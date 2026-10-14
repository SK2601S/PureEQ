import Accelerate
import Cocoa
import CoreAudio
import FlutterMacOS

// Real sound on macOS (14.2+): SK EQ taps the sound of every app with a
// Core Audio process tap, which also mutes the original, runs it through
// the EQ and plays it on the current output device (speakers, headphones…).
//
//   all apps ──tap (original muted)──▶ IO block: biquads + preamp ──▶ output
//
// The tap and the output device are joined in a private aggregate device, so
// one IO callback reads the tapped sound and writes the processed sound.
// SK EQ's own process is excluded from the tap, otherwise its output would
// be tapped again (feedback). When SK EQ quits, macOS removes the tap and the
// original sound comes back by itself.
//
// The filters are designed in Dart (lib/models/eq_filter.dart) for the
// device's sample rate and arrive as ready biquad coefficients.
//
// Channels:
//   skeq/eq        start / stop / setFilters / state; native calls "state"
//                  on Dart whenever the status changes (device switch, error)
//   skeq/spectrum  128 bars (dBFS) of what you hear, ~60 per second, like the
//                  Windows loopback capture (windows/runner/audio_capture.cpp)

final class SystemAudioEQ: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let spectrumChannel: FlutterEventChannel
  private let processor = EQProcessor()
  private let analyzer = SpectrumAnalyzer()

  /// TapEngine (macOS 14.2+), typed loosely so this class builds for 12.0.
  private var engine: AnyObject?
  private var state: [String: Any] = ["status": "checking"]
  private var rebuild: DispatchWorkItem?

  private var spectrumSink: FlutterEventSink?
  private var spectrumTimer: DispatchSourceTimer?
  private let spectrumQueue = DispatchQueue(label: "skeq.spectrum", qos: .userInteractive)

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "skeq/eq", binaryMessenger: messenger)
    spectrumChannel = FlutterEventChannel(name: "skeq/spectrum", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    spectrumChannel.setStreamHandler(self)
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.stopEngine()
    }
  }

  // MARK: - Method channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      start { result($0) }
    case "stop":
      stopEngine()
      setState(["status": "off"], notify: false)
      result(state)
    case "state":
      result(state)
    case "setFilters":
      guard let args = call.arguments as? [String: Any],
        let coefficients = args["coefficients"] as? [Double],
        let preamp = args["preampDb"] as? Double,
        let rate = args["sampleRate"] as? Double
      else {
        result(FlutterError(code: "args", message: "bad setFilters arguments", details: nil))
        return
      }
      // Coefficients only fit the rate they were designed for; after a
      // device switch Dart resends them for the new rate.
      if let current = state["sampleRate"] as? Double, abs(current - rate) < 1 {
        processor.setFilters(coefficients, preampDb: preamp)
      } else {
        processor.setFilters([], preampDb: 0)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setState(_ newState: [String: Any], notify: Bool = true) {
    state = newState
    if notify { methodChannel.invokeMethod("state", arguments: newState) }
  }

  // MARK: - Engine

  private func start(_ done: @escaping ([String: Any]) -> Void) {
    guard #available(macOS 14.2, *) else {
      setState(["status": "unsupported"], notify: false)
      done(state)
      return
    }
    switch AudioCapturePermission.current() {
    case .granted, .unavailable:
      startEngine()
      done(state)
    case .denied:
      setState(["status": "denied"], notify: false)
      done(state)
    case .unknown:
      // First run: macOS asks "Allow SK EQ to record system audio?".
      AudioCapturePermission.request { [weak self] granted in
        guard let self else { return }
        if granted {
          self.startEngine()
        } else {
          self.setState(["status": "denied"], notify: false)
        }
        done(self.state)
      }
    }
  }

  private func startEngine() {
    guard #available(macOS 14.2, *) else { return }
    stopEngine()
    let tapEngine = TapEngine(processor: processor) { [weak self] in
      self?.scheduleRebuild()
    }
    do {
      try tapEngine.start()
      engine = tapEngine
      analyzer.sampleRate = tapEngine.sampleRate
      processor.setFilters([], preampDb: 0)  // until Dart sends the curve
      setState([
        "status": "live",
        "device": tapEngine.deviceName,
        "sampleRate": tapEngine.sampleRate,
      ], notify: false)
    } catch {
      tapEngine.stop()
      setState(["status": "error", "error": "\(error)"], notify: false)
    }
  }

  private func stopEngine() {
    rebuild?.cancel()
    rebuild = nil
    if #available(macOS 14.2, *), let tapEngine = engine as? TapEngine {
      tapEngine.stop()
    }
    engine = nil
    sendSpectrumStopped()
  }

  /// Output device or sample rate changed: start again on the new device.
  /// Debounced, because macOS sends several notifications per switch.
  private func scheduleRebuild() {
    rebuild?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.engine != nil else { return }
      self.startEngine()
      self.methodChannel.invokeMethod("state", arguments: self.state)
    }
    rebuild = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }

  // MARK: - Spectrum (FlutterStreamHandler)

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    spectrumSink = events
    spectrumTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: spectrumQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(16))
    timer.setEventHandler { [weak self] in
      guard let self, self.processor.isRunning else { return }
      let bars = self.analyzer.analyze(self.processor)
      let data = bars.withUnsafeBufferPointer { Data(buffer: $0) }
      DispatchQueue.main.async {
        self.spectrumSink?(FlutterStandardTypedData(float32: data))
      }
    }
    timer.resume()
    spectrumTimer = timer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    spectrumTimer?.cancel()
    spectrumTimer = nil
    spectrumSink = nil
    return nil
  }

  /// Lets the visualizer fall back to its animation instead of freezing.
  private func sendSpectrumStopped() {
    spectrumSink?(FlutterError(code: "stopped", message: "audio engine stopped", details: nil))
  }
}

