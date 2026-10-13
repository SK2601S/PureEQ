import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/eq_band.dart';
import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';
import 'spectrum_visualizer.dart';

/// Maps dB and band indices to pixels inside the spectrum area. Shared by the
/// curve, the spectrum grid and the dB scale so they always line up.
class CurveGeometry {
  const CurveGeometry(this.size);

  final Size size;

  /// Vertical breathing room so ±12 dB points (and their glow) aren't clipped.
  static const double vPad = 18;

  double get top => vPad;
  double get bottom => size.height - vPad;
  double get midY => (top + bottom) / 2;
  double get dbScale => (bottom - top) / 2 / kMaxGain;

  double yForDb(double db) => midY - db * dbScale;
  double dbForY(double y) => (midY - y) / dbScale;

  /// Bands sit in the centre of 10 equal columns (they are one octave apart
  /// on a log axis), which is also where the sliders below are placed.
  double xForBand(int i) => (i + 0.5) / kBandCount * size.width;
  int bandForX(double x) =>
      (x / size.width * kBandCount).floor().clamp(0, kBandCount - 1);
}

/// Interactive EQ curve drawn over the spectrum.
///
/// * Drag a control point, or anywhere on the line, up and down to set that
///   band (the nearest one to the cursor).
/// * Scroll over the curve to nudge the hovered band by ±0.5 dB.
/// * Double-click a point to reset that band to 0 dB.
///
/// The curve shows the *effective* response (bands + bass/treble shelves),
/// i.e. what you hear. It eases between presets, but follows the cursor
/// exactly while dragging.
class EqCurveOverlay extends ConsumerStatefulWidget {
  const EqCurveOverlay({super.key, required this.sim});

  /// Provides the animated curve values and drives repaints every frame.
  final SpectrumSimulation sim;

  @override
  ConsumerState<EqCurveOverlay> createState() => _EqCurveOverlayState();
}

class _EqCurveOverlayState extends ConsumerState<EqCurveOverlay> {
  int? _hoverBand;
  int? _dragBand;
  Offset? _doubleTapAt;
  Size _size = Size.zero;

  /// Which band (if any) a pointer at [p] would grab: near a control point,
  /// or within a few pixels of the line itself.
  int? _hitBand(Offset p) {
    if (_size.isEmpty) return null;
    final geo = CurveGeometry(_size);
    final gains = widget.sim.curveGains;
    final band = geo.bandForX(p.dx);

    final point = Offset(geo.xForBand(band), geo.yForDb(gains[band]));
    if ((p - point).distance <= 26) return band;

    final t = (p.dx / _size.width).clamp(0.0, 1.0);
    final lineY = geo.yForDb(interpolateGain(gains, axisToFrequency(t)));
    if ((p.dy - lineY).abs() <= 20) return band;
    return null;
  }

  void _setHover(int? band) {
    if (band != _hoverBand) setState(() => _hoverBand = band);
  }

  void _dragTo(Offset p) {
    final band = _dragBand;
    if (band == null) return;
    final db = CurveGeometry(_size).dbForY(p.dy).clamp(kMinGain, kMaxGain);
    ref.read(eqProvider.notifier).setBandFromCurve(band, db);
  }

  void _endDrag() {
    widget.sim.dragging = false;
    setState(() => _dragBand = null);
  }

  void _onScroll(PointerSignalEvent event) {
    final band = _hoverBand;
    if (event is! PointerScrollEvent || band == null) return;
    final current = ref.read(eqProvider).effectiveGains[band];
    final step = event.scrollDelta.dy > 0 ? -0.5 : 0.5;
    ref.read(eqProvider.notifier).setBandFromCurve(band, current + step);
  }

