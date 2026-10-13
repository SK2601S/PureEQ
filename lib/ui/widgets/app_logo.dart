import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Glowing gradient badge with an equalizer glyph.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.accentDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.45),
            blurRadius: 14,
          ),
        ],
      ),
      child: Icon(Icons.graphic_eq_rounded, color: Colors.black, size: size * 0.62),
    );
  }
}
