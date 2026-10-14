import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/eq_filter.dart';
import '../services/apo_service.dart';
import '../services/mac_audio_service.dart';
import 'eq_provider.dart';

final apoServiceProvider = Provider<ApoService>((ref) => ApoService());
final macAudioServiceProvider =
    Provider<MacAudioService>((ref) => MacAudioService());

/// Whether (and where) SK EQ changes the real system sound.
final soundProvider =
    NotifierProvider<SoundNotifier, SoundState>(SoundNotifier.new);

enum SoundStatus {
  checking,

  /// No system-wide processing on this system (macOS older than 14.2).
  unsupported,

  /// macOS: SK EQ may not record system audio (Privacy & Security).
  needsPermission,

  /// macOS: the user turned real sound off.
  off,

  /// Equalizer APO is not installed.
  notInstalled,

  /// Another front-end (e.g. Peace) controls Equalizer APO; SK EQ waits for
  /// the user to choose.
  otherInControl,

  /// SK EQ is in control, but Equalizer APO is not attached to any device.
  notOnDevice,

  /// SK EQ is changing the real sound on at least one device.
  live,
  error,
}

@immutable
class SoundState {
  const SoundState({
    this.status = SoundStatus.checking,
    this.devices = const [],
    this.otherApps = const [],
    this.switchedOffApps = const [],
    this.error,
  });

  final SoundStatus status;
  final List<AudioDevice> devices;

  /// Front-ends in control instead of SK EQ (for [SoundStatus.otherInControl]).
  final List<String> otherApps;

  /// Front-ends SK EQ switched off (can be given control back).
  final List<String> switchedOffApps;
  final String? error;

  List<AudioDevice> get liveDevices => [
        for (final d in devices)
          if (d.apoEnabled) d
      ];

  bool get inControl =>
      status == SoundStatus.live || status == SoundStatus.notOnDevice;
}

/// "peace.txt" → "Peace".
String frontEndName(String includeFile) {
  final base =
      includeFile.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
  return base.isEmpty ? includeFile : base[0].toUpperCase() + base.substring(1);
}

class SoundNotifier extends Notifier<SoundState> {
  /// User's choice when another front-end exists: 'skeq' or 'other'.
  static const _choiceKey = 'pureeq.soundControl';

  String? _configDir;
  String? _installDir;

  Timer? _writeTimer;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _writing = false;
  bool _pendingWrite = false;

  ApoService get _apo => ref.read(apoServiceProvider);

  @override
  SoundState build() {
    // Every EQ change (bands, shelves, presets, on/off, A/B) → the real sound.
    ref.listen(eqProvider, (_, __) => _scheduleWrite());
    ref.onDispose(() => _writeTimer?.cancel());
    Future.microtask(refresh);
    return const SoundState();
  }

  /// (Re)detects Equalizer APO, devices and who is in control; on macOS
  /// (re)starts the audio engine.
  Future<void> refresh() async {
    if (Platform.isMacOS) return _refreshMac();
    if (!Platform.isWindows) {
      state = const SoundState(status: SoundStatus.unsupported);
      return;
    }
    try {
      final location = await _apo.locate();
      if (location == null) {
        state = const SoundState(status: SoundStatus.notInstalled);
        return;
      }
      _configDir = location.config;
      _installDir = location.install;
      final devices = await _apo.devices();
      final choice = ref.read(sharedPreferencesProvider).getString(_choiceKey);
      final others = await _apo.otherActiveIncludes(location.config);

      if (choice == 'other' || (choice == null && others.isNotEmpty)) {
        state = SoundState(
            status: SoundStatus.otherInControl,
            devices: devices,
            otherApps: others);
        return;
      }

      // SK EQ in control: chosen by the user, or nothing else was active.
      await _apo.connect(location.config);
      await _writeNow();
      state = SoundState(
        status: devices.any((d) => d.apoEnabled)
            ? SoundStatus.live
            : SoundStatus.notOnDevice,
        devices: devices,
        switchedOffApps: await _apo.switchedOffIncludes(location.config),
      );
    } catch (e) {
      state = SoundState(status: SoundStatus.error, error: '$e');
    }
  }

  /// "Use SK EQ": take over from Peace (or another front-end).
  Future<void> takeControl() async {
    await ref.read(sharedPreferencesProvider).setString(_choiceKey, 'skeq');
    await refresh();
  }

