import 'dart:io';
import 'dart:math' as math;

import '../models/eq_band.dart';

/// One Windows playback device and whether Equalizer APO is attached to it.
class AudioDevice {
  const AudioDevice({required this.name, required this.apoEnabled});

  final String name;
  final bool apoEnabled;
}

/// Connects SK EQ to **Equalizer APO** (Windows), the free system-wide audio
/// driver that actually processes the sound. SK EQ writes its curve to
/// `sk-eq.txt` in Equalizer APO's config folder; Equalizer APO notices the
/// change and applies it to every app within a fraction of a second.
///
/// Equalizer APO only processes devices that were ticked in its Configurator
/// (followed by a restart), so [devices] reports which ones are covered.
class ApoService {
  /// SK EQ's own config file, included from `config.txt`.
  static const String fileName = 'sk-eq.txt';

  static const String _apoKey = r'HKLM\SOFTWARE\EqualizerAPO';
  static const String _renderKey = r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render';

  /// Equalizer APO's pre-/post-mix effect CLSIDs, as found in a device's
  /// FxProperties when the Configurator attached it.
  static const List<String> _apoClsids = [
    'EACD2258-FCAC-4FF4-B36D-419E924A6D79',
    'EC1CC9CE-FAED-4822-828A-82A81A6F018F',
  ];

  /// Device description ("Headset") and interface name ("EarPods"); shown
  /// together as "Headset (EarPods)", like Windows' sound settings.
  static const String _descriptionProp = '{a45c254e-df1c-4efd-8020-67d146a850e0},2';
  static const String _interfaceProp = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6';

  /// Equalizer APO's install and config folders, or null if not installed.
  ///
  /// The driver DLL must exist: uninstalling Equalizer APO leaves its
  /// registry key and config folder behind, which alone mean nothing.
  Future<({String install, String config})?> locate() async {
    final install = await _regValue(_apoKey, 'InstallPath');
    final config = await _regValue(_apoKey, 'ConfigPath');
    if (install == null || config == null) return null;
    if (!await File(_join(install, 'EqualizerAPO.dll')).exists()) return null;
    final configFile = File(_join(config, 'config.txt'));
    if (!await configFile.exists()) await configFile.create(recursive: true);
    return (install: install, config: config);
  }

  /// Active playback devices, each with whether Equalizer APO is attached.
  Future<List<AudioDevice>> devices() async {
    final hooked = <String>{};
    for (final clsid in _apoClsids) {
      final out = await _reg(['query', _renderKey, '/s', '/f', clsid, '/d']);
      for (final m in RegExp(r'\\Render\\(\{[0-9a-fA-F-]+\})\\FxProperties').allMatches(out)) {
        hooked.add(m[1]!.toLowerCase());
      }
    }

    final states = _perDevice(await _reg(['query', _renderKey, '/s', '/v', 'DeviceState']), 'DeviceState');
    final descriptions = _perDevice(await _reg(['query', _renderKey, '/s', '/v', _descriptionProp]), _descriptionProp);
    final interfaces = _perDevice(await _reg(['query', _renderKey, '/s', '/v', _interfaceProp]), _interfaceProp);

    final result = <AudioDevice>[];
    for (final MapEntry(key: id, value: state) in states.entries) {
      if (int.tryParse(state.replaceFirst('0x', ''), radix: 16) != 1) continue; // 1 = active
      final description = descriptions[id] ?? 'Audio device';
      final interface = interfaces[id];
      result.add(AudioDevice(
        name: interface == null ? description : '$description ($interface)',
        apoEnabled: hooked.contains(id),
      ));
    }
    return result;
  }

  /// Other equalizer front-ends (e.g. Peace) that are currently active in
  /// `config.txt`, by their include file name.
  Future<List<String>> otherActiveIncludes(String configDir) async =>
      ApoConfig.otherActiveIncludes(await _readConfig(configDir));

  /// Front-ends SK EQ switched off, which "give control back" restores.
  Future<List<String>> switchedOffIncludes(String configDir) async =>
      ApoConfig.switchedOffIncludes(await _readConfig(configDir));

  /// Puts SK EQ in control: includes `sk-eq.txt` and switches off other
  /// front-ends' includes (kept as comments, so they can be restored).
  Future<void> connect(String configDir) async {
    final text = await _readConfig(configDir);
    final updated = ApoConfig.connect(text);
    if (updated != text) await _writeAtomic(_join(configDir, 'config.txt'), updated);
  }

  /// Gives control back: removes SK EQ's include and restores the
  /// includes SK EQ had switched off.
  Future<void> disconnect(String configDir) async {
    final text = await _readConfig(configDir);
    final updated = ApoConfig.disconnect(text);
    if (updated != text) await _writeAtomic(_join(configDir, 'config.txt'), updated);
  }

  /// Writes the curve. [processing] false (EQ off / A/B "B") writes a flat
  /// file, so bypass is heard immediately.
  Future<void> writeCurve(String configDir, List<double> gains, {required bool processing}) =>
      _writeAtomic(_join(configDir, fileName), ApoConfig.render(gains, processing: processing));

  /// Equalizer APO's Configurator, where devices are ticked (needs admin).
  static String configuratorPath(String installDir) => _join(installDir, 'Configurator.exe');

  // ---------------------------------------------------------------------------

