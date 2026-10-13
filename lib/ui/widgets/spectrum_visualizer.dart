import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/eq_band.dart';
import '../../providers/eq_provider.dart';
import '../../providers/volume_provider.dart';
import '../../providers/window_provider.dart';
import '../../theme/app_theme.dart';
import 'eq_curve.dart';

/// Real-time spectrum analyzer (thin glowing bars with peak-hold dots) with
/// the interactive EQ curve layered on top.
///
/// Capturing system-wide audio needs a loopback driver (WASAPI loopback on
/// Windows, a virtual device such as BlackHole on macOS), so the signal here
/// is *simulated*: a synthetic groove of kick, snare, hi-hats and a wandering
/// melody. It is shaped by the real EQ curve and master volume, so every
/// control has a visible effect. To show real audio, feed FFT magnitudes into
/// [SpectrumSimulation.levels] instead of synthesising them in `step`.
///
/// Performance: an adaptive frame pacer runs the spectrum at ~30 fps when
/// idle and at the full display rate while anything moves; it stops entirely
/// while the window is minimized or in the tray. Only the bars repaint each
/// frame (no widget rebuilds); the bars are drawn as raw GPU triangles and
/// glows avoid blur filters. The curve repaints only while it is moving.
class SpectrumVisualizer extends ConsumerStatefulWidget {
  const SpectrumVisualizer({
    super.key,
    this.showOutput = true,
    this.showCurve = true,
  });

  /// Toggles for the "Output" (bars) and "EQ curve" layers.
  final bool showOutput;
  final bool showCurve;

  @override
  ConsumerState<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends ConsumerState<SpectrumVisualizer> {
  final SpectrumSimulation _sim = SpectrumSimulation(barCount: 128);
  late final AppLifecycleListener _lifecycle;
  bool? _lastCompare;

  // --- Frame pacing --------------------------------------------------------
  //
  // On desktop Flutter re-renders the *whole window* for every frame, so the
  // frame rate is what costs CPU — not the drawing code. The spectrum
  // therefore runs at ~30 fps when idle (plenty for an analyzer, and half
  // the cost) and switches to the full display rate only while something
  // moves: curve drags, preset transitions, A/B switches. Frames are still
  // requested through the scheduler, so they stay aligned to vsync.

  /// Delay before requesting the next frame at the idle rate: the frame then
  /// lands on the following vsync (≈ 33 ms at 60 Hz).
  static const Duration _idleDelay = Duration(milliseconds: 22);

  Timer? _timer;
  int? _frameCallbackId;
  Duration? _lastFrame;

  /// Pause sources: window events (minimize / tray) and the OS lifecycle.
  /// While paused no frames are requested at all — 0 CPU / GPU.
  bool _windowHidden = false;
  bool _lifecycleHidden = false;
  bool get _paused => _windowHidden || _lifecycleHidden;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      _lifecycleHidden = s == AppLifecycleState.hidden || s == AppLifecycleState.paused;
      _syncPacer();
    });
    _requestFrame();
  }

  void _requestFrame() {
    _frameCallbackId ??= SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    _frameCallbackId = null;
    // Clamp dt so a stall (window drag, resume from pause) doesn't jump.
    final last = _lastFrame;
    final dt = last == null ? 1 / 60 : ((timestamp - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastFrame = timestamp;
    _sim.step(dt);
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_paused || _frameCallbackId != null) return;
    if (_sim.needsFullRate) {
      // Motion: skip any pending idle delay and render on the next vsync.
      _timer?.cancel();
      _timer = null;
      _requestFrame();
    } else {
      _timer ??= Timer(_idleDelay, () {
        _timer = null;
        if (!_paused) _requestFrame();
      });
    }
  }

  /// Starts or stops the frame loop to match [_paused].
  void _syncPacer() {
    if (_paused) {
      _timer?.cancel();
      _timer = null;
      final id = _frameCallbackId;
      if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _frameCallbackId = null;
      _lastFrame = null;
    } else {
      _scheduleNext();
    }
  }

  @override
  void dispose() {
    _windowHidden = true; // stops the loop
    _syncPacer();
    _lifecycle.dispose();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eq = ref.watch(eqProvider);
    final volume = ref.watch(volumeProvider);
    final hidden = !ref.watch(windowVisibleProvider);
    if (hidden != _windowHidden) {
      _windowHidden = hidden;
      _syncPacer();
    }

    // A/B switches must be heard (and seen) instantly; everything else eases.
    final compareChanged = _lastCompare != null && _lastCompare != eq.compareBypass;
    _lastCompare = eq.compareBypass;

    _sim
      ..setTargets(
        curve: eq.effectiveGains,
        processing: eq.isProcessing,
        instant: compareChanged,
      )
      ..outputLevel = volume.muted ? 0 : volume.volume;
    // A new target means motion: switch to the full rate right away.
    _scheduleNext();

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _SpectrumPainter(_sim, showOutput: widget.showOutput),
          ),
        ),
        if (widget.showCurve) EqCurveOverlay(sim: _sim),
      ],
    );
  }
}