// MARK: - DSP (runs on the real-time audio thread)

/// The biquad chain, the preamp and a ring buffer of what is played (for the
/// spectrum). New filters are handed over with a try-lock, so the audio
/// thread never waits and never allocates.
final class EQProcessor {
  static let maxSections = 64
  static let ringSize = 4096
  static let scratchFrames = 8192

  private let lock: UnsafeMutablePointer<os_unfair_lock>

  // Written by the main thread under the lock.
  private let pending: UnsafeMutablePointer<Double>
  private var pendingCount = 0
  private var pendingGain = 1.0
  private var pendingVersion = 0

  // Audio thread only.
  private let active: UnsafeMutablePointer<Double>
  private var activeCount = 0
  private var activeGain = 1.0
  private var activeVersion = 0
  private let history: UnsafeMutablePointer<Double>  // 4 per section (L z1 z2, R z1 z2)
  private let left: UnsafeMutablePointer<Float>
  private let right: UnsafeMutablePointer<Float>

  /// Mono copy of the output, read by the spectrum analyzer.
  let ring: UnsafeMutablePointer<Float>
  private(set) var ringPos = 0
  var isRunning = false

  init() {
    lock = .allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    pending = .allocate(capacity: Self.maxSections * 5)
    active = .allocate(capacity: Self.maxSections * 5)
    history = .allocate(capacity: Self.maxSections * 4)
    history.initialize(repeating: 0, count: Self.maxSections * 4)
    left = .allocate(capacity: Self.scratchFrames)
    right = .allocate(capacity: Self.scratchFrames)
    ring = .allocate(capacity: Self.ringSize)
    ring.initialize(repeating: 0, count: Self.ringSize)
  }

  /// Main thread. Empty coefficients = bypass.
  func setFilters(_ coefficients: [Double], preampDb: Double) {
    let count = min(coefficients.count / 5, Self.maxSections)
    os_unfair_lock_lock(lock)
    for i in 0..<count * 5 { pending[i] = coefficients[i] }
    pendingCount = count
    pendingGain = pow(10, preampDb / 20)
    pendingVersion &+= 1
    os_unfair_lock_unlock(lock)
  }

