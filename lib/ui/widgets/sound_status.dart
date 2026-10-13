import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sound_provider.dart';
import '../../theme/app_theme.dart';

/// Title-bar pill: is SK EQ changing the real sound? Click for details/setup.
class SoundStatusChip extends ConsumerWidget {
  const SoundStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundProvider);
    final (String label, Color color, IconData icon) = switch (s.status) {
      SoundStatus.live => ('Live', AppColors.positive, Icons.graphic_eq_rounded),
      SoundStatus.checking => ('Checking…', AppColors.textMuted, Icons.hourglass_empty_rounded),
      SoundStatus.otherInControl => (
          '${s.otherApps.isEmpty ? 'Other app' : frontEndName(s.otherApps.first)} in control',
          AppColors.bypass,
          Icons.swap_horiz_rounded,
        ),
      SoundStatus.error => ('Sound error', AppColors.danger, Icons.error_outline_rounded),
      _ => ('Preview only', AppColors.bypass, Icons.volume_off_rounded),
    };
    final tooltip = s.status == SoundStatus.live
        ? 'Changing the real sound on: ${s.liveDevices.map((d) => d.name).join(', ')}'
        : 'The EQ is not changing the real sound — click to set up';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showSoundDialog(context),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Details and setup: which devices are processed, how to enable more, and
/// who is in control (SK EQ vs. e.g. Peace).
Future<void> showSoundDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SoundDialog(),
  );
}

class _SoundDialog extends ConsumerWidget {
  const _SoundDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundProvider);
    final n = ref.read(soundProvider.notifier);

    const muted = TextStyle(color: AppColors.textSecondary, height: 1.45);
    final children = <Widget>[];
    final actions = <Widget>[];

    void step(String text) => children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(text, style: muted),
        ));

    switch (s.status) {
      case SoundStatus.checking:
        children.add(const Text('Checking your audio setup…', style: muted));
      case SoundStatus.unsupported:
        children.add(const Text(
          'On this system SK EQ shows the equalizer but cannot change the system sound yet.',
          style: muted,
        ));
      case SoundStatus.notInstalled:
        children.add(const Text(
          'To change the real sound, SK EQ uses Equalizer APO — a free, open-source audio driver for Windows.',
          style: muted,
        ));
        step('1. Download and install Equalizer APO.');
        step('2. When it asks which devices to use, tick your playback device (for example your headphones).');
        step('3. Restart your PC, then open SK EQ.');
        actions.add(FilledButton(onPressed: n.openDownloadPage, child: const Text('Get Equalizer APO')));
      case SoundStatus.otherInControl:
        final other = s.otherApps.isEmpty ? 'Another app' : frontEndName(s.otherApps.first);
        children.add(Text(
          '$other is controlling Equalizer APO right now, so SK EQ does not change the sound. '
          'Using both at once would stack two equalizers.',
          style: muted,
        ));
        step('Switching keeps $other\'s settings — you can give control back any time here.');
        actions.add(FilledButton(onPressed: n.takeControl, child: const Text('Use SK EQ instead')));
      case SoundStatus.live:
      case SoundStatus.notOnDevice:
      case SoundStatus.error:
        if (s.status == SoundStatus.error) {
          children.add(Text("Couldn't update Equalizer APO: ${s.error}",
              style: const TextStyle(color: AppColors.danger)));
        } else if (s.status == SoundStatus.notOnDevice) {
          children.add(const Text(
            'SK EQ is connected to Equalizer APO, but Equalizer APO is not enabled for any of your playback devices yet.',
            style: muted,
          ));
        } else {
          children.add(const Text('SK EQ is changing the real sound.', style: muted));
        }
        if (s.devices.isNotEmpty) {
          children.add(const SizedBox(height: 12));
          for (final d in s.devices) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    d.apoEnabled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: d.apoEnabled ? AppColors.positive : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(d.name)),
                  Text(
                    d.apoEnabled ? 'Live' : 'Not enabled',
                    style: TextStyle(
                      color: d.apoEnabled ? AppColors.positive : AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ));
          }
        }
        if (s.devices.any((d) => !d.apoEnabled)) {
          children.add(const SizedBox(height: 10));
          step('To enable a device: choose devices, tick it, click OK, then restart your PC.');
          actions.add(OutlinedButton(
            onPressed: n.openDeviceSelector,
            child: const Text('Choose devices'),
          ));
        }
        if (s.switchedOffApps.isNotEmpty) {
          final other = frontEndName(s.switchedOffApps.first);
          actions.add(TextButton(
            onPressed: n.giveControlBack,
            child: Text('Give control back to $other'),
          ));
        }
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text('Sound output', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
      actions: [
        ...actions,
        TextButton(onPressed: n.refresh, child: const Text('Check again')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
