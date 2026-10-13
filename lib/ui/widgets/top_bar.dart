import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';
import 'app_logo.dart';
import 'app_menu.dart';
import 'preset_selector.dart';
import 'sound_status.dart';
import 'window_buttons.dart';

/// Custom title bar.
///
/// Left: logo + title. Right: EQ switch, preset picker and, on Windows, the
/// Windows 11 caption buttons flush in the top-right corner. Drag anywhere
/// empty to move the window; double-click to maximize.
///
/// macOS keeps its native traffic lights top-left, so content starts after them.
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.closeTooltip = 'Close'});

  /// "Close to tray" when the tray icon is available.
  final String closeTooltip;

  static final bool _isMacOS = Platform.isMacOS;
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DragToMoveArea(
        child: Row(
          children: [
            SizedBox(width: _isMacOS ? 84 : 20),
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            const Text(
              'SK EQ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
            const Spacer(),
            const SoundStatusChip(),
            const SizedBox(width: 10),
            const _EqToggle(),
            const SizedBox(width: 12),
            const PresetSelector(),
            const SizedBox(width: 6),
            const AppMenuButton(),
            if (_isMacOS)
              const SizedBox(width: 20)
            else ...[
              const SizedBox(width: 16),
              SizedBox(height: height, child: WindowButtons(closeTooltip: closeTooltip)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "EQ  ON/OFF" pill with a cyan switch.
class _EqToggle extends ConsumerWidget {
  const _EqToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(eqProvider.select((s) => s.enabled));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: enabled ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? AppColors.accent.withValues(alpha: 0.45) : AppColors.border,
        ),
        boxShadow: enabled
            ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.18), blurRadius: 14)]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('EQ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                enabled ? 'ON' : 'OFF',
                key: ValueKey(enabled),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: enabled,
              onChanged: ref.read(eqProvider.notifier).setEnabled,
            ),
          ),
        ],
      ),
    );
  }
}