  /// Audio thread: one IO cycle. The tap's buffers come after the output
  /// device's own input streams ([inputSkip] of them).
  func render(input: UnsafeMutableAudioBufferListPointer, inputSkip: Int,
              output: UnsafeMutableAudioBufferListPointer) {
    if os_unfair_lock_trylock(lock) {
      if pendingVersion != activeVersion {
        if pendingCount != activeCount {
          history.update(repeating: 0, count: Self.maxSections * 4)
        }
        active.update(from: pending, count: pendingCount * 5)
        activeCount = pendingCount
        activeGain = pendingGain
        activeVersion = pendingVersion
      }
      os_unfair_lock_unlock(lock)
    }

    // Output size decides the cycle length.
    var frames = 0
    for buffer in output where buffer.mNumberChannels > 0 {
      frames = Int(buffer.mDataByteSize) / (4 * Int(buffer.mNumberChannels))
      break
    }
    frames = min(frames, Self.scratchFrames)
    if frames == 0 { return }

    // Gather the tap's (stereo) channels into left/right.
    var channel = 0
    var inFrames = 0
    var index = 0
    for buffer in input {
      defer { index += 1 }
      if index < inputSkip || channel >= 2 { continue }
      guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
      let n = Int(buffer.mNumberChannels)
      if n == 0 { continue }
      let available = min(Int(buffer.mDataByteSize) / (4 * n), frames)
      inFrames = channel == 0 ? available : min(inFrames, available)
      for c in 0..<n where channel < 2 {
        let target = channel == 0 ? left : right
        for i in 0..<available { target[i] = data[i * n + c] }
        channel += 1
      }
    }
    if channel == 0 { inFrames = 0 }
    if channel == 1 { right.update(from: left, count: inFrames) }
    for i in inFrames..<frames {
      left[i] = 0
      right[i] = 0
    }

    // Biquads (transposed direct form II, in Double for clean low bass).
    let count = activeCount
    let gain = activeGain
    for i in 0..<frames {
      // A tiny offset keeps the filter memory out of slow denormal numbers.
      var l = Double(left[i]) + 1e-20
      var r = Double(right[i]) + 1e-20
      var c = active
      var h = history
      for _ in 0..<count {
        let b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
        let yl = b0 * l + h[0]
        h[0] = b1 * l - a1 * yl + h[1]
        h[1] = b2 * l - a2 * yl
        let yr = b0 * r + h[2]
        h[2] = b1 * r - a1 * yr + h[3]
        h[3] = b2 * r - a2 * yr
        l = yl
        r = yr
        c += 5
        h += 4
      }
      left[i] = Float(l * gain)
      right[i] = Float(r * gain)
      ring[ringPos] = (left[i] + right[i]) * 0.5
      ringPos = (ringPos + 1) % Self.ringSize
    }

    // Left/right to the first two output channels, silence on the rest.
    channel = 0
    for buffer in output {
      guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
      let n = Int(buffer.mNumberChannels)
      let available = n == 0 ? 0 : min(Int(buffer.mDataByteSize) / (4 * n), frames)
      for c in 0..<n {
        let source: UnsafeMutablePointer<Float>? = channel == 0 ? left : channel == 1 ? right : nil
        for i in 0..<available { data[i * n + c] = source?[i] ?? 0 }
        channel += 1
      }
    }
  }
}

// MARK: - Spectrum analysis

/// Same analysis as the Windows capture: Hann-windowed 4096-point FFT of the
/// latest output, 128 log-spaced bars over 10 octaves, dBFS tilted +3 dB per
/// octave around 1 kHz.
final class SpectrumAnalyzer {
  static let barCount = 128
  private static let n = EQProcessor.ringSize
  private static let log2n = vDSP_Length(12)
  private static let axisMinHz = 31.25 / 2.0.squareRoot()
  private static let axisOctaves = 10.0

