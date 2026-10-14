import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/eq_band.dart';
import '../../providers/eq_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/volume_provider.dart';
import '../../providers/window_provider.dart';
import '../../theme/app_theme.dart';
import 'eq_curve.dart';

/// Real-time spectrum analyzer (thin glowing bars with peak-hold dots) with
/// the interactive EQ curve layered on top.
///
/// Capturing system-wide audio needs a loopback driver (WASAPI loopback on
/// Windows, a virtual device such as BlackHole on macOS), so the signal here
/// is *simulated*: a synthetic groove of kick, snare, hi-hats and a wandering
/// melody. It is shaped by the real EQ curve and master volume, so every
/// control has a visible effect. To show real audio, feed FFT magnitudes into
/// [SpectrumSimulation.levels] instead of synthesising them in `step`.
///
/// Performance: an adaptive frame pacer runs the spectrum at ~30 fps when
/// idle and at the full display rate while anything moves; it stops entirely
/// while the window is minimized or in the tray. Only the bars repaint each
/// frame (no widget rebuilds); the bars are drawn as raw GPU triangles and
/// glows avoid blur filters. The curve repaints only while it is moving.
class SpectrumVisualizer extends ConsumerStatefulWidget {
  const SpectrumVisualizer({
    super.key,
    this.showOutput = true,
    this.showCurve = true,
  });

  /// Toggles for the "Output" (bars) and "EQ curve" layers.
  final bool showOutput;
  final bool showCurve;

