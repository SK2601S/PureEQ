import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/eq_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../providers/window_provider.dart';
import '../services/tray_service.dart';
import '../theme/app_theme.dart';
import 'widgets/bass_treble_controls.dart';
import 'widgets/bottom_controls.dart';
import 'widgets/eq_panel.dart';
import 'widgets/save_preset_dialog.dart';
import 'widgets/top_bar.dart';
import 'widgets/update_banner.dart';

/// Main (and only) screen:
///
///   ┌ TopBar ─ logo · title ········ EQ on/off · presets · ⋯ · ─ ▢ ✕ ┐
///   │ UpdateBanner ─ slides in when a new version is available        │
///   │ EqPanel ─ spectrum + draggable EQ curve, 10 band sliders        │
///   │ BassTrebleControls ─ low / high shelves                         │
///   └ BottomControls ─ volume · mute ········ A/B · reset · save      ┘
///
/// Also owns the tray icon. When it exists, closing the window hides
/// SK EQ to the tray (it keeps running) and "Quit" lives in the tray menu.
///
/// Keyboard: B = A/B compare, E = EQ on/off, Ctrl/⌘+S = save preset.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WindowListener {
  final TrayService _tray = TrayService();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    final trayReady = _tray.init(
      eqEnabled: ref.read(eqProvider).enabled,
      onShow: _showWindow,
      onEqChanged: (on) => ref.read(eqProvider.notifier).setEnabled(on),
      onCheckUpdates: () async {
        await _showWindow();
        if (mounted) checkForUpdatesManually(context, ref);
      },
      onQuit: _quit,
    );
    // Only hide-to-tray if there is a tray to come back from.
    if (trayReady) {
      windowManager.setPreventClose(true);
    } else if (!ref.read(windowVisibleProvider)) {
      // Started with --minimized but no tray to restore from: show the window.
      _showWindow();
    }

    // Updates: quiet check shortly after startup and every few hours. The
    // installer needs SK EQ closed, so give the updater a way to quit.
    ref.read(updateProvider.notifier)
      ..quitForInstall = _quit
      ..startAutomaticChecks();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tray.dispose();
    super.dispose();
  }

  /// Close button / Alt+F4 / ⌘W: hide to the tray, or quit (Settings).
  @override
  void onWindowClose() async {
    if (!await windowManager.isPreventClose()) return;
    if (ref.read(settingsProvider).closeToTray) {
      _setVisible(false);
      await windowManager.hide();
      // Keeps running in the tray; save now in case the computer shuts down.
      await ref.read(eqProvider.notifier).flush();
    } else {
      await _quit();
    }
  }

  // Pause the spectrum while the window can't be seen.
  @override
  void onWindowMinimize() => _setVisible(false);

  @override
  void onWindowRestore() => _setVisible(true);

  @override
  void onWindowFocus() => _setVisible(true);

  void _setVisible(bool visible) =>
      ref.read(windowVisibleProvider.notifier).state = visible;

  Future<void> _showWindow() async {
    _setVisible(true);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Quit from the tray menu, or to let the updater replace the app.
  ///
  /// Ends the process directly instead of `windowManager.destroy()`: tearing
  /// the window down that way crashed inside flutter_windows.dll
  /// (0xc000041d, an exception in a window callback) once the tray icon had
  /// been removed. Nothing is lost — pending settings are saved first, and
  /// the tray icon is removed explicitly so no ghost icon is left behind.
  Future<void> _quit() async {
    _tray.dispose();
    await ref.read(eqProvider.notifier).flush();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the tray menu's checkmark in sync with the EQ switch.
    ref.listen(
        eqProvider.select((s) => s.enabled), (_, on) => _tray.setEqEnabled(on));

    final notifier = ref.read(eqProvider.notifier);
    final showUpdateBanner =
        ref.watch(updateProvider.select((s) => s.bannerVisible));
    final closeToTray =
        ref.watch(settingsProvider.select((s) => s.closeToTray));
    // Rebuild on theme / accent changes (and system light/dark switches,
    // which arrive through Theme). The palette has already been applied by
    // SkEqApp; the body below is keyed by it, so everything redraws.
    ref.watch(settingsProvider.select((s) => (s.theme, s.accent)));
    Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB): notifier.toggleCompare,
        const SingleActivator(LogicalKeyboardKey.keyE): notifier.toggleEnabled,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            saveCurrentAsPreset(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            saveCurrentAsPreset(context, ref),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background,
          // Keyed by the palette: a theme/accent change rebuilds the whole
          // screen (const widgets and cached painters included).
          body: KeyedSubtree(
            key: ValueKey(AppColors.palette.id),
            child: Column(
              children: [
                TopBar(
                    closeTooltip: _tray.isAvailable && closeToTray
                        ? 'Close to tray'
                        : 'Close'),
                // New-version message: slides down under the title bar.
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: showUpdateBanner
                        ? const UpdateBanner()
                        : const SizedBox(width: double.infinity),
                  ),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 2, 20, 16),
                    child: Column(
                      children: [
                        Expanded(child: EqPanel()),
                        SizedBox(height: 14),
                        BassTrebleControls(),
                      ],
                    ),
                  ),
                ),
                const BottomControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
