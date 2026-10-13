import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'providers/eq_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Window setup -------------------------------------------------------
  // The native title bar is hidden so we can draw our own: on macOS the
  // traffic-light buttons stay visible, on Windows we render Windows 11
  // style caption buttons.
  await windowManager.ensureInitialized();
  final (size, minimumSize) = await _windowSizes();
  final windowOptions = WindowOptions(
    title: 'SK EQ',
    size: size,
    minimumSize: minimumSize,
    center: true,
    backgroundColor: AppColors.background,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // --- Persistence --------------------------------------------------------
  // Loaded once up front so providers can read it synchronously.
  await _migrateSettingsFromPureEq();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const SkEqApp(),
    ),
  );
}

/// SK EQ used to be called PureEQ. On Windows, settings live in a folder named
/// after the app (`%APPDATA%\<company>\<product>`), so the rename would start
/// with no presets. On first launch, copy the old settings file across.
/// (macOS keys settings by bundle id, which did not change.)
Future<void> _migrateSettingsFromPureEq() async {
  if (!Platform.isWindows) return;
  try {
    final newDir = await getApplicationSupportDirectory(); // …\SK EQ\SK EQ
    final appData = newDir.parent.parent.path;
    final sep = Platform.pathSeparator;
    final newFile = File('${newDir.path}${sep}shared_preferences.json');
    final oldFile = File('$appData${sep}PureEQ${sep}PureEQ${sep}shared_preferences.json');
    if (!await newFile.exists() && await oldFile.exists()) {
      await newDir.create(recursive: true);
      await oldFile.copy(newFile.path);
    }
  } catch (e) {
    debugPrint('SK EQ: could not migrate PureEQ settings: $e');
  }
}

/// Preferred and minimum window sizes, shrunk to fit the screen's work area
/// (excluding the taskbar / Dock). E.g. a 1080p laptop at 125 % scaling only
/// has ~1536 × 816 logical pixels available.
Future<(Size, Size)> _windowSizes() async {
  const preferred = Size(1200, 820);
  const minimum = Size(960, 660);
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final area = display.visibleSize ?? display.size;
    final fit = Size(
      math.min(preferred.width, area.width * 0.94),
      math.min(preferred.height, area.height * 0.94),
    );
    final min = Size(
      math.min(minimum.width, fit.width),
      math.min(minimum.height, fit.height),
    );
    return (fit, min);
  } catch (_) {
    return (preferred, minimum);
  }
}
