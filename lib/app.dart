import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/home_page.dart';

/// Root widget. SK EQ is dark-only, so both themes point at the same data.
class SkEqApp extends StatelessWidget {
  const SkEqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SK EQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
