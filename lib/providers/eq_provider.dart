import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eq_band.dart';
import '../models/preset.dart';
import '../services/preset_service.dart';

/// Overridden in main() with the already-loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final presetServiceProvider = Provider<PresetService>(
  (ref) => PresetService(ref.watch(sharedPreferencesProvider)),
);

/// The single source of truth for everything EQ-related.
final eqProvider = NotifierProvider<EqNotifier, EqState>(EqNotifier.new);

/// How much the Bass / Treble quick controls feed into each band (31 Hz → 16 kHz).
/// They behave like gentle low/high shelves layered on top of the graphic EQ.
const List<double> _bassWeights = [1, 1, 0.85, 0.6, 0.3, 0.1, 0, 0, 0, 0];
const List<double> _trebleWeights = [0, 0, 0, 0, 0, 0.1, 0.3, 0.6, 0.85, 1];

/// Immutable EQ state.
@immutable
class EqState {
  const EqState({
    required this.enabled,
    required this.gains,
    required this.bass,
    required this.treble,
    required this.presetName,
    required this.customGains,
    required this.userPresets,
    this.compareBypass = false,
  });

  factory EqState.initial() => EqState(
        enabled: true,
        gains: List.filled(kBandCount, 0.0),
        bass: 0,
        treble: 0,
        presetName: kBuiltInPresets.first.name,
        customGains: List.filled(kBandCount, 0.0),
        userPresets: const [],
      );

  /// Master EQ on/off switch (persisted).
  final bool enabled;

  /// Graphic EQ gains in dB, one per band.
  final List<double> gains;

  /// Quick-control shelves in dB.
  final double bass;
  final double treble;

  /// Currently selected preset (or [Preset.customName]).
  final String presetName;

  /// Last hand-edited curve, restored when "Custom" is picked again.
  final List<double> customGains;

  final List<Preset> userPresets;

  /// A/B compare: true while listening to "B" (the unprocessed signal).
  /// Temporary — never persisted, and separate from [enabled].
  final bool compareBypass;

  /// Whether the EQ is actually shaping the sound right now.
  bool get isProcessing => enabled && !compareBypass;

  List<EqBand> get bands => [
        for (var i = 0; i < kBandCount; i++)
          EqBand(frequency: kBandFrequencies[i], gain: gains[i]),
      ];

  /// Contribution of the bass / treble shelves to band [i], in dB.
  double shelfOffset(int i) =>
      bass * _bassWeights[i] + treble * _trebleWeights[i];

  /// The response actually applied: band gains plus bass/treble shelves.
  /// This is what the EQ curve draws.
  List<double> get effectiveGains => [
        for (var i = 0; i < kBandCount; i++)
          (gains[i] + shelfOffset(i)).clamp(kMinGain, kMaxGain),
      ];

  List<Preset> get allPresets => [...kBuiltInPresets, ...userPresets];

  Preset? findPreset(String name) {
    for (final p in allPresets) {
      if (p.name == name) return p;
    }
    return null;
  }

  bool get isFlat =>
      bass.abs() < 0.05 &&
      treble.abs() < 0.05 &&
      gains.every((g) => g.abs() < 0.05);

  /// True when the current settings differ from the selected preset, i.e.
  /// there is something worth saving. Drives the Save Preset highlight.
  bool get isDirty {
    if (presetName == Preset.customName) return !isFlat;
    final preset = findPreset(presetName);
    return preset == null || !preset.matches(gains, bass, treble);
  }

  EqState copyWith({
    bool? enabled,
    List<double>? gains,
    double? bass,
    double? treble,
    String? presetName,
    List<double>? customGains,
    List<Preset>? userPresets,
    bool? compareBypass,
  }) {
    return EqState(
      enabled: enabled ?? this.enabled,
      gains: gains ?? this.gains,
      bass: bass ?? this.bass,
      treble: treble ?? this.treble,
      presetName: presetName ?? this.presetName,
      customGains: customGains ?? this.customGains,
      userPresets: userPresets ?? this.userPresets,
      compareBypass: compareBypass ?? this.compareBypass,
    );
  }

  Map<String, dynamic> toSettingsJson() => {
        'enabled': enabled,
        'gains': gains,
        'bass': bass,
        'treble': treble,
        'preset': presetName,
        'customGains': customGains,
      };
}

class EqNotifier extends Notifier<EqState> {
  Timer? _persistTimer;

  PresetService get _service => ref.read(presetServiceProvider);

  @override
  EqState build() {
    ref.onDispose(() => _persistTimer?.cancel());
    return _restore();
  }

  // ---------------------------------------------------------------------------
  // On / off and A/B compare
  // ---------------------------------------------------------------------------

  /// Turning the EQ off also leaves A/B mode, which only makes sense while on.
  void setEnabled(bool enabled) =>
      _commit(state.copyWith(enabled: enabled, compareBypass: false));

