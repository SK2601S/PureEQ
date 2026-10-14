import 'dart:math' as math;

import 'eq_band.dart';

/// Biquad coefficients ready for the macOS audio engine: one section is
/// `b0, b1, b2, a1, a2` (normalized so a0 = 1), applied in series, followed
/// by [preampDb] of overall gain.
class FilterChain {
  const FilterChain({required this.coefficients, required this.preampDb});

  /// Bypass: no filters, unity gain.
  static const FilterChain flat = FilterChain(coefficients: [], preampDb: 0);

  /// 5 values per section.
  final List<double> coefficients;
  final double preampDb;

  int get sectionCount => coefficients.length ~/ 5;
}

/// Turns SK EQ's smooth curve (the 10 bands plus bass/treble) into a chain of
/// biquad filters for macOS, where SK EQ processes the sound itself.
///
/// The filter bank is a low shelf, 29 peaking filters a ⅓ octave apart
/// (25 Hz – 16 kHz) and a high shelf. Their gains are solved by least
/// squares so the chain's response follows [interpolateGain] — what the app
/// draws — within about half a dB from 20 Hz to 20 kHz. The design is made
/// for the device's real sample rate, because digital filters bend near the
/// top of the range (and differently at 44.1 and 48 kHz).
class EqFilterDesign {
  EqFilterDesign._(this.sampleRate) {
    for (final f in _grid) {
      final w = 2 * math.pi * f / sampleRate;
      _trig.add((math.cos(w), math.sin(w), math.cos(2 * w), math.sin(2 * w)));
    }
    // Response of each filter at +1 dB: the columns of the linear model.
    _shapes = [
      for (final f in _grid)
        [
          for (final s in _bank)
            magnitudeDb(s.coefficients(1, sampleRate), f, sampleRate)
        ]
    ];
    final n = _bank.length;
    final normal = List.generate(n, (i) {
      return List.generate(n, (j) {
        var sum = i == j ? _regularization : 0.0;
        for (final row in _shapes) {
          sum += row[i] * row[j];
        }
        return sum;
      });
    });
    _inverse = _invert(normal);
  }

  static final Map<double, EqFilterDesign> _cache = {};

  /// The design for [sampleRate] (cached: building one solves a 31×31
  /// system once; each [design] afterwards is cheap).
  factory EqFilterDesign.forSampleRate(double sampleRate) =>
      _cache.putIfAbsent(sampleRate, () => EqFilterDesign._(sampleRate));

  final double sampleRate;

  /// Small ridge term: keeps neighbouring filters from fighting each other
  /// with huge opposite gains.
  static const double _regularization = 1e-3;

  /// Refinement passes: a filter's dB shape changes slightly with its gain,
  /// so the linear solution is corrected a few times.
  static const int _iterations = 4;

  static final List<_Section> _bank = [
    const _Section(_Kind.lowShelf, 22, 0.707),
    for (var k = -16; k <= 12; k++)
      _Section(_Kind.peak, 1000 * math.pow(2, k / 3).toDouble(), 1.5),
    const _Section(_Kind.highShelf, 14000, 0.5),
  ];

  /// Where the fit is measured: 1/12 octave from 20 Hz to 20 kHz.
  static final List<double> _grid = [
    for (var i = 0; i <= 120; i++) 20 * math.pow(1000, i / 120).toDouble()
  ];

  /// cos ω, sin ω, cos 2ω, sin 2ω for each grid point.
  final List<(double, double, double, double)> _trig = [];

  late final List<List<double>> _shapes;
  late final List<List<double>> _inverse;

  /// Filters for the 10 effective band gains (dB). [processing] false (EQ
  /// off / A/B "B") gives [FilterChain.flat].
  FilterChain design(List<double> gains, {bool processing = true}) {
    if (!processing || gains.every((g) => g.abs() < 0.05)) {
      return FilterChain.flat;
    }
    final target = [for (final f in _grid) interpolateGain(gains, f)];
    final n = _bank.length;
    final sectionGains = List<double>.filled(n, 0);

    for (var pass = 0; pass < _iterations; pass++) {
      final current = _coefficients(sectionGains);
      final rhs = List<double>.filled(n, 0);
      for (var r = 0; r < _grid.length; r++) {
        final error = target[r] - _responseAt(current, r);
        final row = _shapes[r];
        for (var i = 0; i < n; i++) {
          rhs[i] += row[i] * error;
        }
      }
      for (var i = 0; i < n; i++) {
        var step = 0.0;
        for (var j = 0; j < n; j++) {
          step += _inverse[i][j] * rhs[j];
        }
        sectionGains[i] += step;
      }
    }

    final sections = _coefficients(sectionGains);
    // Headroom: lower the level by the largest boost so it can't clip.
    var maxBoost = 0.0;
    for (var r = 0; r < _grid.length; r++) {
      maxBoost = math.max(maxBoost, _responseAt(sections, r));
    }
    return FilterChain(
        coefficients: [for (final c in sections) ...c], preampDb: -maxBoost);
  }