  @override
  ConsumerState<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends ConsumerState<SpectrumVisualizer> {
  final SpectrumSimulation _sim = SpectrumSimulation(barCount: 128);
  late final AppLifecycleListener _lifecycle;
  bool? _lastCompare;

  // --- Frame pacing --------------------------------------------------------
  //
  // On desktop Flutter re-renders the *whole window* for every frame, so the
  // frame rate is what costs CPU — not the drawing code. The spectrum
  // therefore runs at ~30 fps when idle (plenty for an analyzer, and half
  // the cost) and switches to the full display rate only while something
  // moves: curve drags, preset transitions, A/B switches. Frames are still
  // requested through the scheduler, so they stay aligned to vsync.

  /// Delay before requesting the next frame at the idle rate (Settings →
  /// Spectrum quality): the frame then lands on the following vsync, e.g.
  /// 22 ms ≈ 30 fps at 60 Hz ("Balanced").
  Duration _idleDelay = SpectrumQuality.balanced.idleDelay;

  /// While silent and settled (nothing playing, nothing moving), check for
  /// sound only a few times a second.
  static const Duration _quietDelay = Duration(milliseconds: 150);

  Timer? _timer;
  int? _frameCallbackId;
  Duration? _lastFrame;

  /// Real-time spectrum of what is playing (Windows: see
  /// windows/runner/audio_capture.cpp; macOS 14.2+ while real sound is on:
  /// macos/Runner/SystemAudioEQ.swift). Cancelled while paused, which also
  /// stops the native analysis.
  static const _liveChannel = EventChannel('skeq/spectrum');
  StreamSubscription<dynamic>? _liveSub;

  /// "Playing" (for the play/pause button) as soon as there is sound;
  /// "stopped" only after ~1 s of silence, so quiet gaps don't flicker it.
  DateTime _lastSound = DateTime.fromMillisecondsSinceEpoch(0);

  void _updatePlaying(bool hasSound) {
    final now = DateTime.now();
    if (hasSound) _lastSound = now;
    final playing =
        now.difference(_lastSound) < const Duration(milliseconds: 1000);
    final notifier = ref.read(audioPlayingProvider.notifier);
    if (notifier.state != playing) notifier.state = playing;
  }

  void _syncLiveInput() {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (_paused) {
      _liveSub?.cancel();
      _liveSub = null;
      _sim.clearLive();
    } else {
      _liveSub ??= _liveChannel.receiveBroadcastStream().listen(
        (frame) {
          if (frame is Float32List) {
            _sim.pushLive(frame);
            _updatePlaying(_sim.liveHasSignal);
            // Sound after silence: wake the pacer right away.
            if (_timer != null && _sim.isQuiet && _sim.liveHasSignal) {
              _timer!.cancel();
              _timer = null;
              if (!_paused) _requestFrame();
            }
          }
        },
        onError: (Object _) => _sim.clearLive(),
      );
    }
  }

  /// Pause sources: window events (minimize / tray) and the OS lifecycle.
  /// While paused no frames are requested at all — 0 CPU / GPU.
  bool _windowHidden = false;
  bool _lifecycleHidden = false;
  bool get _paused => _windowHidden || _lifecycleHidden;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      _lifecycleHidden =
          s == AppLifecycleState.hidden || s == AppLifecycleState.paused;
      _syncPacer();
    });
    _syncLiveInput();
    _requestFrame();
  }

  void _requestFrame() {
    _frameCallbackId ??=
        SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    _frameCallbackId = null;
    // Clamp dt so a stall (window drag, resume from pause) doesn't jump.
    final last = _lastFrame;
    final dt = last == null
        ? 1 / 60
        : ((timestamp - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastFrame = timestamp;
    _sim.step(dt);
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_paused || _frameCallbackId != null) return;
    if (_sim.needsFullRate) {
      // Motion: skip any pending idle delay and render on the next vsync.
      _timer?.cancel();
      _timer = null;
      _requestFrame();
    } else {
      _timer ??= Timer(_sim.isQuiet ? _quietDelay : _idleDelay, () {
        _timer = null;
        if (!_paused) _requestFrame();
      });
    }
  }

  /// Starts or stops the frame loop to match [_paused].
  void _syncPacer() {
    _syncLiveInput();
    if (_paused) {
      _timer?.cancel();
      _timer = null;
      final id = _frameCallbackId;
      if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _frameCallbackId = null;
      _lastFrame = null;
    } else {
      _scheduleNext();
    }
  }

  @override
  void dispose() {
    _windowHidden = true; // stops the loop
    _syncPacer();
    _lifecycle.dispose();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eq = ref.watch(eqProvider);
    final volume = ref.watch(volumeProvider);
    _idleDelay =
        ref.watch(settingsProvider.select((s) => s.spectrumQuality)).idleDelay;
    final look = ref.watch(settingsProvider
        .select((s) => (s.spectrumStyle, s.barDensity.columns, s.showPeaks)));
    final motion =
        ref.watch(settingsProvider.select((s) => (s.motion, s.smoothBars)));
    _sim
      ..attackRate = motion.$1.attack
      ..releaseRate = motion.$1.release
      ..peakFall = motion.$1.peakFall
      ..peakHoldSeconds = motion.$1.peakHold
      ..smoothBars = motion.$2;
    final hidden = !ref.watch(windowVisibleProvider);
    if (hidden != _windowHidden) {
      _windowHidden = hidden;
      _syncPacer();
    }

    // A/B switches must be heard (and seen) instantly; everything else eases.
    final compareChanged =
        _lastCompare != null && _lastCompare != eq.compareBypass;
    _lastCompare = eq.compareBypass;

    _sim
      ..setTargets(
        curve: eq.effectiveGains,
        processing: eq.isProcessing,
        instant: compareChanged,
      )
      ..outputLevel = volume.muted ? 0 : volume.volume;
    // A new target means motion: switch to the full rate right away.
    _scheduleNext();

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _SpectrumPainter(
              _sim,
              showOutput: widget.showOutput,
              style: look.$1,
              columns: look.$2,
              showPeaks: look.$3,
            ),
          ),
        ),
        if (widget.showCurve) EqCurveOverlay(sim: _sim),
      ],
    );
  }
}

/// Generates a plausible music spectrum and smooths it like a real analyzer
/// (fast attack, slower release, peak-hold dots that wait, then fall).
class SpectrumSimulation extends ChangeNotifier {
  SpectrumSimulation({required this.barCount})
      : frequencies = List.generate(
            barCount, (j) => axisToFrequency((j + 0.5) / barCount)),
        levels = List.filled(barCount, 0.0),
        peaks = List.filled(barCount, 0.0),
        _peakHold = List.filled(barCount, 0.0),
        _phaseA =
            List.generate(barCount, (_) => _rand.nextDouble() * math.pi * 2),
        _phaseB =
            List.generate(barCount, (_) => _rand.nextDouble() * math.pi * 2);

  static final math.Random _rand = math.Random();

  final int barCount;

  /// Center frequency of each bar (log-spaced on the shared axis).
  final List<double> frequencies;

