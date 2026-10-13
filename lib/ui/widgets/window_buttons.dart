import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';

/// Windows 11–style caption buttons (minimize / maximize-restore / close):
/// 46 px wide, full title-bar height, square corners, thin line glyphs and
/// the red close hover. Drawn by the app because the native title bar is
/// hidden. Not used on macOS, where the traffic lights stay visible.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key, this.closeTooltip = 'Close'});

  final String closeTooltip;

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CaptionButton(
          glyph: _Glyph.minimize,
          tooltip: 'Minimize',
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          glyph: _maximized ? _Glyph.restore : _Glyph.maximize,
          tooltip: _maximized ? 'Restore Down' : 'Maximize',
          onPressed: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _CaptionButton(
          glyph: _Glyph.close,
          tooltip: widget.closeTooltip,
          isClose: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final _Glyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color background;
    if (widget.isClose) {
      background = _pressed
          ? AppColors.windowsClose.withValues(alpha: 0.85)
          : _hover
              ? AppColors.windowsClose
              : Colors.transparent;
    } else {
      background = Colors.white.withValues(alpha: _pressed ? 0.04 : _hover ? 0.07 : 0);
    }
    final glyphColor =
        widget.isClose && _hover ? Colors.white : AppColors.textPrimary.withValues(alpha: 0.9);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 46,
            color: background,
            child: CustomPaint(painter: _GlyphPainter(widget.glyph, glyphColor)),
          ),
        ),
      ),
    );
  }
}

/// Thin 10 px glyphs, matching Segoe Fluent Icons' caption set.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final c = Offset((size.width / 2).roundToDouble() + 0.5, (size.height / 2).roundToDouble() + 0.5);
    const s = 5.0; // half of the 10 px glyph box

    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(c + const Offset(-s, 0), c + const Offset(s, 0), p);
      case _Glyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 2, height: s * 2),
              const Radius.circular(1.5)),
          p,
        );
      case _Glyph.restore:
        // Front square plus the corner of the one behind it.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c.dx - s, c.dy - s + 2, s * 2 - 2, s * 2 - 2),
            const Radius.circular(1.5),
          ),
          p,
        );
        final back = Path()
          ..moveTo(c.dx - s + 2, c.dy - s)
          ..lineTo(c.dx + s - 1.5, c.dy - s)
          ..arcToPoint(Offset(c.dx + s, c.dy - s + 1.5), radius: const Radius.circular(1.5))
          ..lineTo(c.dx + s, c.dy + s - 2);
        canvas.drawPath(back, p);
      case _Glyph.close:
        canvas
          ..drawLine(c + const Offset(-s, -s), c + const Offset(s, s), p)
          ..drawLine(c + const Offset(s, -s), c + const Offset(-s, s), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}
