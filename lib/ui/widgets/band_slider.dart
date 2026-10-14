import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/eq_band.dart';
import '../../theme/app_theme.dart';

/// Shared vertical layout of a band slider, so [BandScale] can line its
/// labels up with the slider tracks.
class BandSliderLayout {
  BandSliderLayout._();

  static const double headerHeight = 22;
  static const double footerHeight = 34;
  static const double thumbHalfHeight = 8;

  /// Y of [db] inside a track area of [height].
  static double yFor(double db, double height) {
    const top = thumbHalfHeight;
    final bottom = height - thumbHalfHeight;
    return top + (kMaxGain - db) / (kMaxGain - kMinGain) * (bottom - top);
  }
}

/// Vertical, bipolar (-12 … +12 dB) slider for one EQ band.
///
/// * Drag up/down to set the gain in 0.5 dB steps.
/// * Mouse wheel nudges by ±0.5 dB; double-click resets to 0 dB.
/// * Boosts fill in bright cyan, cuts in blue.
/// * When [value] changes from outside (preset load, curve drag elsewhere,
///   reset) the thumb glides to the new position instead of jumping.
class BandSlider extends StatefulWidget {
  const BandSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  /// Visual only: the slider stays editable while the EQ is off.
  final bool enabled;

  @override
  State<BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<BandSlider> {
  bool _dragging = false;
  bool _hovering = false;

  double _valueFromDy(double dy, double height) {
    const pad = BandSliderLayout.thumbHalfHeight;
    final usable = (height - pad * 2).clamp(1.0, double.infinity);
    final t = ((dy - pad) / usable).clamp(0.0, 1.0);
    final v = kMaxGain - t * (kMaxGain - kMinGain);
    return (v * 2).roundToDouble() / 2; // snap to 0.5 dB
  }

  void _set(double v) {
    final clamped = v.clamp(kMinGain, kMaxGain);
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  void _endDrag() => setState(() => _dragging = false);

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      // No animation while dragging (the thumb must track the pointer).
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.value),
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          final color = AppColors.forGain(v, enabled: widget.enabled);
          return Column(
            children: [
              SizedBox(
                height: BandSliderLayout.headerHeight,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: widget.label,
                      style: TextStyle(
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' Hz',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 10),
                    ),
                  ]),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _set(widget.value +
                            (event.scrollDelta.dy > 0 ? -0.5 : 0.5));
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (d) {
                        setState(() => _dragging = true);
                        _set(_valueFromDy(d.localPosition.dy, c.maxHeight));
                      },
                      onVerticalDragUpdate: (d) =>
                          _set(_valueFromDy(d.localPosition.dy, c.maxHeight)),
                      onVerticalDragEnd: (_) => _endDrag(),
                      onVerticalDragCancel: _endDrag,
                      onDoubleTap: () => _set(0),
                      child: CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: _BandSliderPainter(
                          value: v,
                          enabled: widget.enabled,
                          highlighted: active,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: BandSliderLayout.footerHeight,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? color.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${formatGain(v)} dB',
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BandSliderPainter extends CustomPainter {
  _BandSliderPainter({
    required this.value,
    required this.enabled,
    required this.highlighted,
  });

  static const double _trackWidth = 6;

  final double value;
  final bool enabled;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const half = BandSliderLayout.thumbHalfHeight;
    double yFor(double db) => BandSliderLayout.yFor(db, size.height);

    final color = AppColors.forGain(value, enabled: enabled);

    // Tick marks at ±12, ±6 and 0 dB.
    final tick = Paint()..strokeWidth = 1;
    for (final db in [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = yFor(db).roundToDouble() + 0.5;
      final isZero = db == 0;
      tick.color = AppColors.overlay.withValues(alpha: isZero ? 0.22 : 0.09);
      final len = isZero ? 7.0 : 4.0;
      canvas.drawLine(Offset(cx - 9 - len, y), Offset(cx - 9, y), tick);
      canvas.drawLine(Offset(cx + 9, y), Offset(cx + 9 + len, y), tick);
    }

    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - _trackWidth / 2, half, cx + _trackWidth / 2,
            size.height - half),
        const Radius.circular(_trackWidth / 2),
      ),
      Paint()..color = AppColors.track,
    );

    // Fill from 0 dB to the value, with a glow in the gain color.
    final y0 = yFor(0);
    final yv = yFor(value);
    if ((yv - y0).abs() > 0.5) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          cx - _trackWidth / 2,
          yv < y0 ? yv : y0,
          cx + _trackWidth / 2,
          yv < y0 ? y0 : yv,
        ),
        const Radius.circular(_trackWidth / 2),
      );
      if (enabled) {
        // Blur-free glow: two translucent, slightly wider copies.
        final a = highlighted ? 1.0 : 0.6;
        canvas
          ..drawRRect(fill.inflate(4),
              Paint()..color = color.withValues(alpha: 0.10 * a))
          ..drawRRect(fill.inflate(2),
              Paint()..color = color.withValues(alpha: 0.22 * a));
      }
      canvas.drawRRect(fill, Paint()..color = color);
    }

    // Thumb: a light pill with a colored centre line.
    final thumbW = (size.width * 0.6).clamp(22.0, 34.0);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, yv), width: thumbW, height: half * 2),
      const Radius.circular(half),
    );
    if (enabled) {
      final glow = value.abs() < 0.05 ? AppColors.accent : color;
      final a = highlighted ? 1.0 : 0.5;
      canvas
        ..drawRRect(
            thumb.inflate(5), Paint()..color = glow.withValues(alpha: 0.08 * a))
        ..drawRRect(thumb.inflate(2.5),
            Paint()..color = glow.withValues(alpha: 0.2 * a));
    }
    canvas.drawRRect(
      thumb,
      Paint()
        ..color = enabled ? const Color(0xFFEFFBFF) : const Color(0xFF8A8A90),
    );
    if (!AppColors.isDark) {
      // Light theme: outline so the white knob stands out on white cards.
      canvas.drawRRect(
        thumb,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.textMuted,
      );
    }
    canvas.drawLine(
      Offset(cx - thumbW / 2 + 7, yv),
      Offset(cx + thumbW / 2 - 7, yv),
      Paint()
        ..color = enabled
            ? (value < -0.05 ? AppColors.negative : AppColors.accentDeep)
            : AppColors.textMuted
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BandSliderPainter old) =>
      old.value != value ||
      old.enabled != enabled ||
      old.highlighted != highlighted;
}

