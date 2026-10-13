import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/update_provider.dart';
import '../../theme/app_theme.dart';
import 'app_logo.dart';
import 'update_banner.dart';

/// "⋯" button in the title bar: Check for updates · About SK EQ.
/// A small cyan dot appears on it while an update is waiting.
class AppMenuButton extends ConsumerWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final hasUpdate = update.info != null &&
        (update.status == UpdateStatus.available || update.status == UpdateStatus.error);

    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      onSelected: (value) {
        switch (value) {
          case 'update':
            if (hasUpdate) {
              // Bring the banner back (e.g. after "Later").
              ref.read(updateProvider.notifier).check(manual: true);
            } else {
              checkForUpdatesManually(context, ref);
            }
          case 'about':
            showAboutSkEq(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'update',
          enabled: !update.isBusy,
          child: Row(
            children: [
              Icon(
                hasUpdate ? Icons.system_update_alt_rounded : Icons.update_rounded,
                size: 18,
                color: hasUpdate ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(hasUpdate ? 'Update to ${update.info!.version}…' : 'Check for updates'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 12),
              Text('About SK EQ'),
            ],
          ),
        ),
      ],
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.textSecondary),
            if (hasUpdate)
              Positioned(
                top: 6,
                right: 5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// About dialog with the version and a "Check for updates" button.
Future<void> showAboutSkEq(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const AppLogo(size: 56),
            const SizedBox(height: 16),
            const Text('SK EQ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            FutureBuilder(
              future: ref.read(updateServiceProvider).currentVersion(),
              builder: (_, snap) => Text(
                snap.hasData ? 'Version ${snap.data}' : ' ',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A minimal 10-band graphic equalizer\nwith a real-time spectrum visualizer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            checkForUpdatesManually(context, ref);
          },
          icon: const Icon(Icons.update_rounded, size: 18),
          label: const Text('Check for updates'),
        ),
      ],
    ),
  );
}