  /// Bar heights and peak-dot positions, 0..1.
  final List<double> levels;
  final List<double> peaks;

  /// The EQ curve as drawn: eases toward the target, follows drags exactly.
  final List<double> curveGains = List.filled(kBandCount, 0.0);

  /// The EQ actually applied to the simulated audio (0 dB when bypassed).
  final List<double> appliedGains = List.filled(kBandCount, 0.0);

  /// 1 while the EQ is processing, 0 when off / bypassed. Used to dim the curve.
  double activeMix = 1;

  /// Set by the curve overlay while the user drags a point.
  bool dragging = false;

  /// Notifies only on frames where the curve moved, so the (static most of
  /// the time) curve layer isn't repainted 60 times a second for nothing.
  final ChangeNotifier curveChanged = ChangeNotifier();

  double outputLevel = 0.5;

  List<double> _targetCurve = List.filled(kBandCount, 0.0);
  bool _processing = true;
  bool _initialised = false;
  bool _curveDirty = true; // force a curve repaint on the next step
  bool _curveMoving = true;

  /// True while the curve is animating or being dragged: the visualizer then
  /// renders at the full display rate instead of the ~30 fps idle rate.
  bool get needsFullRate => dragging || _curveMoving;

  final List<double> _peakHold;
  final List<double> _phaseA;
  final List<double> _phaseB;
  double _time = 0;
  double _smoothedOutput = 0.5;

  static const double _bpm = 124;
  static const double _dbRange = 66; // dB span from silent to full-scale bar

  // --- Real audio (Windows) ------------------------------------------------
  //
  // When the native side streams the spectrum of what is actually playing
  // (WASAPI loopback, see windows/runner/audio_capture.cpp), the bars show
  // that instead of the synthetic groove. Values are dBFS per bar, already
  // tilted +3 dB/octave; silence arrives as very low values, so the bars fall.

  /// Display window for real input, in dBFS: [_liveFloorDb] = empty bar,
  /// [_liveFloorDb] + [_liveRangeDb] = full bar.
  static const double _liveFloorDb = -78;
  static const double _liveRangeDb = 66;

  List<double>? _live;

  /// True once real audio frames are being received.
  bool get hasLiveInput => _live != null;

  /// Called for every frame from the native capture.
  void pushLive(List<double> dbPerBar) {
    if (dbPerBar.length == barCount) _live = dbPerBar;
  }

  /// Live input stopped (window hidden / capture unavailable).
  void clearLive() => _live = null;

  /// Whether the latest live frame contains audible sound.
  bool get liveHasSignal {
    final live = _live;
    if (live == null) return false;
    for (final db in live) {
      if (db > _liveFloorDb) return true;
    }
    return false;
  }

  /// Nothing to show and nothing moving: the visualizer can slow right down.
  bool get isQuiet {
    if (needsFullRate) return false;
    for (var j = 0; j < barCount; j++) {
      if (levels[j] > 0.003 || peaks[j] > 0.003) return false;
    }
    return true;
  }

  /// Updates what the simulation eases toward. With [instant] (A/B switch)
  /// the processed signal jumps immediately instead of gliding.
  void setTargets({
    required List<double> curve,
    required bool processing,
    bool instant = false,
  }) {
    for (var i = 0; i < kBandCount; i++) {
      if (curve[i] != _targetCurve[i]) _curveMoving = true;
    }
    if (processing != _processing) _curveMoving = true;
    _targetCurve = curve;
    _processing = processing;

    // While dragging, the curve must sit under the cursor in this very frame.
    if (dragging) {
      for (var i = 0; i < kBandCount; i++) {
        curveGains[i] = curve[i];
        if (processing) appliedGains[i] = curve[i];
      }
      curveChanged.notifyListeners();
    }
    if (instant || !_initialised) {
      for (var i = 0; i < kBandCount; i++) {
        appliedGains[i] = processing ? curve[i] : 0;
        if (!_initialised) curveGains[i] = curve[i];
      }
      activeMix = processing ? 1 : 0;
      _initialised = true;
      _curveDirty = true;
      curveChanged.notifyListeners();
    }
  }