  Future<String> _readConfig(String dir) => File(_join(dir, 'config.txt')).readAsString();

  /// Write to a temp file, then swap it in, so Equalizer APO never reads a
  /// half-written file.
  static Future<void> _writeAtomic(String path, String content) async {
    final tmp = File('$path.sk-eq-tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(path);
  }

  static Future<String?> _regValue(String key, String name) async {
    final out = await _reg(['query', key, '/v', name]);
    final m = RegExp('^\\s*${RegExp.escape(name)}\\s+REG_\\w+\\s+(.+)\$', multiLine: true).firstMatch(out);
    return m?[1]?.trim();
  }

  /// Runs reg.exe (a console tool; started normally, not detached).
  static Future<String> _reg(List<String> args) async {
    try {
      final r = await Process.run('reg', args);
      return r.exitCode == 0 ? r.stdout as String : '';
    } catch (_) {
      return '';
    }
  }

  /// Maps device id → value for `reg query … /s /v <name>` output.
  static Map<String, String> _perDevice(String out, String valueName) {
    final map = <String, String>{};
    String? current;
    for (final line in out.split(RegExp(r'\r?\n'))) {
      final key = RegExp(r'\\Render\\(\{[0-9a-fA-F-]+\})').firstMatch(line);
      if (line.startsWith('HKEY_') && key != null) {
        current = key[1]!.toLowerCase();
      } else if (current != null && line.trimLeft().startsWith(valueName)) {
        final m = RegExp(r'REG_\w+\s+(.*)$').firstMatch(line);
        if (m != null) map[current] = m[1]!.trim();
      }
    }
    return map;
  }

  static String _join(String a, String b) => a.endsWith(r'\') ? '$a$b' : '$a\\$b';
}

/// Pure text transformations for Equalizer APO config files (unit-tested).
class ApoConfig {
  ApoConfig._();

  static const String _tag = '# SK EQ';
  static const String _offNote = '# turned off by SK EQ (SK EQ → Sound → give control back)';

  /// 1/3-octave centre frequencies, 20 Hz – 20 kHz. Sampling SK EQ's smooth
  /// curve this finely makes Equalizer APO's interpolation match what the
  /// app draws.
  static const List<double> frequencies = [
    20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, //
    800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
    12500, 16000, 20000,
  ];

  /// Contents of `sk-eq.txt` for the given band gains (dB, 10 bands).
  static String render(List<double> gains, {required bool processing}) {
    final b = StringBuffer()
      ..writeln('# Written by SK EQ - changes made here are overwritten.')
      ..writeln('# Control the sound from the SK EQ app.');
    if (!processing) {
      b.writeln('Preamp: 0 dB');
      return b.toString();
    }
    final points = [for (final f in frequencies) (f, interpolateGain(gains, f))];
    // Headroom: lower the overall level by the largest boost so it can't clip.
    final maxBoost = points.map((p) => p.$2).fold<double>(0, math.max);
    b
      ..writeln('Preamp: ${_fmt(-maxBoost)} dB')
      ..writeln('GraphicEQ: ${points.map((p) => '${_fmtHz(p.$1)} ${_fmt(p.$2)}').join('; ')}');
    return b.toString();
  }

  /// Includes `sk-eq.txt` and comments out other active includes.
  static String connect(String config) {
    final lines = _lines(disconnect(config));
    final out = <String>[];
    for (final line in lines) {
      if (_isActiveInclude(line)) {
        out.add('# ${line.trim()}  $_offNote');
      } else {
        out.add(line);
      }
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    out.add('Include: ${ApoService.fileName}  $_tag');
    return '${out.join('\r\n')}\r\n';
  }

  /// Reverses [connect].
  static String disconnect(String config) {
    final out = <String>[];
    for (final line in _lines(config)) {
      if (line.trimRight().endsWith(_tag) && line.contains(ApoService.fileName)) continue;
      if (line.contains(_offNote)) {
        out.add(line.replaceFirst(RegExp(r'^\s*#\s*'), '').replaceFirst(_offNote, '').trimRight());
      } else {
        out.add(line);
      }
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return out.isEmpty ? '' : '${out.join('\r\n')}\r\n';
  }

  /// Names of other include files that are active (e.g. "peace.txt").
  static List<String> otherActiveIncludes(String config) => [
        for (final line in _lines(config))
          if (_isActiveInclude(line))
            line.trim().substring('include:'.length).trim().split(RegExp(r'\s+#')).first.trim(),
      ];

  /// Include file names that SK EQ commented out in [connect].
  static List<String> switchedOffIncludes(String config) => [
        for (final line in _lines(config))
          if (line.contains(_offNote))
            line
                .replaceFirst(RegExp(r'^\s*#\s*'), '')
                .replaceFirst(_offNote, '')
                .trim()
                .substring('include:'.length)
                .trim(),
      ];

  static bool _isActiveInclude(String line) {
    final t = line.trim();
    return t.toLowerCase().startsWith('include:') &&
        !t.toLowerCase().contains(ApoService.fileName);
  }

  static List<String> _lines(String text) => text.split(RegExp(r'\r?\n'));

  static String _fmt(double v) {
    final r = (v * 10).roundToDouble() / 10;
    return (r == 0 ? 0.0 : r).toStringAsFixed(1);
  }

  static String _fmtHz(double f) => f == f.roundToDouble() ? f.toInt().toString() : f.toString();
}
