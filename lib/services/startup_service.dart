import 'dart:io';

/// "Start with Windows": a per-user Run entry that opens SK EQ hidden in the
/// tray (`--minimized`) when the user signs in. Uses reg.exe, so no admin
/// rights are needed.
class StartupService {
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'SK EQ';

  /// Command-line flag: start hidden in the tray.
  static const minimizedFlag = '--minimized';

  static bool get isSupported => Platform.isWindows;

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return r.exitCode == 0;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
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
}