/// Generates a plausible music spectrum and smooths it like a real analyzer
/// (fast attack, slower release, peak-hold dots that wait, then fall).
class SpectrumSimulation extends ChangeNotifier {
  SpectrumSimulation({required this.barCount})
      : frequencies = List.generate(barCount, (j) => axisToFrequency((j + 0.5) / barCount)),
        levels = List.filled(barCount, 0.0),
        peaks = List.filled(barCount, 0.0),
        _peakHold = List.filled(barCount, 0.0),
        _phaseA = List.generate(barCount, (_) => _rand.nextDouble() * math.pi * 2),
        _phaseB = List.generate(barCount, (_) => _rand.nextDouble() * math.pi * 2);

  static final math.Random _rand = math.Random();

  final int barCount;

  /// Center frequency of each bar (log-spaced on the shared axis).
  final List<double> frequencies;

  /// Bar heights and peak-dot positions, 0..1.
  final List<double> levels;
  final List<double> peaks;

  /// The EQ curve as drawn: eases toward the target, follows drags exactly.
  final List<double> curveGains = List.filled(kBandCount, 0.0);

  /// The EQ actually applied to the simulated audio (0 dB when bypassed).
  final List<double> appliedGains = List.filled(kBandCount, 0.0);

  /// 1 while the EQ is processing, 0 when off / bypassed. Used to dim the curve.
  double activeMix = 1;

  /// Set by the curve overlay while the user drags a point.
  bool dragging = false;

  /// Notifies only on frames where the curve moved, so the (static most of
  /// the time) curve layer isn't repainted 60 times a second for nothing.
  final ChangeNotifier curveChanged = ChangeNotifier();

  double outputLevel = 0.5;

  List<double> _targetCurve = List.filled(kBandCount, 0.0);
  bool _processing = true;
  bool _initialised = false;
  bool _curveDirty = true; // force a curve repaint on the next step
  bool _curveMoving = true;

  /// True while the curve is animating or being dragged: the visualizer then
  /// renders at the full display rate instead of the ~30 fps idle rate.
  bool get needsFullRate => dragging || _curveMoving;

  final List<double> _peakHold;
  final List<double> _phaseA;
  final List<double> _phaseB;
  double _time = 0;
  double _smoothedOutput = 0.5;

  static const double _bpm = 124;
  static const double _dbRange = 66; // dB span from silent to full-scale bar

  /// Updates what the simulation eases toward. With [instant] (A/B switch)
  /// the processed signal jumps immediately instead of gliding.
  void setTargets({
    required List<double> curve,
    required bool processing,
    bool instant = false,
  }) {
    for (var i = 0; i < kBandCount; i++) {
      if (curve[i] != _targetCurve[i]) _curveMoving = true;
    }
    if (processing != _processing) _curveMoving = true;
    _targetCurve = curve;
    _processing = processing;

    // While dragging, the curve must sit under the cursor in this very frame.
    if (dragging) {
      for (var i = 0; i < kBandCount; i++) {
        curveGains[i] = curve[i];
        if (processing) appliedGains[i] = curve[i];
      }
      curveChanged.notifyListeners();
    }
    if (instant || !_initialised) {
      for (var i = 0; i < kBandCount; i++) {
        appliedGains[i] = processing ? curve[i] : 0;
        if (!_initialised) curveGains[i] = curve[i];
      }
      activeMix = processing ? 1 : 0;
      _initialised = true;
      _curveDirty = true;
      curveChanged.notifyListeners();
    }
  }

