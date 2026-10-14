import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/eq_provider.dart';
import '../../providers/volume_provider.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import 'media_controls.dart';
import 'save_preset_dialog.dart';

/// Bottom bar: media buttons, master volume + mute on the left; A/B compare, Reset and
/// Save Preset on the right.
class BottomControls extends ConsumerWidget {
  const BottomControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (MediaService.isSupported) ...[
            const MediaControls(),
            const SizedBox(width: 20),
          ],
          const Expanded(child: _MasterVolume()),
          const SizedBox(width: 24),
          const AbCompareButton(),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Reset all bands and shelves to 0 dB',
            child: OutlinedButton.icon(
              onPressed: ref.read(eqProvider.notifier).reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(width: 12),
          const _SavePresetButton(),
        ],
      ),
    );
  }
}

/// A/B compare: one click flips instantly between the EQ'd sound (A) and
/// the untouched signal (B). Keyboard shortcut: B.
class AbCompareButton extends ConsumerWidget {
  const AbCompareButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(eqProvider.select((s) => s.enabled));
    final bypassed = ref.watch(eqProvider.select((s) => s.compareBypass));

    Widget segment(String text, bool active, Color color) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.45), blurRadius: 12)
                  ]
                : [],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: active
                  ? (color == AppColors.bypass
                      ? Colors.black
                      : AppColors.onAccent)
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        );

    return Tooltip(
      message: enabled
          ? 'A/B compare — A: with EQ · B: bypassed  (shortcut: B)'
          : 'Turn the EQ on to compare',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? ref.read(eqProvider.notifier).toggleCompare : null,
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: bypassed
                      ? AppColors.bypass.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.compare_arrows_rounded, size: 18),
                  const SizedBox(width: 8),
                  const Text('Compare',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                  segment('A', enabled && !bypassed, AppColors.accent),
                  const SizedBox(width: 2),
                  segment('B', enabled && bypassed, AppColors.bypass),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Save Preset lights up (filled cyan + glow + dot) when there are unsaved
/// changes, and stays quiet otherwise.
class _SavePresetButton extends ConsumerWidget {
  const _SavePresetButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirty = ref.watch(eqProvider.select((s) => s.isDirty));

    return Tooltip(
      message: dirty
          ? 'You have unsaved changes — save them as a preset (Ctrl/⌘+S)'
          : 'No unsaved changes',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: dirty
              ? [
                  BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 18)
                ]
              : [],
        ),
        child: FilledButton.icon(
          onPressed: () => saveCurrentAsPreset(context, ref),
          style: FilledButton.styleFrom(
            backgroundColor: dirty ? AppColors.accent : AppColors.surfaceHigh,
            foregroundColor:
                dirty ? AppColors.onAccent : AppColors.textSecondary,
            side: dirty ? null : BorderSide(color: AppColors.border),
          ),
          icon: Icon(
              dirty
                  ? Icons.bookmark_add_rounded
                  : Icons.bookmark_border_rounded,
              size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Save Preset'),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: dirty
                    ? Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.onAccent,
                          shape: BoxShape.circle,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterVolume extends ConsumerWidget {
  const _MasterVolume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vol = ref.watch(volumeProvider);
    final notifier = ref.read(volumeProvider.notifier);

    final IconData icon;
    if (vol.muted || vol.volume == 0) {
      icon = Icons.volume_off_rounded;
    } else if (vol.volume < 0.5) {
      icon = Icons.volume_down_rounded;
    } else {
      icon = Icons.volume_up_rounded;
    }

    // Narrow windows (media buttons take room): drop the label, keep the slider.
    return LayoutBuilder(builder: (context, constraints) {
      final showLabel = constraints.maxWidth > 330;
      return Row(
        children: [
          Tooltip(
            message: vol.muted ? 'Unmute' : 'Mute',
            child: IconButton(
              onPressed: notifier.toggleMute,
              style: IconButton.styleFrom(
                backgroundColor: vol.muted
                    ? AppColors.danger.withValues(alpha: 0.15)
                    : AppColors.surfaceHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                fixedSize: const Size(44, 44),
              ),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  color: vol.muted ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (showLabel) ...[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Master Volume',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  vol.available ? 'System output' : 'System volume unavailable',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: vol.muted ? 0.45 : 1,
                child: Slider(value: vol.volume, onChanged: notifier.setVolume),
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              vol.muted ? 'Muted' : '${(vol.volume * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: vol.muted ? AppColors.danger : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    });
  }
}