  @override
  Widget build(BuildContext context) {
    final MouseCursor cursor = _dragBand != null
        ? SystemMouseCursors.grabbing
        : _hoverBand != null
            ? SystemMouseCursors.grab
            : MouseCursor.defer;

    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return MouseRegion(
          cursor: cursor,
          onHover: (e) => _setHover(_hitBand(e.localPosition)),
          onExit: (_) {
            if (_dragBand == null) _setHover(null);
          },
          child: Listener(
            onPointerSignal: _onScroll,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Use the pointer-down position so the grab is decided where
              // the user clicked, not after the drag slop.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (d) {
                final band = _hitBand(d.localPosition);
                if (band == null) return;
                widget.sim.dragging = true;
                setState(() {
                  _dragBand = band;
                  _hoverBand = band;
                });
                _dragTo(d.localPosition);
              },
              onPanUpdate: (d) => _dragTo(d.localPosition),
              onPanEnd: (_) => _endDrag(),
              onPanCancel: () {
                if (_dragBand != null) _endDrag();
              },
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: () {
                final at = _doubleTapAt;
                final band = at == null ? null : _hitBand(at);
                if (band != null) ref.read(eqProvider.notifier).setBandGain(band, 0);
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _CurvePainter(
                    widget.sim,
                    hoverBand: _hoverBand,
                    dragBand: _dragBand,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  // Repaints only on frames where the curve actually moved (see
  // SpectrumSimulation.curveChanged), not on every spectrum frame.
  _CurvePainter(this.sim, {this.hoverBand, this.dragBand})
      : super(repaint: sim.curveChanged);

  final SpectrumSimulation sim;
  final int? hoverBand;
  final int? dragBand;

  static const int _samples = 200;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final geo = CurveGeometry(size);
    final gains = sim.curveGains;

    // Dim to grey when the EQ is off or bypassed (A/B "B").
    final mix = sim.activeMix;
    final pos = Color.lerp(AppColors.textMuted, AppColors.positive, mix)!;
    final neg = Color.lerp(AppColors.textMuted, AppColors.negative, mix)!;

    final curve = Path();
    for (var k = 0; k <= _samples; k++) {
      final t = k / _samples;
      final y = geo.yForDb(interpolateGain(gains, axisToFrequency(t)));
      if (k == 0) {
        curve.moveTo(0, y);
      } else {
        curve.lineTo(t * size.width, y);
      }
    }

    // --- Area fill: cyan above 0 dB, blue below, fading toward the line. ---
    final area = Path.from(curve)
      ..lineTo(size.width, geo.midY)
      ..lineTo(0, geo.midY)
      ..close();
    final upper = Rect.fromLTRB(0, 0, size.width, geo.midY);
    final lower = Rect.fromLTRB(0, geo.midY, size.width, size.height);
    canvas
      ..save()
      ..clipRect(upper)
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pos.withValues(alpha: 0.22 * mix), pos.withValues(alpha: 0.03)],
          ).createShader(Rect.fromLTRB(0, geo.top, size.width, geo.midY)),
      )
      ..restore()
      ..save()
      ..clipRect(lower)
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [neg.withValues(alpha: 0.03), neg.withValues(alpha: 0.22 * mix)],
          ).createShader(Rect.fromLTRB(0, geo.midY, size.width, geo.bottom)),
      )
      ..restore();

    // --- Line: hard color split at 0 dB, with a soft glow underneath. ---
    final split = geo.midY / size.height;
    Shader lineShader(double alpha) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            pos.withValues(alpha: alpha),
            pos.withValues(alpha: alpha),
            neg.withValues(alpha: alpha),
            neg.withValues(alpha: alpha),
          ],
          stops: [0, split, split, 1],
        ).createShader(Offset.zero & size);

    // Glow as two wide translucent strokes (no blur filter: the whole scene
    // is recomposited every spectrum frame, so blurs here would cost GPU
    // time even while the curve is still).
    for (final (width, alpha) in const [(10.0, 0.10), (5.5, 0.22)]) {
      canvas.drawPath(
        curve,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..shader = lineShader(alpha * mix),
      );
    }
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..shader = lineShader(1),
    );

    // --- Control points. ---
    for (var i = 0; i < kBandCount; i++) {
      final g = gains[i];
      final center = Offset(geo.xForBand(i), geo.yForDb(g));
      final dragging = i == dragBand;
      final hovered = i == hoverBand;
      final color = g > 0.05
          ? pos
          : g < -0.05
              ? neg
              : Color.lerp(AppColors.textMuted, AppColors.accent, mix * 0.7)!;
      final radius = dragging ? 8.0 : hovered ? 7.0 : 5.0;

      if (dragging || hovered) {
        canvas
          ..drawCircle(center, radius + 8, Paint()..color = color.withValues(alpha: 0.10))
          ..drawCircle(center, radius + 4, Paint()..color = color.withValues(alpha: 0.22));
      }
      canvas.drawCircle(center, radius, Paint()..color = AppColors.inset);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      if (g.abs() >= 0.05 || dragging || hovered) {
        canvas.drawCircle(center, dragging ? 3 : 2.2, Paint()..color = color);
      }
    }

    // --- Value bubble for the hovered / dragged point. ---
    final active = dragBand ?? hoverBand;
    if (active != null) _paintBubble(canvas, size, geo, active, gains[active], pos, neg);
  }

  void _paintBubble(
    Canvas canvas,
    Size size,
    CurveGeometry geo,
    int band,
    double gain,
    Color pos,
    Color neg,
  ) {
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: '${formatFrequency(kBandFrequencies[band])} Hz  ',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        TextSpan(
          text: '${formatGain(gain)} dB',
          style: TextStyle(
            color: gain > 0.05 ? pos : gain < -0.05 ? neg : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();

    final point = Offset(geo.xForBand(band), geo.yForDb(gain));
    final w = tp.width + 16;
    final h = tp.height + 10;
    // Above the point, or below it when too close to the top edge.
    final above = point.dy - 16 - h >= 0;
    final left = (point.dx - w / 2).clamp(4.0, size.width - w - 4);
    final top = above ? point.dy - 16 - h : point.dy + 16;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      rect.shift(const Offset(0, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.surfaceHigh);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border,
    );
    tp.paint(canvas, Offset(left + 8, top + 5));
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.sim != sim || old.hoverBand != hoverBand || old.dragBand != dragBand;
}