  void step(double dt) {
    _time += dt;

    // Exponential easing toward the targets (≈ 0.3 s to settle).
    final ease = 1 - math.exp(-dt * 10);
    var curveMoved = _curveDirty;
    _curveDirty = false;
    for (var i = 0; i < kBandCount; i++) {
      final target = _targetCurve[i];
      final next = dragging ? target : _settle(curveGains[i], target, ease);
      if (next != curveGains[i]) curveMoved = true;
      curveGains[i] = next;
      final applied = _processing ? target : 0.0;
      appliedGains[i] = dragging && _processing ? applied : _settle(appliedGains[i], applied, ease);
    }
    final mix = _settle(activeMix, _processing ? 1.0 : 0.0, ease);
    if (mix != activeMix) curveMoved = true;
    activeMix = mix;
    if (curveMoved) curveChanged.notifyListeners();
    _curveMoving = curveMoved;
    _smoothedOutput += (outputLevel - _smoothedOutput) * ease;

    // Rhythm envelopes (exponential decays retriggered on the beat grid).
    const beat = 60 / _bpm;
    final kick = math.exp(-(_time % beat) * 10);
    final snare = math.exp(-((_time + beat) % (beat * 2)) * 12);
    final hat = 0.25 + 0.75 * math.exp(-(_time % (beat / 2)) * 28);

    // Two "melodic" partials that wander across the mids.
    final melodyA = math.log(600 * math.pow(2, 1.6 * math.sin(_time * 0.7))) / math.ln2;
    final melodyB = math.log(2400 * math.pow(2, math.sin(_time * 0.43 + 1))) / math.ln2;

    final volumeDb =
        _smoothedOutput <= 0.001 ? -120.0 : 20 * math.log(_smoothedOutput) / math.ln10;

    final attack = 1 - math.exp(-dt * 38);
    final release = 1 - math.exp(-dt * 7);
    final log40 = math.log(40) / math.ln2;
    final log900 = math.log(900) / math.ln2;
    final log4k = math.log(4000) / math.ln2;

    for (var j = 0; j < barCount; j++) {
      final f = frequencies[j];
      final t = j / (barCount - 1);
      final oct = math.log(f) / math.ln2;

      // Pink-ish tilt plus slow per-bar movement and a little jitter.
      var db = -20 - 14 * t;
      db += 3.5 * math.sin(_time * (1.1 + j * 0.07) + _phaseA[j]);
      db += 2.5 * math.sin(_time * (2.7 + j * 0.03) + _phaseB[j]);
      db += (_rand.nextDouble() - 0.5) * 4;

      db += 22 * kick * (1 - (oct - log40) / 2).clamp(0.0, 1.0); // kick < 160 Hz
      final sn = oct - log900;
      db += 12 * snare * math.exp(-sn * sn / 3); // snare around 900 Hz
      db += 14 * hat * ((oct - log4k) / 2).clamp(0.0, 1.0); // hats, top octaves
      final ma = oct - melodyA;
      final mb = oct - melodyB;
      db += 12 * math.exp(-ma * ma / 0.25) + 8 * math.exp(-mb * mb / 0.2);

      // Apply the EQ (as heard) and the master volume.
      db += interpolateGain(appliedGains, f);
      db += volumeDb;

      final target = ((db + _dbRange) / _dbRange).clamp(0.0, 1.0);
      final current = levels[j];
      levels[j] = current + (target - current) * (target > current ? attack : release);

      // Peak hold: wait ~0.6 s at the max, then fall.
      if (levels[j] >= peaks[j]) {
        peaks[j] = levels[j];
        _peakHold[j] = 0.6;
      } else if (_peakHold[j] > 0) {
        _peakHold[j] -= dt;
      } else {
        peaks[j] = math.max(levels[j], peaks[j] - dt * 0.45);
      }
    }

    notifyListeners();
  }

  /// Eases [from] toward [to], snapping once within 0.001 so the value
  /// actually settles (and the curve can stop repainting).
  static double _settle(double from, double to, double ease) {
    final next = from + (to - from) * ease;
    return (next - to).abs() < 0.001 ? to : next;
  }

  @override
  void dispose() {
    curveChanged.dispose();
    super.dispose();
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.sim, {required this.showOutput}) : super(repaint: sim);

