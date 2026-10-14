import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/preset.dart';
import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';

/// Pill-shaped dropdown: Custom, the built-in presets, then the user's saved
/// presets (each with a delete button). A dot after the name marks unsaved
/// changes.
class PresetSelector extends ConsumerWidget {
  const PresetSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(eqProvider);
    final notifier = ref.read(eqProvider.notifier);
    final dirty = eq.isDirty;

    return PopupMenuButton<String>(
      tooltip: 'Presets',
      initialValue: eq.presetName,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 230),
      onSelected: notifier.selectPreset,
      itemBuilder: (menuContext) => [
        _presetItem(Preset.customName,
            selected: eq.presetName == Preset.customName),
        const PopupMenuDivider(),
        for (final p in kBuiltInPresets)
          _presetItem(p.name, selected: p.name == eq.presetName),
        if (eq.userPresets.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(
              'MY PRESETS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final p in eq.userPresets)
            _presetItem(
              p.name,
              selected: p.name == eq.presetName,
              trailing: IconButton(
                tooltip: 'Delete preset',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  notifier.deletePreset(p.name);
                },
              ),
            ),
        ],
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, maxWidth: 160),
              // Cross-fade the name when the preset changes.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  eq.presetName,
                  key: ValueKey(eq.presetName),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: dirty ? 1 : 0,
              child: Tooltip(
                message: 'Unsaved changes',
                child: Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 4, right: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.7),
                          blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _presetItem(
    String name, {
    required bool selected,
    Widget? trailing,
  }) {
    return PopupMenuItem<String>(
      value: name,
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: selected
                ? Icon(Icons.check_rounded, size: 16, color: AppColors.accent)
                : null,
          ),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
