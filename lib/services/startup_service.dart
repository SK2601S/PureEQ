import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Start SK EQ when the user signs in, hidden in the tray / menu bar, so the
/// EQ keeps working after a restart.
///
/// - Windows ("Start with Windows"): a per-user Run entry that opens SK EQ
///   with `--minimized`. Uses reg.exe, so no admin rights are needed.
/// - macOS 13+ ("Open at login"): a login item (SMAppService, see
///   macos/Runner/AppChannel.swift). macOS can't pass `--minimized`, so SK EQ
///   asks how it was launched instead ([launchedAtLogin]).
class StartupService {
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'SK EQ';
  static const _mac = MethodChannel('skeq/app');

  /// Command-line flag: start hidden in the tray.
  static const minimizedFlag = '--minimized';

  static bool get isSupported => Platform.isWindows || Platform.isMacOS;

  /// macOS: whether this launch came from the login item. Waits at most a
  /// second, so a missed answer can never keep the window from showing.
  static Future<bool> launchedAtLogin() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _mac
              .invokeMethod<bool>('launchedAtLogin')
              .timeout(const Duration(seconds: 1)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (Platform.isMacOS) {
      return (await _macLoginItem('loginItem'))['enabled'] == true;
    }
    if (!Platform.isWindows) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return r.exitCode == 0;
  }

  Future<void> setEnabled(bool enabled) async {
    if (Platform.isMacOS) {
      await _macLoginItem('setLoginItem', enabled);
      return;
    }
    if (!Platform.isWindows) return;
    if (enabled) {
      final command = '"${Platform.resolvedExecutable}" $minimizedFlag';
      await Process.run('reg', [
        'add',
        _runKey,
        '/v',
        _valueName,
        '/t',
        'REG_SZ',
        '/d',
        command,
        '/f'
      ]);
    } else {
      await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
    }
  }

  static Future<Map<Object?, Object?>> _macLoginItem(String method,
      [bool? on]) async {
    try {
      return await _mac.invokeMethod<Map<Object?, Object?>>(method, on) ??
          const {};
    } catch (_) {
      return const {};
    }
  }
}