  void step(double dt) {
    _time += dt;

    // Exponential easing toward the targets (≈ 0.3 s to settle).
    final ease = 1 - math.exp(-dt * 10);
    var curveMoved = _curveDirty;
    _curveDirty = false;
    for (var i = 0; i < kBandCount; i++) {
      final target = _targetCurve[i];
      final next = dragging ? target : _settle(curveGains[i], target, ease);
      if (next != curveGains[i]) curveMoved = true;
      curveGains[i] = next;
      final applied = _processing ? target : 0.0;
      appliedGains[i] = dragging && _processing
          ? applied
          : _settle(appliedGains[i], applied, ease);
    }
    final mix = _settle(activeMix, _processing ? 1.0 : 0.0, ease);
    if (mix != activeMix) curveMoved = true;
    activeMix = mix;
    if (curveMoved) curveChanged.notifyListeners();
    _curveMoving = curveMoved;
    _smoothedOutput += (outputLevel - _smoothedOutput) * ease;

    // Rhythm envelopes (exponential decays retriggered on the beat grid).
    const beat = 60 / _bpm;
    final kick = math.exp(-(_time % beat) * 10);
    final snare = math.exp(-((_time + beat) % (beat * 2)) * 12);
    final hat = 0.25 + 0.75 * math.exp(-(_time % (beat / 2)) * 28);

    // Two "melodic" partials that wander across the mids.
    final melodyA =
        math.log(600 * math.pow(2, 1.6 * math.sin(_time * 0.7))) / math.ln2;
    final melodyB =
        math.log(2400 * math.pow(2, math.sin(_time * 0.43 + 1))) / math.ln2;

    final volumeDb = _smoothedOutput <= 0.001
        ? -120.0
        : 20 * math.log(_smoothedOutput) / math.ln10;

    // Rise/fall speeds come from Settings → Spectrum → Motion.
    final attack = 1 - math.exp(-dt * attackRate);
    final release = 1 - math.exp(-dt * releaseRate);
    final log40 = math.log(40) / math.ln2;
    final log900 = math.log(900) / math.ln2;
    final log4k = math.log(4000) / math.ln2;

    // Pass 1: where each bar wants to be.
    final live = _live;
    for (var j = 0; j < barCount; j++) {
      _targets[j] = live != null
          // Real audio: what you hear (already processed by the system EQ).
          ? ((live[j] - _liveFloorDb) / _liveRangeDb).clamp(0.0, 1.0)
          : _syntheticLevel(j, kick, snare, hat, melodyA, melodyB, volumeDb,
              log40, log900, log4k);
    }

    // Optional "Smooth bars": blend each bar with its neighbours (1-2-3-2-1
    // kernel) so the shape reads as a soft curve instead of jagged spikes.
    if (smoothBars) {
      for (var j = 0; j < barCount; j++) {
        var sum = 0.0, weight = 0.0;
        for (var k = -2; k <= 2; k++) {
          final i = j + k;
          if (i < 0 || i >= barCount) continue;
          final w = 3.0 - k.abs();
          sum += _targets[i] * w;
          weight += w;
        }
        _blended[j] = sum / weight;
      }
    }
    final targets = smoothBars ? _blended : _targets;

    // Pass 2: ease toward the targets (fast attack, slower release).
    for (var j = 0; j < barCount; j++) {
      final target = targets[j];
      final current = levels[j];
      levels[j] =
          current + (target - current) * (target > current ? attack : release);

      // Peak hold: wait a moment at the max, then fall.
      if (levels[j] >= peaks[j]) {
        peaks[j] = levels[j];
        _peakHold[j] = peakHoldSeconds;
      } else if (_peakHold[j] > 0) {
        _peakHold[j] -= dt;
      } else {
        peaks[j] = math.max(levels[j], peaks[j] - dt * peakFall);
      }
    }

    notifyListeners();
  }

  // Motion (Settings → Spectrum): rise / fall speeds and peak behaviour.
  double attackRate = 38;
  double releaseRate = 7;
  double peakFall = 0.45;
  double peakHoldSeconds = 0.6;
  bool smoothBars = false;

  late final List<double> _targets = List.filled(barCount, 0.0);
  late final List<double> _blended = List.filled(barCount, 0.0);

