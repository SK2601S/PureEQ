import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    title: 'PureEQ',
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
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const PureEqApp(),
    ),
  );
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
