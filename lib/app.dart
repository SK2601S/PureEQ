import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

/// Root widget. Applies the theme (dark / light / follow the system) and the
/// accent color chosen in Settings.
class SkEqApp extends ConsumerStatefulWidget {
  const SkEqApp({super.key});

  @override
  ConsumerState<SkEqApp> createState() => _SkEqAppState();
}

class _SkEqAppState extends ConsumerState<SkEqApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Windows / macOS switched between light and dark ("follow system").
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider.select((s) => (s.theme, s.accent)));
    final brightness = switch (settings.$1) {
      ThemeChoice.dark => Brightness.dark,
      ThemeChoice.light => Brightness.light,
      ThemeChoice.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    AppColors.apply(Palette.of(brightness, settings.$2));
    final theme = AppTheme.current;

    return MaterialApp(
      title: 'SK EQ',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const HomePage(),
    );
  }
}