  private let setup = vDSP_create_fftsetup(SpectrumAnalyzer.log2n, FFTRadix(kFFTRadix2))!
  private let window: [Float]
  private let samples = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumAnalyzer.n)
  private let real = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumAnalyzer.n / 2)
  private let imag = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumAnalyzer.n / 2)
  private var amp = [Double](repeating: 0, count: SpectrumAnalyzer.n / 2)

  /// Sample rate of the running engine (set when it starts).
  var sampleRate = 48000.0

  init() {
    window = (0..<Self.n).map { i in
      Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(Self.n - 1))))
    }
  }

  func analyze(_ processor: EQProcessor) -> [Float] {
    let n = Self.n
    let start = processor.ringPos
    for i in 0..<n {
      samples[i] = processor.ring[(start + i) % n] * window[i]
    }
    var split = DSPSplitComplex(realp: real, imagp: imag)
    samples.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
      vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
    }
    vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))

    // vDSP's real FFT is 2× the plain DFT, so |X|·4/N becomes |V|·2/N:
    // a full-scale sine reads about 1.0 (0 dBFS).
    let scale = 2.0 / Double(n)
    amp[0] = Double(abs(real[0])) * scale / 2
    for k in 1..<n / 2 {
      amp[k] = Double((real[k] * real[k] + imag[k] * imag[k]).squareRoot()) * scale
    }

    let half = n / 2
    let binHz = sampleRate / Double(n)
    var bars = [Float](repeating: 0, count: Self.barCount)
    for j in 0..<Self.barCount {
      let fLo = Self.axisMinHz * pow(2, Self.axisOctaves * Double(j) / Double(Self.barCount))
      let fHi = Self.axisMinHz * pow(2, Self.axisOctaves * Double(j + 1) / Double(Self.barCount))
      let fMid = (fLo * fHi).squareRoot()
      var value = 0.0
      let kLo = fLo / binHz
      let kHi = fHi / binHz
      if kHi - kLo < 1 {
        // Narrower than one bin (low frequencies): interpolate.
        let k = fMid / binHz
        let k0 = Int(k)
        let t = k - Double(k0)
        if k0 + 1 < half { value = amp[k0] * (1 - t) + amp[k0 + 1] * t }
      } else {
        var k = Int(kLo.rounded(.up))
        while k <= Int(kHi) && k < half {
          value = max(value, amp[k])
          k += 1
        }
      }
      bars[j] = Float(20 * log10(value + 1e-9) + 3 * log2(fMid / 1000))
    }
    return bars
  }
}

// MARK: - Core Audio tap + aggregate device (macOS 14.2+)

struct AudioError: Error, CustomStringConvertible {
  let description: String
}

private func check(_ status: OSStatus, _ what: String) throws {
  guard status == noErr else { throw AudioError(description: "\(what) failed (\(status))") }
}

private func address(_ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
  -> AudioObjectPropertyAddress
{
  AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                             mElement: kAudioObjectPropertyElementMain)
}

private func readValue<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          _ initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
  throws -> T
{
  var addr = address(selector, scope)
  var size = UInt32(MemoryLayout<T>.size)
  var value = initial
  try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value),
            "Reading audio property \(selector)")
  return value
}

private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws
  -> String
{
  var addr = address(selector)
  var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
  var value: Unmanaged<CFString>?
  let status = withUnsafeMutablePointer(to: &value) {
    AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
  }
  try check(status, "Reading audio property \(selector)")
  guard let string = value?.takeRetainedValue() else {
    throw AudioError(description: "Audio property \(selector) is empty")
  }
  return string as String
}

/// The tap description takes the process list as [AudioObjectID] or
/// [NSNumber] depending on the SDK; this fits either.
private func processList<T>(_ ids: [AudioObjectID]) -> [T] {
  ids.map { NSNumber(value: $0) as! T }
}

@available(macOS 14.2, *)
final class TapEngine {
  private let processor: EQProcessor
  private let onDeviceChange: () -> Void

  private(set) var sampleRate = 48000.0
  private(set) var deviceName = ""
  private var outputID = AudioObjectID(kAudioObjectUnknown)
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

  init(processor: EQProcessor, onDeviceChange: @escaping () -> Void) {
    self.processor = processor
    self.onDeviceChange = onDeviceChange
  }

