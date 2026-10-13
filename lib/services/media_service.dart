import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Media buttons. On Windows they send the keyboard media keys (see
/// windows/runner/flutter_window.cpp, "skeq/media"), so they control whichever
/// app is playing: Spotify, YouTube in a browser, VLC, …
class MediaService {
  static const _channel = MethodChannel('skeq/media');

  /// Only Windows for now (macOS would need Accessibility permission).
  static bool get isSupported => Platform.isWindows;

  Future<void> playPause() => _press('playPause');
  Future<void> next() => _press('next');
  Future<void> previous() => _press('previous');
  Future<void> stop() => _press('stop');

  Future<void> _press(String key) async {
    try {
      await _channel.invokeMethod<bool>(key);
    } catch (e) {
      debugPrint('SK EQ: media key "$key" failed: $e');
    }
  }
}
