import 'dart:math' as math;

/// Center frequencies (Hz) of the 10 graphic-EQ bands, one octave apart.
const List<double> kBandFrequencies = [
  31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, //
];

const int kBandCount = 10;
const double kMinGain = -12;
const double kMaxGain = 12;

/// Exact octave base used for math (the "31 Hz" label is rounded 31.25 Hz).
const double _kBaseBandFrequency = 31.25;

/// Left edge of the shared log-frequency axis used by both the visualizer and
/// the slider row. Because the bands are exactly one octave apart, starting
/// half an octave below the first band puts every band in the centre of one
/// of [kAxisOctaves] equal-width columns — so the sliders line up perfectly
/// under the spectrum.
const double kAxisMinFrequency = _kBaseBandFrequency / math.sqrt2;
const int kAxisOctaves = kBandCount;

/// A single equalizer band: a center frequency and its gain in dB.
class EqBand {
  const EqBand({required this.frequency, required this.gain});

  final double frequency;
  final double gain;

  /// Compact label such as "63" or "4k".
  String get label => formatFrequency(frequency);

  EqBand copyWith({double? gain}) =>
      EqBand(frequency: frequency, gain: gain ?? this.gain);
}

/// 63 -> "63", 1000 -> "1k", 16000 -> "16k".
String formatFrequency(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
  }
  return hz.round().toString();
}

/// 3 -> "+3.0", -1.5 -> "-1.5", 0 -> "0.0".
String formatGain(double db) {
  if (db.abs() < 0.05) return '0.0';
  final s = db.toStringAsFixed(1);
  return db > 0 ? '+$s' : s;
}

/// Maps a frequency to 0..1 on the shared log axis.
double frequencyToAxis(double hz) =>
    (math.log(hz / kAxisMinFrequency) / math.ln2) / kAxisOctaves;

/// Inverse of [frequencyToAxis].
double axisToFrequency(double t) =>
    kAxisMinFrequency * math.pow(2, t * kAxisOctaves).toDouble();

/// Smooth EQ response (dB) at any frequency, interpolated between the 10 band
/// gains in log-frequency space using a Catmull-Rom spline.
double interpolateGain(List<double> gains, double hz) {
  final pos = math.log(hz / _kBaseBandFrequency) / math.ln2; // band index
  final last = gains.length - 1;
  if (pos <= 0) return gains.first;
  if (pos >= last) return gains.last;

  final i = pos.floor();
  final t = pos - i;
  final p0 = gains[math.max(i - 1, 0)];
  final p1 = gains[i];
  final p2 = gains[i + 1];
  final p3 = gains[math.min(i + 2, last)];

  final t2 = t * t;
  final t3 = t2 * t;
  final v = 0.5 *
      ((2 * p1) +
          (-p0 + p2) * t +
          (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
          (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  return v.clamp(kMinGain - 3, kMaxGain + 3);
}
