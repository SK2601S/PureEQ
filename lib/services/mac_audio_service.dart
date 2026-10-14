import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/eq_filter.dart';

/// Talks to SK EQ's macOS audio engine (macos/Runner/SystemAudioEQ.swift),
/// which taps the sound of every app, runs it through the EQ and plays it.
///
/// The engine reports its state as a map: `status` is one of `live`,
/// `denied` (no "record system audio" permission), `unsupported` (macOS
/// older than 14.2), `off` or `error`; `device` and `sampleRate` describe
/// the output while live; `error` explains a failure.
class MacAudioService {
  static const _channel = MethodChannel('skeq/eq');

  /// Called when the engine's state changes by itself (output device
  /// switched, sample rate changed, error).
  set onState(void Function(Map<String, Object?> state) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state') handler(_map(call.arguments));
    });
  }

  /// Starts processing. The first time, macOS asks for permission and this
  /// waits for the answer.
  Future<Map<String, Object?>> start() async =>
      _map(await _channel.invokeMethod<Object?>('start'));

  /// Stops processing; apps play normally again.
  Future<Map<String, Object?>> stop() async =>
      _map(await _channel.invokeMethod<Object?>('stop'));

  /// Sends the filters, designed for the engine's [sampleRate].
  Future<void> setFilters(FilterChain chain, double sampleRate) =>
      _channel.invokeMethod<void>('setFilters', {
        'coefficients': chain.coefficients,
        'preampDb': chain.preampDb,
        'sampleRate': sampleRate,
      });

  /// System Settings → Privacy & Security → Screen & System Audio Recording.
  Future<bool> openPrivacySettings() => launchUrl(Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};
}
