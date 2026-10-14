import 'package:flutter/material.dart';

/// Accent colors the user can pick in Settings.
enum AccentColor {
  cyan('Cyan', Color(0xFF00D4FF), Color(0xFF0A6CFF), Color(0xFFB8F4FF),
      Color(0xFF3DE6FF), Color(0xFF3D7BFF)),
  purple('Purple', Color(0xFFB26BFF), Color(0xFF6A3DFF), Color(0xFFE5CCFF),
      Color(0xFFC690FF), Color(0xFF6F7BFF)),
  green('Green', Color(0xFF2FE39A), Color(0xFF0FA36B), Color(0xFFC4FBE2),
      Color(0xFF5CF0B2), Color(0xFF2FB8E3)),
  orange('Orange', Color(0xFFFF9F2E), Color(0xFFFF5A1F), Color(0xFFFFE0B8),
      Color(0xFFFFB85C), Color(0xFFFF6A3D)),
  pink('Pink', Color(0xFFFF5FA8), Color(0xFFD6337A), Color(0xFFFFD0E6),
      Color(0xFFFF85BD), Color(0xFFB266FF)),
  blue('Blue', Color(0xFF4D8DFF), Color(0xFF2A4DFF), Color(0xFFCCDDFF),
      Color(0xFF75A8FF), Color(0xFF8F6BFF));

  const AccentColor(this.label, this.main, this.deep, this.soft, this.positive,
      this.negative);

  final String label;
  final Color main; // glow, curve, buttons
  final Color deep; // gradient partner
  final Color soft; // highlights / bar tips
  final Color positive; // boosts
  final Color negative; // cuts
}

/// One complete set of colors: a dark or light base plus an accent.
class Palette {
  const Palette._({
    required this.id,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.inset,
    required this.border,
    required this.track,
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
    required this.positive,
    required this.negative,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.overlay,
  });

  factory Palette.of(Brightness brightness, AccentColor a) {
    if (brightness == Brightness.dark) {
      return Palette._(
        id: '${brightness.name}-${a.name}',
        brightness: brightness,
        background: const Color(0xFF0B0B0D),
        surface: const Color(0xFF161618),
        surfaceHigh: const Color(0xFF202024),
        inset: const Color(0xFF0F0F12),
        border: const Color(0xFF26262B),
        track: const Color(0xFF2B2B31),
        accent: a.main,
        accentDeep: a.deep,
        accentSoft: a.soft,
        positive: a.positive,
        negative: a.negative,
        textPrimary: const Color(0xFFF2F2F7),
        textSecondary: const Color(0xFF9A9AA1),
        textMuted: const Color(0xFF5E5E66),
        overlay: Colors.white,
      );
    }
    // Light: same accent, deepened a little for contrast on white.
    Color deepen(Color c) => Color.lerp(c, Colors.black, 0.18)!;
    return Palette._(
      id: '${brightness.name}-${a.name}',
      brightness: brightness,
      background: const Color(0xFFF1F2F5),
      surface: const Color(0xFFFFFFFF),
      surfaceHigh: const Color(0xFFEDEEF2),
      inset: const Color(0xFFF7F8FA),
      border: const Color(0xFFDADCE2),
      track: const Color(0xFFD3D6DD),
      accent: deepen(a.main),
      accentDeep: a.deep,
      accentSoft: a.main,
      positive: deepen(a.positive),
      negative: deepen(a.negative),
      textPrimary: const Color(0xFF16171A),
      textSecondary: const Color(0xFF5B5F68),
      textMuted: const Color(0xFF959AA4),
      overlay: Colors.black,
    );
  }

  /// e.g. "dark-cyan"; changes whenever the look changes.
  final String id;
  final Brightness brightness;
  final Color background, surface, surfaceHigh, inset, border, track;
  final Color accent, accentDeep, accentSoft, positive, negative;
  final Color textPrimary, textSecondary, textMuted;

  /// White on dark, black on light: for faint grid lines and hover tints.
  final Color overlay;
}

/// Central color access for SK EQ. Reads the current [Palette], which the
/// app swaps when the theme or accent changes in Settings.
class AppColors {
  AppColors._();

  static Palette _p = Palette.of(Brightness.dark, AccentColor.cyan);

  /// Switches every color at once (the UI is rebuilt right after).
  static void apply(Palette palette) => _p = palette;

  static Palette get palette => _p;
  static bool get isDark => _p.brightness == Brightness.dark;

  static Color get background => _p.background;
  static Color get surface => _p.surface; // cards
  static Color get surfaceHigh => _p.surfaceHigh; // raised controls, menus
  static Color get inset => _p.inset; // recessed areas (spectrum well)
  static Color get border => _p.border;
  static Color get track => _p.track;

  static Color get accent => _p.accent;
  static Color get accentDeep => _p.accentDeep; // gradient partner
  static Color get accentSoft => _p.accentSoft; // highlights / bar tips

  /// Boosts are drawn in a brighter shade, cuts in a cooler one, so the
  /// direction of every band is readable at a glance.
  static Color get positive => _p.positive;
  static Color get negative => _p.negative;

  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  /// White in dark mode, black in light mode (faint lines, hover tints).
  static Color get overlay => _p.overlay;

  /// Readable text/icon color on top of [accent].
  static Color get onAccent =>
      _p.accent.computeLuminance() > 0.35 ? Colors.black : Colors.white;

  static const danger = Color(0xFFFF453A);
  static const bypass = Color(0xFFFFB340); // A/B "B" (bypassed) state
  static const windowsClose = Color(0xFFC42B1C); // Windows 11 close hover

  /// Color for a gain value: cyan for boosts, blue for cuts, grey at 0 dB.
  static Color forGain(double db, {bool enabled = true}) {
    if (!enabled) return textMuted;
    if (db > 0.05) return positive;
    if (db < -0.05) return negative;
    return textSecondary;
  }
}

/// Material 3 theme built from the current [Palette] (dark or light).
class AppTheme {
  AppTheme._();

  static ThemeData get current {
    final dark = AppColors.isDark;
    final scheme =
        (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.border,
      error: AppColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dividerColor: AppColors.border,
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 20),

      // Master volume slider.
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.track,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        showValueIndicator: ShowValueIndicator.never,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.track,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inset,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        width: 360,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
