import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/update_provider.dart';
import '../../theme/app_theme.dart';

/// Manual "Check for updates" (app menu, About dialog, tray): runs the check
/// and reports the outcome in a snackbar. An available update additionally
/// shows the banner.
Future<void> checkForUpdatesManually(
    BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: Text('Checking for updates…'),
      duration: Duration(seconds: 10),
    ));

  final result = await ref.read(updateProvider.notifier).check(manual: true);
  final state = ref.read(updateProvider);
  final message = switch (result) {
    UpdateCheckResult.upToDate =>
      "You're up to date — SK EQ ${state.current ?? ''} is the latest version.",
    UpdateCheckResult.available => 'SK EQ ${state.info?.version} is available.',
    UpdateCheckResult.failed => state.error ?? "Couldn't check for updates.",
    UpdateCheckResult.notConfigured =>
      'Updates are not set up for this build yet.',
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
}

/// Slim banner under the title bar: announces a new version, then shows
/// download progress, the restart step, or an error with Retry.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final info = state.info;
    final version = info?.version.toString() ?? '';

    final (
      IconData icon,
      Color color,
      String title,
      String? subtitle,
      List<Widget> actions
    ) = switch (state.status) {
      UpdateStatus.downloading => (
          Icons.downloading_rounded,
          AppColors.accent,
          state.progress == null
              ? 'Downloading SK EQ $version…'
              : 'Downloading SK EQ $version…  ${(state.progress! * 100).round()}%',
          null,
          [
            TextButton(
                onPressed: notifier.cancelDownload,
                child: const Text('Cancel')),
          ],
        ),
      UpdateStatus.installing => (
          Icons.restart_alt_rounded,
          AppColors.accent,
          'Installing SK EQ $version…',
          'SK EQ will close and reopen by itself in a moment.',
          <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
        ),
      UpdateStatus.openedInstaller => (
          Icons.install_desktop_rounded,
          AppColors.accent,
          'Almost done — drag SK EQ into Applications',
          'Then quit this window and open the new SK EQ.',
          [
            FilledButton(onPressed: notifier.dismiss, child: const Text('OK')),
          ],
        ),
      UpdateStatus.error => (
          Icons.error_outline_rounded,
          AppColors.danger,
          "The update didn't finish",
          state.error,
          [
            TextButton(onPressed: notifier.dismiss, child: const Text('Close')),
            const SizedBox(width: 6),
            FilledButton(onPressed: notifier.retry, child: const Text('Retry')),
          ],
        ),
      _ => (
          Icons.system_update_alt_rounded,
          AppColors.accent,
          'SK EQ $version is available',
          'You have ${state.current ?? 'an older version'}. Your settings and presets are kept.',
          [
            if (info?.notes != null || info?.notesUrl != null) ...[
              TextButton(
                onPressed: () => _showWhatsNew(context, ref),
                child: const Text("What's new"),
              ),
              const SizedBox(width: 2),
            ],
            TextButton(onPressed: notifier.dismiss, child: const Text('Later')),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: notifier.downloadAndInstall,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Update now'),
            ),
          ],
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              color.withValues(alpha: 0.08), AppColors.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ...actions,
                ],
              ),
            ),
            if (state.status == UpdateStatus.downloading)
              LinearProgressIndicator(
                value: state.progress,
                minHeight: 3,
                color: AppColors.accent,
                backgroundColor: AppColors.track,
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showWhatsNew(BuildContext context, WidgetRef ref) {
    final info = ref.read(updateProvider).info;
    if (info == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text("What's new in SK EQ ${info.version}",
            style: const TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(
              info.notes ?? 'See the full release notes online.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ),
        actions: [
          if (info.notesUrl != null)
            TextButton(
              onPressed: () =>
                  ref.read(updateProvider.notifier).openReleaseNotes(),
              child: const Text('Open release page'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(updateProvider.notifier).downloadAndInstall();
            },
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }
}