  /// One bar of the synthetic groove (used where real audio isn't available).
  double _syntheticLevel(
      int j,
      double kick,
      double snare,
      double hat,
      double melodyA,
      double melodyB,
      double volumeDb,
      double log40,
      double log900,
      double log4k) {
    {
      final f = frequencies[j];
      final t = j / (barCount - 1);
      final oct = math.log(f) / math.ln2;

      // Pink-ish tilt plus slow per-bar movement and a little jitter.
      var db = -20 - 14 * t;
      db += 3.5 * math.sin(_time * (1.1 + j * 0.07) + _phaseA[j]);
      db += 2.5 * math.sin(_time * (2.7 + j * 0.03) + _phaseB[j]);
      db += (_rand.nextDouble() - 0.5) * 4;

      db +=
          22 * kick * (1 - (oct - log40) / 2).clamp(0.0, 1.0); // kick < 160 Hz
      final sn = oct - log900;
      db += 12 * snare * math.exp(-sn * sn / 3); // snare around 900 Hz
      db += 14 * hat * ((oct - log4k) / 2).clamp(0.0, 1.0); // hats, top octaves
      final ma = oct - melodyA;
      final mb = oct - melodyB;
      db += 12 * math.exp(-ma * ma / 0.25) + 8 * math.exp(-mb * mb / 0.2);

      // Apply the EQ (as heard) and the master volume.
      db += interpolateGain(appliedGains, f);
      db += volumeDb;

      return ((db + _dbRange) / _dbRange).clamp(0.0, 1.0);
    }
  }

  /// Eases [from] toward [to], snapping once within 0.001 so the value
  /// actually settles (and the curve can stop repainting).
  static double _settle(double from, double to, double ease) {
    final next = from + (to - from) * ease;
    return (next - to).abs() < 0.001 ? to : next;
  }

