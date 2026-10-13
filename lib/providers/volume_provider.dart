import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/volume_service.dart';

final volumeServiceProvider = Provider<VolumeService>((ref) {
  final service = VolumeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Master volume, kept in sync with the operating system.
final volumeProvider =
    NotifierProvider<VolumeNotifier, VolumeState>(VolumeNotifier.new);

@immutable
class VolumeState {
  const VolumeState({
    required this.volume,
    required this.muted,
    this.available = true,
  });

  /// 0..1
  final double volume;
  final bool muted;

  /// False when the system volume could not be read on this machine.
  final bool available;

  VolumeState copyWith({double? volume, bool? muted, bool? available}) =>
      VolumeState(
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        available: available ?? this.available,
      );
}

class VolumeNotifier extends Notifier<VolumeState> {
  /// Used to ignore the echo of our own changes coming back from the OS
  /// listener, which would otherwise make the slider jitter while dragging.
  DateTime _lastLocalChange = DateTime.fromMillisecondsSinceEpoch(0);

  /// Volume to restore if muting has to be emulated by setting volume to 0.
  double _preMuteVolume = 0.5;
  bool _emulatedMute = false;

  VolumeService get _service => ref.read(volumeServiceProvider);

  @override
  VolumeState build() {
    Future.microtask(_init);
    return const VolumeState(volume: 0.5, muted: false);
  }

  Future<void> _init() async {
    final volume = await _service.getVolume();
    final muted = await _service.getMute();
    state = state.copyWith(
      volume: volume ?? state.volume,
      muted: muted ?? false,
      available: volume != null,
    );

    await _service.listen((v) {
      final sinceLocal = DateTime.now().difference(_lastLocalChange);
      if (sinceLocal < const Duration(milliseconds: 400) || _emulatedMute) {
        return;
      }
      state = state.copyWith(volume: v.clamp(0.0, 1.0));
    });
  }

  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _lastLocalChange = DateTime.now();

    // Moving the slider while muted un-mutes, like most OS mixers.
    if (state.muted && v > 0) {
      state = state.copyWith(volume: v, muted: false);
      if (_emulatedMute) {
        _emulatedMute = false;
      } else {
        await _service.setMute(false);
      }
    } else {
      state = state.copyWith(volume: v);
    }
    await _service.setVolume(v);
  }

  Future<void> toggleMute() async {
    final mute = !state.muted;
    _lastLocalChange = DateTime.now();
    state = state.copyWith(muted: mute);

    if (mute) {
      final ok = await _service.setMute(true);
      if (!ok) {
        // Fallback: emulate mute by dropping the volume to zero.
        _preMuteVolume = state.volume;
        _emulatedMute = true;
        await _service.setVolume(0);
      }
    } else if (_emulatedMute) {
      _emulatedMute = false;
      await _service.setVolume(_preMuteVolume);
    } else {
      await _service.setMute(false);
    }
  }
}
