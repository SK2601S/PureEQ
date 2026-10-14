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

@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.dark,
    this.accent = AccentColor.cyan,
    this.spectrumQuality = SpectrumQuality.balanced,
    this.closeToTray = true,
    this.startWithWindows = false,
    this.autoUpdate = true,
  });

  final ThemeChoice theme;
  final AccentColor accent;
  final SpectrumQuality spectrumQuality;

  /// Close button hides to the tray (true) or quits (false).
  final bool closeToTray;
  final bool startWithWindows;
  final bool autoUpdate;

  AppSettings copyWith({
    ThemeChoice? theme,
    AccentColor? accent,
    SpectrumQuality? spectrumQuality,
    bool? closeToTray,
    bool? startWithWindows,
    bool? autoUpdate,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      spectrumQuality: spectrumQuality ?? this.spectrumQuality,
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
      _kCloseToTray,
      _kAutoUpdate
    ]) {
      await p.remove(k);
    }
    await setStartWithWindows(false);
    state = const AppSettings();
  }
}