  /// Response (dB) of the whole chain at [hz], without the preamp.
  static double chainResponseDb(FilterChain chain, double hz, double fs) {
    var sum = 0.0;
    for (var i = 0; i < chain.sectionCount; i++) {
      sum += magnitudeDb(chain.coefficients.sublist(i * 5, i * 5 + 5), hz, fs);
    }
    return sum;
  }

  List<List<double>> _coefficients(List<double> sectionGains) => [
        for (var i = 0; i < _bank.length; i++)
          _bank[i].coefficients(sectionGains[i], sampleRate)
      ];

  /// Chain response (dB) at grid point [r]: 10·log10 of the product of
  /// the sections' squared magnitudes (one log instead of 31).
  double _responseAt(List<List<double>> sections, int r) {
    final (c1, s1, c2, s2) = _trig[r];
    var power = 1.0;
    for (final c in sections) {
      final nr = c[0] + c[1] * c1 + c[2] * c2, ni = c[1] * s1 + c[2] * s2;
      final dr = 1 + c[3] * c1 + c[4] * c2, di = c[3] * s1 + c[4] * s2;
      power *= (nr * nr + ni * ni) / (dr * dr + di * di);
    }
    return 10 * math.log(power) / math.ln10;
  }

  /// |H(e^jω)| in dB of one normalized biquad `[b0, b1, b2, a1, a2]`.
  static double magnitudeDb(List<double> c, double hz, double fs) {
    final w = 2 * math.pi * hz / fs;
    final c1 = math.cos(w), s1 = math.sin(w);
    final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
    final nr = c[0] + c[1] * c1 + c[2] * c2, ni = c[1] * s1 + c[2] * s2;
    final dr = 1 + c[3] * c1 + c[4] * c2, di = c[3] * s1 + c[4] * s2;
    return 10 *
        math.log((nr * nr + ni * ni) / (dr * dr + di * di)) /
        math.ln10;
  }

  /// Gauss–Jordan inverse with partial pivoting (the matrix is small and
  /// well conditioned thanks to [_regularization]).
  static List<List<double>> _invert(List<List<double>> m) {
    final n = m.length;
    final a = [
      for (var i = 0; i < n; i++)
        [...m[i], for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0]
    ];
    for (var c = 0; c < n; c++) {
      var p = c;
      for (var r = c + 1; r < n; r++) {
        if (a[r][c].abs() > a[p][c].abs()) p = r;
      }
      final t = a[c];
      a[c] = a[p];
      a[p] = t;
      final pivot = a[c][c];
      for (var k = 0; k < 2 * n; k++) {
        a[c][k] /= pivot;
      }
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        final f = a[r][c];
        if (f == 0) continue;
        for (var k = 0; k < 2 * n; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return [for (final row in a) row.sublist(n)];
  }
}

enum _Kind { peak, lowShelf, highShelf }

/// One filter of the bank (RBJ Audio EQ Cookbook formulas).
class _Section {
  const _Section(this.kind, this.frequency, this.q);

  final _Kind kind;
  final double frequency;
  final double q;

  List<double> coefficients(double gainDb, double fs) {
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * frequency / fs;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    double b0, b1, b2, a0, a1, a2;
    switch (kind) {
      case _Kind.peak:
        b0 = 1 + alpha * a;
        b1 = -2 * cosW;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cosW;
        a2 = 1 - alpha / a;
      case _Kind.lowShelf:
        final s = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) - (a - 1) * cosW + s);
        b1 = 2 * a * ((a - 1) - (a + 1) * cosW);
        b2 = a * ((a + 1) - (a - 1) * cosW - s);
        a0 = (a + 1) + (a - 1) * cosW + s;
        a1 = -2 * ((a - 1) + (a + 1) * cosW);
        a2 = (a + 1) + (a - 1) * cosW - s;
      case _Kind.highShelf:
        final s = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) + (a - 1) * cosW + s);
        b1 = -2 * a * ((a - 1) + (a + 1) * cosW);
        b2 = a * ((a + 1) + (a - 1) * cosW - s);
        a0 = (a + 1) - (a - 1) * cosW + s;
        a1 = 2 * ((a - 1) - (a + 1) * cosW);
        a2 = (a + 1) - (a - 1) * cosW - s;
    }
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
  }
}