  void toggleEnabled() => setEnabled(!state.enabled);

  /// Switches instantly between A (EQ) and B (bypass). No-op while EQ is off.
  void toggleCompare() {
    if (!state.enabled) return;
    state =
        state.copyWith(compareBypass: !state.compareBypass); // not persisted
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  /// Sets one band's gain (slider). Switches the preset to "Custom".
  void setBandGain(int index, double gain) {
    final gains = [...state.gains];
    gains[index] = _round(gain.clamp(kMinGain, kMaxGain));
    _commit(state.copyWith(
      gains: gains,
      customGains: gains,
      presetName: Preset.customName,
    ));
  }

  /// Used when dragging the EQ curve: the curve shows the *effective* gain
  /// (band + shelves), so subtract the shelf contribution to keep the
  /// dragged point exactly under the cursor.
  void setBandFromCurve(int index, double effectiveDb) =>
      setBandGain(index, effectiveDb - state.shelfOffset(index));

  void setBass(double db) =>
      _commit(state.copyWith(bass: _round(db.clamp(kMinGain, kMaxGain))));

  void setTreble(double db) =>
      _commit(state.copyWith(treble: _round(db.clamp(kMinGain, kMaxGain))));

  // ---------------------------------------------------------------------------
  // Presets
  // ---------------------------------------------------------------------------

  /// Loads a built-in, user or "Custom" preset. The UI animates to the new
  /// values on its own (band sliders and the EQ curve ease toward them).
  void selectPreset(String name) {
    if (name == Preset.customName) {
      _commit(state.copyWith(presetName: name, gains: [...state.customGains]));
      return;
    }
    final preset = state.findPreset(name);
    if (preset == null) return;
    _commit(state.copyWith(
      presetName: preset.name,
      gains: [...preset.gains],
      bass: preset.bass,
      treble: preset.treble,
    ));
  }

  /// Saves the current settings as a user preset (overwriting same name).
  Future<void> savePreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || Preset.isReservedName(trimmed)) return;

    final preset = Preset(
      name: trimmed,
      gains: [...state.gains],
      bass: state.bass,
      treble: state.treble,
    );
    final presets = [
      for (final p in state.userPresets)
        if (p.name != trimmed) p,
      preset,
    ];
    _commit(state.copyWith(userPresets: presets, presetName: trimmed));
    await _service.saveUserPresets(presets);
  }

  Future<void> deletePreset(String name) async {
    final presets = [
      for (final p in state.userPresets)
        if (p.name != name) p,
    ];
    final wasActive = state.presetName == name;
    _commit(state.copyWith(
      userPresets: presets,
      presetName: wasActive ? Preset.customName : null,
      customGains: wasActive ? [...state.gains] : null,
    ));
    await _service.saveUserPresets(presets);
  }

  /// Back to a flat response. The on/off switch is left untouched.
  void reset() {
    _commit(state.copyWith(
      gains: List.filled(kBandCount, 0.0),
      bass: 0,
      treble: 0,
      presetName: kBuiltInPresets.first.name,
      compareBypass: false,
    ));
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Writes any not-yet-saved change right away (used when quitting).
  Future<void> flush() async {
    if (_persistTimer?.isActive ?? false) {
      _persistTimer!.cancel();
      await _service.saveSettings(state.toSettingsJson());
    }
  }

  /// Sets state and persists it shortly after the user stops interacting.
  void _commit(EqState next) {
    state = next;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      _service.saveSettings(state.toSettingsJson());
    });
  }

  EqState _restore() {
    final initial = EqState.initial();
    final userPresets = _service.loadUserPresets();
    final json = _service.loadSettings();
    if (json == null) return initial.copyWith(userPresets: userPresets);

    List<double> readGains(Object? raw) {
      final list = raw is List ? raw : const [];
      return List<double>.generate(
        kBandCount,
        (i) => i < list.length && list[i] is num
            ? (list[i] as num).toDouble().clamp(kMinGain, kMaxGain)
            : 0.0,
      );
    }

    double readDb(Object? raw) =>
        raw is num ? raw.toDouble().clamp(kMinGain, kMaxGain) : 0.0;

    var presetName = json['preset'] as String? ?? initial.presetName;
    final known = presetName == Preset.customName ||
        kBuiltInPresets.any((p) => p.name == presetName) ||
        userPresets.any((p) => p.name == presetName);
    if (!known) presetName = Preset.customName;

    return EqState(
      enabled: json['enabled'] as bool? ?? true,
      gains: readGains(json['gains']),
      bass: readDb(json['bass']),
      treble: readDb(json['treble']),
      presetName: presetName,
      customGains: readGains(json['customGains']),
      userPresets: userPresets,
    );
  }

  /// Rounds to 0.1 dB so values stay tidy in the UI and in storage.
  static double _round(double v) => (v * 10).roundToDouble() / 10;
}