  /// "Give control back": restore the front-end(s) SK EQ switched off.
  Future<void> giveControlBack() async {
    await ref.read(sharedPreferencesProvider).setString(_choiceKey, 'other');
    final dir = _configDir;
    if (dir != null) await _apo.disconnect(dir);
    await refresh();
  }

  /// Opens Equalizer APO's device selector to tick devices (asks for admin).
  Future<bool> openDeviceSelector() async {
    final dir = _installDir;
    if (dir == null) return false;
    final path = await ApoService.deviceSelectorPath(dir);
    return path != null && await launchUrl(Uri.file(path));
  }

  Future<void> openDownloadPage() =>
      launchUrl(Uri.parse('https://sourceforge.net/projects/equalizerapo/'),
          mode: LaunchMode.externalApplication);

  // --- macOS -----------------------------------------------------------------

  /// "Real sound" switch on macOS (persisted).
  static const _macOffKey = 'skeq.macRealSoundOff';

  MacAudioService get _mac => ref.read(macAudioServiceProvider);

  /// Sample rate of the running macOS engine; filters are designed for it.
  double? _macSampleRate;

  Future<void> _refreshMac() async {
    _mac.onState = _onMacState;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      _onMacState(prefs.getBool(_macOffKey) ?? false
          ? await _mac.stop()
          : await _mac.start());
    } catch (e) {
      state = SoundState(status: SoundStatus.error, error: '$e');
    }
  }

  /// Turns real sound on or off on macOS.
  Future<void> setMacRealSound(bool on) async {
    await ref.read(sharedPreferencesProvider).setBool(_macOffKey, !on);
    await _refreshMac();
  }

  Future<bool> openPrivacySettings() => _mac.openPrivacySettings();

  void _onMacState(Map<String, Object?> s) {
    final rate = s['sampleRate'];
    _macSampleRate = rate is num ? rate.toDouble() : null;
    state = switch (s['status']) {
      'live' => SoundState(status: SoundStatus.live, devices: [
          AudioDevice(name: '${s['device'] ?? 'Output'}', apoEnabled: true)
        ]),
      'denied' => const SoundState(status: SoundStatus.needsPermission),
      'unsupported' => const SoundState(status: SoundStatus.unsupported),
      'off' => const SoundState(status: SoundStatus.off),
      _ => SoundState(
          status: SoundStatus.error, error: '${s['error'] ?? 'unknown'}'),
    };
    if (state.status == SoundStatus.live) _writeNow();
  }

  // ---------------------------------------------------------------------------

  /// Throttled: at most one update per 80 ms (Equalizer APO file) or 30 ms
  /// (macOS engine) while dragging, always followed by a final update with
  /// the latest values.
  void _scheduleWrite() {
    if (!state.inControl) return;
    if (_writeTimer?.isActive ?? false) return;
    final interval = Duration(milliseconds: Platform.isMacOS ? 30 : 80);
    final wait = interval - DateTime.now().difference(_lastWrite);
    _writeTimer = Timer(wait.isNegative ? Duration.zero : wait, _writeNow);
  }

  Future<void> _writeNow() async {
    final dir = _configDir;
    if (dir == null && !Platform.isMacOS) return;
    if (_writing) {
      _pendingWrite = true;
      return;
    }
    _writing = true;
    _lastWrite = DateTime.now();
    final eq = ref.read(eqProvider);
    try {
      if (Platform.isMacOS) {
        final rate = _macSampleRate;
        if (rate != null) {
          await _mac.setFilters(
              EqFilterDesign.forSampleRate(rate)
                  .design(eq.effectiveGains, processing: eq.isProcessing),
              rate);
        }
        return;
      }
      // Re-assert control in case another app rewrote config.txt.
      await _apo.connect(dir!);
      await _apo.writeCurve(dir, eq.effectiveGains,
          processing: eq.isProcessing);
    } catch (e) {
      debugPrint('SK EQ: could not update the sound: $e');
      state = SoundState(
          status: SoundStatus.error, devices: state.devices, error: '$e');
    } finally {
      _writing = false;
      if (_pendingWrite) {
        _pendingWrite = false;
        _scheduleWrite();
      }
    }
  }
}
