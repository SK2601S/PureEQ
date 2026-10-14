import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/startup_service.dart';
import '../theme/app_theme.dart';
import 'eq_provider.dart';

/// Dark, light, or follow the Windows / macOS setting.
enum ThemeChoice { dark, light, system }

/// Spectrum frame rate when idle — a CPU/battery trade-off.
enum SpectrumQuality {
  smooth('Smooth', Duration.zero), // every screen refresh
  balanced('Balanced', Duration(milliseconds: 22)), // ~30 fps
  saver('Battery saver', Duration(milliseconds: 60)); // ~15 fps

  const SpectrumQuality(this.label, this.idleDelay);
  final String label;

  /// Wait before requesting the next idle frame (see SpectrumVisualizer).
  final Duration idleDelay;
}

/// How the spectrum is drawn.
enum SpectrumStyle {
  bars('Bars'),
  wave('Wave'),
  mirror('Mirror'),
  led('LED');

  const SpectrumStyle(this.label);
  final String label;
}

/// How many columns the spectrum shows (the analysis has 128).
enum BarDensity {
  fine('Fine', 128),
  medium('Medium', 64),
  wide('Wide', 32);

  const BarDensity(this.label, this.columns);
  final String label;
  final int columns;
}

@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.dark,
    this.accent = AccentColor.cyan,
    this.spectrumQuality = SpectrumQuality.balanced,
    this.spectrumStyle = SpectrumStyle.bars,
    this.barDensity = BarDensity.fine,
    this.showPeaks = true,
    this.closeToTray = true,
    this.startWithWindows = false,
    this.autoUpdate = true,
  });

  final ThemeChoice theme;
  final AccentColor accent;
  final SpectrumQuality spectrumQuality;
  final SpectrumStyle spectrumStyle;
  final BarDensity barDensity;
  final bool showPeaks;

  /// Close button hides to the tray (true) or quits (false).
  final bool closeToTray;
  final bool startWithWindows;
  final bool autoUpdate;

  AppSettings copyWith({
    ThemeChoice? theme,
    AccentColor? accent,
    SpectrumQuality? spectrumQuality,
    SpectrumStyle? spectrumStyle,
    BarDensity? barDensity,
    bool? showPeaks,
    bool? closeToTray,
    bool? startWithWindows,
    bool? autoUpdate,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      spectrumQuality: spectrumQuality ?? this.spectrumQuality,
      spectrumStyle: spectrumStyle ?? this.spectrumStyle,
      barDensity: barDensity ?? this.barDensity,
      showPeaks: showPeaks ?? this.showPeaks,
      closeToTray: closeToTray ?? this.closeToTray,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      autoUpdate: autoUpdate ?? this.autoUpdate,
    );
  }
}

final startupServiceProvider =
    Provider<StartupService>((ref) => StartupService());

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// App preferences (Settings dialog), saved in SharedPreferences.
class SettingsNotifier extends Notifier<AppSettings> {
  static const _kTheme = 'pureeq.ui.theme';
  static const _kAccent = 'pureeq.ui.accent';
  static const _kQuality = 'pureeq.spectrumQuality';
  static const _kStyle = 'pureeq.spectrumStyle';
  static const _kDensity = 'pureeq.barDensity';
  static const _kPeaks = 'pureeq.showPeaks';
  static const _kCloseToTray = 'pureeq.closeToTray';
  static const _kAutoUpdate = 'pureeq.autoUpdate';

  @override
  AppSettings build() {
    final p = ref.read(sharedPreferencesProvider);
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final name = p.getString(key);
      return values.firstWhere((v) => v.name == name, orElse: () => fallback);
    }

    // The Run entry is the source of truth for "start with Windows".
    Future.microtask(() async {
      final enabled = await ref.read(startupServiceProvider).isEnabled();
      if (enabled != state.startWithWindows) {
        state = state.copyWith(startWithWindows: enabled);
      }
    });

    return AppSettings(
      theme: pick(ThemeChoice.values, _kTheme, ThemeChoice.dark),
      accent: pick(AccentColor.values, _kAccent, AccentColor.cyan),
      spectrumQuality:
          pick(SpectrumQuality.values, _kQuality, SpectrumQuality.balanced),
      spectrumStyle: pick(SpectrumStyle.values, _kStyle, SpectrumStyle.bars),
      barDensity: pick(BarDensity.values, _kDensity, BarDensity.fine),
      showPeaks: p.getBool(_kPeaks) ?? true,
      closeToTray: p.getBool(_kCloseToTray) ?? true,
      autoUpdate: p.getBool(_kAutoUpdate) ?? true,
    );
  }

  void setTheme(ThemeChoice v) {
    state = state.copyWith(theme: v);
    ref.read(sharedPreferencesProvider).setString(_kTheme, v.name);
  }

  void setAccent(AccentColor v) {
    state = state.copyWith(accent: v);
    ref.read(sharedPreferencesProvider).setString(_kAccent, v.name);
  }

  void setSpectrumQuality(SpectrumQuality v) {
    state = state.copyWith(spectrumQuality: v);
    ref.read(sharedPreferencesProvider).setString(_kQuality, v.name);
  }

  void setSpectrumStyle(SpectrumStyle v) {
    state = state.copyWith(spectrumStyle: v);
    ref.read(sharedPreferencesProvider).setString(_kStyle, v.name);
  }

  void setBarDensity(BarDensity v) {
    state = state.copyWith(barDensity: v);
    ref.read(sharedPreferencesProvider).setString(_kDensity, v.name);
  }

  void setShowPeaks(bool v) {
    state = state.copyWith(showPeaks: v);
    ref.read(sharedPreferencesProvider).setBool(_kPeaks, v);
  }

  void setCloseToTray(bool v) {
    state = state.copyWith(closeToTray: v);
    ref.read(sharedPreferencesProvider).setBool(_kCloseToTray, v);
  }

  void setAutoUpdate(bool v) {
    state = state.copyWith(autoUpdate: v);
    ref.read(sharedPreferencesProvider).setBool(_kAutoUpdate, v);
  }

  Future<void> setStartWithWindows(bool v) async {
    await ref.read(startupServiceProvider).setEnabled(v);
    state = state.copyWith(
        startWithWindows: await ref.read(startupServiceProvider).isEnabled());
  }

  /// Back to defaults (EQ settings and presets are kept).
  Future<void> reset() async {
    final p = ref.read(sharedPreferencesProvider);
    for (final k in [
      _kTheme,
      _kAccent,
      _kQuality,
      _kStyle,
      _kDensity,
      _kPeaks,
      _kCloseToTray,
      _kAutoUpdate
    ]) {
      await p.remove(k);
    }
    await setStartWithWindows(false);
    state = const AppSettings();
  }
}
