import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/home_page.dart';

/// Root widget. PureEQ is dark-only, so both themes point at the same data.
class PureEqApp extends StatelessWidget {
  const PureEqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureEQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
