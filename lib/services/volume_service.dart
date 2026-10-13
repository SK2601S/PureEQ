import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// Thin wrapper around the OS master volume.
///
/// Every call is guarded: if the platform plugin is unavailable (for example
/// an unsupported OS or no output device) the UI keeps working and simply
/// stops reflecting the system volume.
class VolumeService {
  /// Current system volume in 0..1, or null if it cannot be read.
  Future<double?> getVolume() async {
    try {
      return await FlutterVolumeController.getVolume();
    } catch (e) {
      debugPrint('PureEQ: getVolume failed: $e');
      return null;
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await FlutterVolumeController.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('PureEQ: setVolume failed: $e');
    }
  }

  Future<bool?> getMute() async {
    try {
      return await FlutterVolumeController.getMute();
    } catch (e) {
      debugPrint('PureEQ: getMute failed: $e');
      return null;
    }
  }

  /// Returns false if the platform could not mute, so callers can fall back.
  Future<bool> setMute(bool muted) async {
    try {
      await FlutterVolumeController.setMute(muted);
      return true;
    } catch (e) {
      debugPrint('PureEQ: setMute failed: $e');
      return false;
    }
  }

  /// Calls [onChanged] whenever the system volume changes (e.g. media keys).
  Future<void> listen(ValueChanged<double> onChanged) async {
    try {
      await Future<Object?>.sync(
        () => FlutterVolumeController.addListener(onChanged, emitOnStart: false),
      );
    } catch (e) {
      debugPrint('PureEQ: volume listener unavailable: $e');
    }
  }

  void dispose() {
    try {
      FlutterVolumeController.removeListener();
    } catch (_) {
      // Nothing to clean up.
    }
  }
}
