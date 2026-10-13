import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';

/// Stores user presets and the last-used EQ settings in SharedPreferences.
class PresetService {
  PresetService(this._prefs);

  final SharedPreferences _prefs;

  static const _kUserPresets = 'pureeq.userPresets.v1';
  static const _kSettings = 'pureeq.settings.v1';

  /// Loads user presets. Corrupt entries are skipped rather than crashing.
  List<Preset> loadUserPresets() {
    final raw = _prefs.getStringList(_kUserPresets) ?? const [];
    final presets = <Preset>[];
    for (final entry in raw) {
      try {
        presets.add(Preset.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('SK EQ: skipping unreadable preset: $e');
      }
    }
    return presets;
  }

  Future<void> saveUserPresets(List<Preset> presets) => _prefs.setStringList(
        _kUserPresets,
        [for (final p in presets) jsonEncode(p.toJson())],
      );

  /// Last EQ settings as a JSON map, or null on first launch.
  Map<String, dynamic>? loadSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings));
}
