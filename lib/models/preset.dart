import 'eq_band.dart';

/// A named EQ setting: 10 band gains plus the bass / treble shelves.
class Preset {
  const Preset({
    required this.name,
    required this.gains,
    this.bass = 0,
    this.treble = 0,
    this.isBuiltIn = false,
  });

  /// Name shown when the bands were edited by hand.
  static const String customName = 'Custom';

  final String name;
  final List<double> gains;
  final double bass;
  final double treble;
  final bool isBuiltIn;

  /// Parses a user preset, padding/trimming gains to exactly 10 bands.
  factory Preset.fromJson(Map<String, dynamic> json) {
    final raw = (json['gains'] as List? ?? const [])
        .map((e) => (e as num).toDouble().clamp(kMinGain, kMaxGain))
        .toList();
    double db(Object? v) =>
        v is num ? v.toDouble().clamp(kMinGain, kMaxGain) : 0.0;
    return Preset(
      name: json['name'] as String,
      gains: List<double>.generate(
          kBandCount, (i) => i < raw.length ? raw[i] : 0.0),
      bass: db(json['bass']),
      treble: db(json['treble']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'gains': gains, 'bass': bass, 'treble': treble};

  /// True if the given values equal this preset (within 0.05 dB).
  bool matches(List<double> otherGains, double otherBass, double otherTreble) {
    bool same(double a, double b) => (a - b).abs() < 0.05;
    if (!same(bass, otherBass) || !same(treble, otherTreble)) return false;
    for (var i = 0; i < kBandCount; i++) {
      if (!same(gains[i], otherGains[i])) return false;
    }
    return true;
  }

  /// True for names users may not take (built-ins and "Custom").
  static bool isReservedName(String name) {
    final n = name.trim().toLowerCase();
    return n == customName.toLowerCase() ||
        kBuiltInPresets.any((p) => p.name.toLowerCase() == n);
  }
}

/// Factory presets. Gains are listed 31 Hz → 16 kHz.
const List<Preset> kBuiltInPresets = [
  Preset(name: 'Flat', isBuiltIn: true, gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  Preset(
      name: 'Bass Boost',
      isBuiltIn: true,
      gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
  Preset(
      name: 'Treble Boost',
      isBuiltIn: true,
      gains: [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
  Preset(
      name: 'Vocal', isBuiltIn: true, gains: [-3, -2, -1, 1, 3, 4, 4, 3, 1, 0]),
  Preset(
      name: 'Rock', isBuiltIn: true, gains: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
  Preset(
      name: 'Pop', isBuiltIn: true, gains: [-1, 0, 2, 4, 5, 4, 2, 0, -1, -1]),
  Preset(
      name: 'Jazz', isBuiltIn: true, gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
  Preset(
      name: 'Classical',
      isBuiltIn: true,
      gains: [3, 2, 1, 0, 0, 0, -1, -1, 1, 2]),
  Preset(
      name: 'Electronic',
      isBuiltIn: true,
      gains: [6, 5, 1, 0, -2, 2, 1, 2, 5, 6]),
];