  @override
  void dispose() {
    curveChanged.dispose();
    super.dispose();
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(
    this.sim, {
    required this.showOutput,
    required this.style,
    required this.columns,
    required this.showPeaks,
  }) : super(repaint: sim);

  final SpectrumSimulation sim;
  final bool showOutput;

  /// Look chosen in Settings → Spectrum.
  final SpectrumStyle style;

  /// Number of columns drawn (128 / 64 / 32); the 128 analysed bars are
  /// merged by taking the loudest of each group.
  final int columns;
  final bool showPeaks;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _paintGrid(canvas, size);
    if (!showOutput) return;
    _group();
    _preparePaints(size);
    switch (style) {
      case SpectrumStyle.bars:
        _paintBars(canvas, size);
      case SpectrumStyle.mirror:
        _paintMirror(canvas, size);
      case SpectrumStyle.led:
        _paintLed(canvas, size);
      case SpectrumStyle.wave:
        _paintWave(canvas, size);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final geo = CurveGeometry(size);
    final line = Paint()..strokeWidth = 1;

    // Horizontal lines at the dB marks of the scale on the left.
    for (final db in [12.0, 6.0, 0.0, -6.0, -12.0]) {
      line.color = AppColors.overlay.withValues(alpha: db == 0 ? 0.09 : 0.04);
      final y = geo.yForDb(db).roundToDouble() + 0.5; // crisp 1px lines
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // Vertical lines through each band (they line up with the sliders).
    line.color = AppColors.overlay.withValues(alpha: 0.03);
    for (var i = 0; i < kBandCount; i++) {
      final x = geo.xForBand(i).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  // --- Column levels -------------------------------------------------------

  late final List<double> _level = List.filled(columns, 0.0);
  late final List<double> _peak = List.filled(columns, 0.0);

  void _group() {
    final g = math.max(1, sim.barCount ~/ columns);
    for (var c = 0; c < columns; c++) {
      var lv = 0.0, pk = 0.0;
      for (var j = c * g; j < (c + 1) * g && j < sim.barCount; j++) {
        lv = math.max(lv, sim.levels[j]);
        pk = math.max(pk, sim.peaks[j]);
      }
      _level[c] = lv;
      _peak[c] = pk;
    }
  }

  // --- GPU quads -----------------------------------------------------------
  //
  // Bars change every frame, so they are sent to the GPU as raw triangles
  // (one draw call per layer) instead of as Paths: a path of many rounded
  // rects is re-tessellated on the CPU every frame, which kept a whole core
  // busy on integrated graphics. Buffers are reused between frames.

  Float32List _main = Float32List(0);
  Float32List _halo = Float32List(0);
  int _mainCount = 0;
  int _haloCount = 0;

  static Float32List _fit(Float32List buf, int quads) =>
      buf.length >= quads * 12 ? buf : Float32List(quads * 12);

  void _begin(int maxQuads, {bool halo = true}) {
    _main = _fit(_main, maxQuads);
    if (halo) _halo = _fit(_halo, maxQuads);
    _mainCount = 0;
    _haloCount = 0;
  }

  /// Appends one rectangle (two triangles).
  static void _quad(
      Float32List v, int i, double l, double t, double r, double b) {
    final k = i * 12;
    v
      ..[k] = l
      ..[k + 1] = t
      ..[k + 2] = r
      ..[k + 3] = t
      ..[k + 4] = l
      ..[k + 5] = b
      ..[k + 6] = r
      ..[k + 7] = t
      ..[k + 8] = r
      ..[k + 9] = b
      ..[k + 10] = l
      ..[k + 11] = b;
  }

  void _addMain(double l, double t, double r, double b) =>
      _quad(_main, _mainCount++, l, t, r, b);
  void _addHalo(double l, double t, double r, double b) =>
      _quad(_halo, _haloCount++, l, t, r, b);

  /// Without texture coordinates the shader is mapped by position, so the
  /// gradients look exactly as they would on rectangles.
  static void _draw(Canvas canvas, Float32List buf, int count, Paint paint) {
    if (count == 0) return;
    final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles, Float32List.sublistView(buf, 0, count * 12));
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
  }

  // --- Paints (gradients depend only on size and style) ---------------------

  Size? _paintSize;
  late Paint _barPaint;
  late Paint _haloPaint;
  late Paint _peakHaloPaint;
  late Paint _peakPaint;

  void _preparePaints(Size size) {
    if (_paintSize == size) return;
    _paintSize = size;
    final rect = Offset.zero & size;
    final mirror = style == SpectrumStyle.mirror;
    // Deep at the floor (or centre line, for Mirror) → accent → bright tips.
    _barPaint = Paint()
      ..shader = LinearGradient(
        begin: mirror ? Alignment.topCenter : Alignment.bottomCenter,
        end: mirror ? Alignment.bottomCenter : Alignment.topCenter,
        colors: mirror
            ? [
                AppColors.accentSoft,
                AppColors.accent.withValues(alpha: 0.85),
                AppColors.accentDeep.withValues(alpha: 0.35),
                AppColors.accent.withValues(alpha: 0.85),
                AppColors.accentSoft,
              ]
            : [
                AppColors.accentDeep.withValues(alpha: 0.25),
                AppColors.accent.withValues(alpha: 0.85),
                AppColors.accentSoft,
              ],
        stops: mirror ? const [0, 0.3, 0.5, 0.7, 1] : const [0, 0.6, 1],
      ).createShader(rect);
    // Halo: glow faked with a wider translucent copy (a blur filter would be
    // far more expensive every frame).
    _haloPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.accent.withValues(alpha: mirror ? 0.12 : 0.02),
          AppColors.accent.withValues(alpha: 0.16)
        ],
      ).createShader(rect);
    _peakHaloPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: 0.22);
    _peakPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accentSoft;
  }

  void _paintPeaks(Canvas canvas, List<Offset> points, double r) {
    if (!showPeaks || points.isEmpty) return;
    canvas
      ..drawPoints(ui.PointMode.points, points,
          _peakHaloPaint..strokeWidth = (r + 2.5) * 2)
      ..drawPoints(
          ui.PointMode.points, points, _peakPaint..strokeWidth = r * 2);
  }

  // --- Styles ----------------------------------------------------------------

  /// Classic bars rising from the floor, with peak-hold dots.
  void _paintBars(Canvas canvas, Size size) {
    final colW = size.width / columns;
    final barW = math.max(1.5, colW * 0.56);
    final haloW = math.min(colW * 0.95, barW + 4);
    final dotR = (barW * 0.35).clamp(1.4, 3.0);
    final maxH = size.height - 8;
    final floor = size.height;
    final peaks = <Offset>[];
    _begin(columns);
    for (var c = 0; c < columns; c++) {
      final cx = (c + 0.5) * colW;
      final top = floor - math.max(_level[c] * maxH, 2.0);
      _addMain(cx - barW / 2, top, cx + barW / 2, floor);
      _addHalo(cx - haloW / 2, top - 2, cx + haloW / 2, floor);
      peaks.add(Offset(cx, floor - _peak[c] * maxH - dotR - 3));
    }
    _draw(canvas, _halo, _haloCount, _haloPaint);
    _draw(canvas, _main, _mainCount, _barPaint);
    _paintPeaks(canvas, peaks, dotR);
  }