  final SpectrumSimulation sim;
  final bool showOutput;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _paintGrid(canvas, size);
    if (showOutput) _paintBars(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final geo = CurveGeometry(size);
    final line = Paint()..strokeWidth = 1;

    // Horizontal lines at the dB marks of the scale on the left.
    for (final db in const [12.0, 6.0, 0.0, -6.0, -12.0]) {
      line.color = Colors.white.withValues(alpha: db == 0 ? 0.09 : 0.04);
      final y = geo.yForDb(db).roundToDouble() + 0.5; // crisp 1px lines
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // Vertical lines through each band (they line up with the sliders).
    line.color = Colors.white.withValues(alpha: 0.03);
    for (var i = 0; i < kBandCount; i++) {
      final x = geo.xForBand(i).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  // --- Bar rendering -------------------------------------------------------
  //
  // The bars change every frame, so they are sent to the GPU as raw
  // triangles (one draw call per layer) instead of as a Path. A path made of
  // 128 rounded rects has to be re-tessellated on the CPU every frame, which
  // kept a whole core busy on integrated graphics. Buffers are reused.

  late final Float32List _barVerts = Float32List(sim.barCount * 12);
  late final Float32List _haloVerts = Float32List(sim.barCount * 12);
  late final List<Offset> _peakPoints = List.filled(sim.barCount, Offset.zero);

  Size? _paintSize;
  late Paint _barPaint;
  late Paint _haloPaint;

  /// Gradients depend only on the size, so they're rebuilt only on resize.
  void _preparePaints(Size size) {
    if (_paintSize == size) return;
    _paintSize = size;
    final rect = Offset.zero & size;
    // Bars: deep blue at the floor → cyan → bright tips.
    _barPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.accentDeep.withValues(alpha: 0.25),
          AppColors.accent.withValues(alpha: 0.85),
          AppColors.accentSoft,
        ],
        stops: const [0, 0.6, 1],
      ).createShader(rect);
    // Halo: glow faked with a wider translucent copy of each bar (a blur
    // filter would be far more expensive every frame).
    _haloPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.accent.withValues(alpha: 0.02),
          AppColors.accent.withValues(alpha: 0.16),
        ],
      ).createShader(rect);
  }

  /// Writes bar [i] as two triangles into [v].
  static void _quad(Float32List v, int i, double l, double t, double r, double b) {
    final k = i * 12;
    v
      ..[k] = l
      ..[k + 1] = t
      ..[k + 2] = r
      ..[k + 3] = t
      ..[k + 4] = l
      ..[k + 5] = b
      ..[k + 6] = r
      ..[k + 7] = t
      ..[k + 8] = r
      ..[k + 9] = b
      ..[k + 10] = l
      ..[k + 11] = b;
  }

  void _paintBars(Canvas canvas, Size size) {
    _preparePaints(size);
    final n = sim.barCount;
    final colW = size.width / n;
    final barW = math.max(1.5, colW * 0.52);
    final haloW = math.min(colW * 0.95, barW + 4);
    final dotR = (barW * 0.6).clamp(1.4, 2.6);
    final maxH = size.height - 8;
    final floor = size.height;

    for (var j = 0; j < n; j++) {
      final cx = (j + 0.5) * colW;
      final top = floor - math.max(sim.levels[j] * maxH, 2.0);
      _quad(_barVerts, j, cx - barW / 2, top, cx + barW / 2, floor);
      _quad(_haloVerts, j, cx - haloW / 2, top - 2, cx + haloW / 2, floor);
      // Peak-hold dot sits just above the highest recent level.
      _peakPoints[j] = Offset(cx, floor - sim.peaks[j] * maxH - dotR - 3);
    }

    // Without texture coordinates the shader is mapped by position, so the
    // gradients look exactly as they would on rectangles.
    for (final (verts, paint) in [(_haloVerts, _haloPaint), (_barVerts, _barPaint)]) {
      final vertices = ui.Vertices.raw(ui.VertexMode.triangles, verts);
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
      vertices.dispose();
    }

    // Peak-hold dots (round points in a single call) with a soft halo.
    canvas
      ..drawPoints(
        ui.PointMode.points,
        _peakPoints,
        Paint()
          ..strokeWidth = (dotR + 2.5) * 2
          ..strokeCap = StrokeCap.round
          ..color = AppColors.accent.withValues(alpha: 0.22),
      )
      ..drawPoints(
        ui.PointMode.points,
        _peakPoints,
        Paint()
          ..strokeWidth = dotR * 2
          ..strokeCap = StrokeCap.round
          ..color = AppColors.accentSoft,
      );
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.sim != sim || old.showOutput != showOutput;
}
