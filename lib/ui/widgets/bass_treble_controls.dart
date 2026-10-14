import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/eq_band.dart';
import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';
import 'panel.dart';

/// Bass and Treble shelves. They layer on top of the 10-band curve (see
/// EqState.effectiveGains), so you can tilt any preset without editing it.
class BassTrebleControls extends ConsumerWidget {
  const BassTrebleControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(eqProvider);
    final notifier = ref.read(eqProvider.notifier);

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: _ShelfControl(
              icon: Icons.speaker_rounded,
              label: 'Bass',
              caption: 'Low shelf · 31–250 Hz',
              value: eq.bass,
              enabled: eq.enabled,
              onChanged: notifier.setBass,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: AppColors.border,
          ),
          Expanded(
            child: _ShelfControl(
              icon: Icons.music_note_rounded,
              label: 'Treble',
              caption: 'High shelf · 4–16 kHz',
              value: eq.treble,
              enabled: eq.enabled,
              onChanged: notifier.setTreble,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfControl extends StatelessWidget {
  const _ShelfControl({
    required this.icon,
    required this.label,
    required this.caption,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String caption;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forGain(value, enabled: enabled);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: enabled ? 1 : 0.5,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(caption,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: BipolarSlider(
                value: value, enabled: enabled, onChanged: onChanged),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Double-click to reset',
            child: GestureDetector(
              onDoubleTap: () => onChanged(0),
              child: SizedBox(
                width: 68,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                  child: Text('${formatGain(value)} dB',
                      textAlign: TextAlign.right),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal ±12 dB slider that fills outward from the centre (0 dB),
/// cyan for boosts and blue for cuts. Click or drag to set, scroll to nudge,
/// double-click to reset.
class BipolarSlider extends StatefulWidget {
  const BipolarSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<BipolarSlider> createState() => _BipolarSliderState();
}

class _BipolarSliderState extends State<BipolarSlider> {
  bool _dragging = false;
  bool _hovering = false;

  static const double _pad = 10; // keeps the thumb inside at ±12 dB

  double _valueFromDx(double dx, double width) {
    final t = ((dx - _pad) / (width - _pad * 2)).clamp(0.0, 1.0);
    final v = kMinGain + t * (kMaxGain - kMinGain);
    return (v * 2).roundToDouble() / 2; // 0.5 dB steps
  }

  void _set(double v) {
    final clamped = v.clamp(kMinGain, kMaxGain);
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: LayoutBuilder(
        builder: (context, c) => Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _set(widget.value + (e.scrollDelta.dy > 0 ? -0.5 : 0.5));
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                _set(_valueFromDx(d.localPosition.dx, c.maxWidth)),
            onDoubleTap: () => _set(0),
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              _set(_valueFromDx(d.localPosition.dx, c.maxWidth));
            },
            onHorizontalDragUpdate: (d) =>
                _set(_valueFromDx(d.localPosition.dx, c.maxWidth)),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: widget.value),
              duration:
                  _dragging ? Duration.zero : const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                size: Size(c.maxWidth, 32),
                painter: _BipolarPainter(
                  value: v,
                  enabled: widget.enabled,
                  highlighted: _hovering || _dragging,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BipolarPainter extends CustomPainter {
  _BipolarPainter(
      {required this.value, required this.enabled, required this.highlighted});

  final double value;
  final bool enabled;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = _BipolarSliderState._pad;
    final cy = size.height / 2;
    double xFor(double db) =>
        pad + (db - kMinGain) / (kMaxGain - kMinGain) * (size.width - pad * 2);
    final color = AppColors.forGain(value, enabled: enabled);

    // Track + centre tick.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(pad, cy - 2, size.width - pad, cy + 2),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.track,
    );
    final x0 = xFor(0);
    canvas.drawLine(
      Offset(x0, cy - 7),
      Offset(x0, cy + 7),
      Paint()
        ..color = AppColors.overlay.withValues(alpha: 0.2)
        ..strokeWidth = 1,
    );

    // Fill from 0 dB outward.
    final xv = xFor(value);
    if ((xv - x0).abs() > 0.5) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTRB(xv < x0 ? xv : x0, cy - 2, xv < x0 ? x0 : xv, cy + 2),
        const Radius.circular(2),
      );
      if (enabled) {
        // Blur-free glow (cheap to redraw every frame).
        canvas
          ..drawRRect(
              fill.inflate(4), Paint()..color = color.withValues(alpha: 0.10))
          ..drawRRect(
              fill.inflate(2), Paint()..color = color.withValues(alpha: 0.22));
      }
      canvas.drawRRect(fill, Paint()..color = color);
    }

    // Thumb.
    final ring = value.abs() < 0.05 ? AppColors.accent : color;
    if (enabled) {
      final a = highlighted ? 1.0 : 0.55;
      canvas
        ..drawCircle(Offset(xv, cy), 14,
            Paint()..color = ring.withValues(alpha: 0.08 * a))
        ..drawCircle(Offset(xv, cy), 10.5,
            Paint()..color = ring.withValues(alpha: 0.2 * a));
    }
    canvas.drawCircle(
      Offset(xv, cy),
      7,
      Paint()
        ..color = enabled ? const Color(0xFFEFFBFF) : const Color(0xFF8A8A90),
    );
    canvas.drawCircle(
      Offset(xv, cy),
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = enabled ? ring : AppColors.textMuted,
    );
  }

  @override
  bool shouldRepaint(_BipolarPainter old) =>
      old.value != value ||
      old.enabled != enabled ||
      old.highlighted != highlighted;
}