/// dB labels (+12 … -12) aligned with the band slider tracks. Sits in the
/// left gutter under the spectrum's dB scale.
class BandScale extends StatelessWidget {
  const BandScale({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: BandSliderLayout.headerHeight),
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: DbScalePainter(
                (db, size) => BandSliderLayout.yFor(db, size.height)),
          ),
        ),
        const SizedBox(height: BandSliderLayout.footerHeight),
      ],
    );
  }
}

/// Right-aligned "+12 / +6 / 0 / -6 / -12" labels at positions given by [yFor].
/// Also used for the spectrum's dB scale.
class DbScalePainter extends CustomPainter {
  DbScalePainter(this.yFor);

  final double Function(double db, Size size) yFor;

  static const List<double> marks = [12, 6, 0, -6, -12];

  @override
  void paint(Canvas canvas, Size size) {
    for (final db in marks) {
      final tp = TextPainter(
        text: TextSpan(
          text: db == 0 ? '0' : (db > 0 ? '+${db.toInt()}' : '${db.toInt()}'),
          style: TextStyle(
            color: db == 0 ? AppColors.textSecondary : AppColors.textMuted,
            fontSize: 10,
            fontWeight: db == 0 ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = yFor(db, size);
      tp.paint(canvas, Offset(size.width - tp.width - 6, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(DbScalePainter old) => false;
}