  func start() throws {
    let system = AudioObjectID(kAudioObjectSystemObject)
    outputID = try readValue(system, kAudioHardwarePropertyDefaultOutputDevice,
                             AudioObjectID(kAudioObjectUnknown))
    guard outputID != kAudioObjectUnknown else {
      throw AudioError(description: "No output device")
    }
    let outputUID = try readString(outputID, kAudioDevicePropertyDeviceUID)
    deviceName = (try? readString(outputID, kAudioObjectPropertyName)) ?? "Output"

    // Exclude SK EQ itself, or its own output would be tapped again.
    var pid = getpid()
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var ownProcess = AudioObjectID(kAudioObjectUnknown)
    try check(AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid,
                                         &size, &ownProcess),
              "Finding SK EQ's audio process")
    guard ownProcess != kAudioObjectUnknown else {
      throw AudioError(description: "SK EQ's audio process was not found")
    }

    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: processList([ownProcess]))
    description.muteBehavior = .mutedWhenTapped
    try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating the audio tap")

    let format = try readValue(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
    guard format.mFormatID == kAudioFormatLinearPCM,
      format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
    else {
      throw AudioError(description: "Unexpected tap format")
    }

    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "SK EQ",
      kAudioAggregateDeviceUIDKey: "skeq-\(UUID().uuidString)",
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapDriftCompensationKey: true,
          kAudioSubTapUIDKey: description.uuid.uuidString,
        ]
      ],
    ]
    try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
              "Creating the SK EQ audio device")

    sampleRate = try readValue(aggregateID, kAudioDevicePropertyNominalSampleRate, Float64(0))
    if sampleRate <= 0 { sampleRate = format.mSampleRate }

    // The output device's own inputs (e.g. a headset microphone) come before
    // the tap in the aggregate's input buffers.
    let inputSkip = streamCount(outputID, scope: kAudioObjectPropertyScopeInput)
    let processor = self.processor
    try check(
      AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
        _, inInputData, _, outOutputData, _ in
        processor.render(
          input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData)),
          inputSkip: inputSkip,
          output: UnsafeMutableAudioBufferListPointer(outOutputData))
      }, "Creating the audio callback")
    if inputSkip > 0 { switchOffInputs(count: inputSkip) }

    processor.isRunning = true
    try check(AudioDeviceStart(aggregateID, procID), "Starting audio")

    listen(system, address(kAudioHardwarePropertyDefaultOutputDevice))
    listen(outputID, address(kAudioDevicePropertyNominalSampleRate))
    listen(outputID, address(kAudioDevicePropertyDeviceIsAlive))
  }

  func stop() {
    processor.isRunning = false
    for (object, addr, block) in listeners {
      var a = addr
      AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
    }
    listeners.removeAll()
    if aggregateID != kAudioObjectUnknown {
      if let procID {
        AudioDeviceStop(aggregateID, procID)
        AudioDeviceDestroyIOProcID(aggregateID, procID)
      }
      AudioHardwareDestroyAggregateDevice(aggregateID)
    }
    procID = nil
    aggregateID = AudioObjectID(kAudioObjectUnknown)
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    tapID = AudioObjectID(kAudioObjectUnknown)
  }

  private func listen(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) {
    let block: AudioObjectPropertyListenerBlock = { [onDeviceChange] _, _ in onDeviceChange() }
    var a = addr
    if AudioObjectAddPropertyListenerBlock(object, &a, DispatchQueue.main, block) == noErr {
      listeners.append((object, addr, block))
    }
  }

  private func streamCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var addr = address(kAudioDevicePropertyStreams, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return 0 }
    return Int(size) / MemoryLayout<AudioStreamID>.size
  }

  /// Tells macOS the callback doesn't use the output device's microphone,
  /// so it isn't switched on (Bluetooth headsets would drop to call quality).
  /// Best effort: if this fails the sound still works.
  private func switchOffInputs(count: Int) {
    guard let procID else { return }
    var addr = address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(aggregateID, &addr, 0, nil, &size) == noErr,
      size >= 16
    else { return }
    // struct { void *mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { raw.deallocate() }
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
    raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self),
                   as: UnsafeMutableRawPointer.self)
    guard AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, raw) == noErr else { return }
    let streams = Int(raw.load(fromByteOffset: 8, as: UInt32.self))
    for i in 0..<min(count, streams) {
      raw.storeBytes(of: UInt32(0), toByteOffset: 12 + 4 * i, as: UInt32.self)
    }
    AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, size, raw)
  }
}

// MARK: - "Record system audio" permission

/// macOS has no public call to check this permission, so SK EQ uses the
/// TCC framework directly, like other system-audio apps. Without it, a denied
/// tap would deliver silence while still muting every app.
enum AudioCapturePermission {
  enum State { case granted, denied, unknown, unavailable }

  private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
  private typealias Request = @convention(c) (
    CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void
  ) -> Void

  private static let tcc = dlopen(
    "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
  private static let service = "kTCCServiceAudioCapture" as CFString

  static func current() -> State {
    guard let handle = tcc, let symbol = dlsym(handle, "TCCAccessPreflight") else {
      return .unavailable
    }
    switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
    case 0: return .granted
    case 1: return .denied
    default: return .unknown
    }
  }

  static func request(_ done: @escaping (Bool) -> Void) {
    guard let handle = tcc, let symbol = dlsym(handle, "TCCAccessRequest") else {
      done(false)
      return
    }
    unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in
      DispatchQueue.main.async { done(granted) }
    }
  }
}