  /// Bars growing up and down from the centre line.
  void _paintMirror(Canvas canvas, Size size) {
    final colW = size.width / columns;
    final barW = math.max(1.5, colW * 0.56);
    final haloW = math.min(colW * 0.95, barW + 4);
    final dotR = (barW * 0.35).clamp(1.4, 3.0);
    final mid = size.height / 2;
    final maxH = mid - 6;
    final peaks = <Offset>[];
    _begin(columns);
    for (var c = 0; c < columns; c++) {
      final cx = (c + 0.5) * colW;
      final h = math.max(_level[c] * maxH, 1.0);
      _addMain(cx - barW / 2, mid - h, cx + barW / 2, mid + h);
      _addHalo(cx - haloW / 2, mid - h - 2, cx + haloW / 2, mid + h + 2);
      final p = _peak[c] * maxH + dotR + 3;
      peaks
        ..add(Offset(cx, mid - p))
        ..add(Offset(cx, mid + p));
    }
    _draw(canvas, _halo, _haloCount, _haloPaint);
    _draw(canvas, _main, _mainCount, _barPaint);
    _paintPeaks(canvas, peaks, dotR);
  }

  /// Segmented "hi-fi" blocks; the peak lights a single block.
  void _paintLed(Canvas canvas, Size size) {
    final colW = size.width / columns;
    final barW = math.max(2.0, colW * 0.7);
    final maxH = size.height - 4;
    final floor = size.height;
    final step = columns >= 128 ? 5.0 : 7.0; // block + gap
    final block = step - 2;
    final maxBlocks = (maxH / step).floor();
    _begin(columns * (maxBlocks + 1), halo: false);
    final peakBlocks = <Offset>[];
    for (var c = 0; c < columns; c++) {
      final x = (c + 0.5) * colW - barW / 2;
      final lit = (_level[c] * maxBlocks).floor();
      for (var k = 0; k < lit; k++) {
        final b = floor - k * step;
        _addMain(x, b - block, x + barW, b);
      }
      if (showPeaks) {
        final pk = (_peak[c] * maxBlocks).floor();
        if (pk > lit) peakBlocks.add(Offset(x, floor - pk * step));
      }
    }
    _draw(canvas, _main, _mainCount, _barPaint);
    for (final o in peakBlocks) {
      canvas.drawRect(
          Rect.fromLTWH(o.dx, o.dy - block, barW, block), _peakPaint);
    }
  }

  /// One smooth glowing line with a filled area underneath.
  void _paintWave(Canvas canvas, Size size) {
    final colW = size.width / columns;
    final maxH = size.height - 10;
    final floor = size.height;
    final pts = [
      Offset(0, floor - _level[0] * maxH),
      for (var c = 0; c < columns; c++)
        Offset((c + 0.5) * colW, floor - _level[c] * maxH),
      Offset(size.width, floor - _level[columns - 1] * maxH),
    ];
    // Quadratic curves through the midpoints give a smooth line.
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset(
          (pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      line.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);
    final area = Path.from(line)
      ..lineTo(size.width, floor)
      ..lineTo(0, floor)
      ..close();
    final rect = Offset.zero & size;
    canvas
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accent.withValues(alpha: 0.45),
              AppColors.accentDeep.withValues(alpha: 0.04)
            ],
          ).createShader(rect),
      )
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.accent.withValues(alpha: 0.18),
      )
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.accentSoft,
      );
    if (showPeaks) {
      _paintPeaks(
          canvas,
          [
            for (var c = 0; c < columns; c++)
              Offset((c + 0.5) * colW, floor - _peak[c] * maxH - 4),
          ],
          columns >= 128 ? 1.4 : 2.2);
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.sim != sim ||
      old.showOutput != showOutput ||
      old.style != style ||
      old.columns != columns ||
      old.showPeaks != showPeaks;
}
