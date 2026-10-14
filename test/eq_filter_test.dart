// Tests for the macOS filter design: the biquad chain must sound like the
// curve SK EQ draws.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_eq/models/eq_band.dart';
import 'package:pure_eq/models/eq_filter.dart';

/// Largest gap (dB) between the chain and the drawn curve, 20 Hz – 20 kHz.
double maxError(FilterChain chain, List<double> gains, double fs) {
  var worst = 0.0;
  for (var i = 0; i <= 400; i++) {
    final f = 20 * math.pow(1000, i / 400).toDouble();
    final err = (EqFilterDesign.chainResponseDb(chain, f, fs) -
            interpolateGain(gains, f))
        .abs();
    worst = math.max(worst, err);
  }
  return worst;
}

void main() {
  final random = math.Random(7);
  final curves = <String, List<double>>{
    'all +12': List.filled(10, 12),
    'all -12': List.filled(10, -12),
    'bass boost': [12, 12, 8, 3, 0, 0, 0, 0, 0, 0],
    'treble only': [0, 0, 0, 0, 0, 0, 0, 0, 0, 12],
    'one band': [0, 0, 0, 0, 12, 0, 0, 0, 0, 0],
    'zigzag': [12, -12, 12, -12, 12, -12, 12, -12, 12, -12],
    for (var t = 0; t < 10; t++)
      'random $t': [for (var i = 0; i < 10; i++) random.nextDouble() * 24 - 12],
  };

  for (final fs in [44100.0, 48000.0, 96000.0]) {
    test('follows the drawn curve within 0.75 dB at ${fs ~/ 1000} kHz', () {
      final design = EqFilterDesign.forSampleRate(fs);
      for (final MapEntry(key: name, value: gains) in curves.entries) {
        final chain = design.design(gains);
        expect(maxError(chain, gains, fs), lessThan(0.75), reason: name);
      }
    });
  }

  test('flat curve, EQ off and A/B "B" are a plain bypass', () {
    final design = EqFilterDesign.forSampleRate(48000);
    expect(design.design(List.filled(10, 0)).sectionCount, 0);
    expect(design.design([6, 0, 0, 0, 0, 0, 0, 0, 0, 0], processing: false),
        same(FilterChain.flat));
  });

  test('preamp leaves headroom for the largest boost', () {
    final design = EqFilterDesign.forSampleRate(48000);
    final boost = design.design([0, 0, 0, 0, 0, 9, 0, 0, 0, 0]);
    expect(boost.preampDb, closeTo(-9, 0.5));
    expect(design.design(List.filled(10, -6)).preampDb, 0);
  });

  test('every section is stable', () {
    for (final fs in [44100.0, 48000.0]) {
      final design = EqFilterDesign.forSampleRate(fs);
      for (final gains in curves.values) {
        final c = design.design(gains).coefficients;
        for (var i = 0; i < c.length; i += 5) {
          final a1 = c[i + 3], a2 = c[i + 4];
          // Poles inside the unit circle (Jury criterion for 2nd order).
          expect(a2.abs(), lessThan(1));
          expect(a1.abs(), lessThan(1 + a2));
        }
      }
    }
  });
}
