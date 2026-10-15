import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/settings_provider.dart';
import '../../providers/sound_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/startup_service.dart';
import '../../theme/app_theme.dart';
import 'sound_status.dart';
import 'update_banner.dart';

/// Settings: appearance, spectrum, behavior, sound, updates, about.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
      context: context, builder: (_) => const _SettingsDialog());
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final sound = ref.watch(soundProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.settings_rounded, color: AppColors.accent),
                  const SizedBox(width: 10),
                  const Text('Settings',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Appearance -------------------------------------------
                    const _Section('Appearance'),
                    const _Label('Theme'),
                    SegmentedButton<ThemeChoice>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: ThemeChoice.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_rounded)),
                        ButtonSegment(
                            value: ThemeChoice.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_rounded)),
                        ButtonSegment(
                            value: ThemeChoice.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_rounded)),
                      ],
                      selected: {s.theme},
                      onSelectionChanged: (v) => n.setTheme(v.first),
                    ),
                    const SizedBox(height: 16),
                    const _Label('Accent color'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final a in AccentColor.values)
                          _Swatch(
                              accent: a,
                              selected: a == s.accent,
                              onTap: () => n.setAccent(a)),
                      ],
                    ),

                    // --- Spectrum ---------------------------------------------
                    const _Section('Spectrum'),
                    const _Label('Style'),
                    SegmentedButton<SpectrumStyle>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: SpectrumStyle.bars,
                            label: Text('Bars'),
                            icon: Icon(Icons.bar_chart_rounded)),
                        ButtonSegment(
                            value: SpectrumStyle.wave,
                            label: Text('Wave'),
                            icon: Icon(Icons.show_chart_rounded)),
                        ButtonSegment(
                            value: SpectrumStyle.mirror,
                            label: Text('Mirror'),
                            icon: Icon(Icons.graphic_eq_rounded)),
                        ButtonSegment(
                            value: SpectrumStyle.led,
                            label: Text('LED'),
                            icon: Icon(Icons.view_week_rounded)),
                      ],
                      selected: {s.spectrumStyle},
                      onSelectionChanged: (v) => n.setSpectrumStyle(v.first),
                    ),
                    const SizedBox(height: 14),
                    const _Label('Bar width'),
                    SegmentedButton<BarDensity>(
                      showSelectedIcon: false,
                      segments: [
                        for (final d in BarDensity.values)
                          ButtonSegment(value: d, label: Text(d.label)),
                      ],
                      selected: {s.barDensity},
                      onSelectionChanged: (v) => n.setBarDensity(v.first),
                    ),
                    const SizedBox(height: 6),
                    _Switch(
                      title: 'Peak dots',
                      subtitle:
                          'Small markers that hold the loudest level for a moment.',
                      value: s.showPeaks,
                      onChanged: n.setShowPeaks,
                    ),
                    const SizedBox(height: 8),
                    const _Label('Motion'),
                    SegmentedButton<SpectrumMotion>(
                      showSelectedIcon: false,
                      segments: [
                        for (final m in SpectrumMotion.values)
                          ButtonSegment(value: m, label: Text(m.label)),
                      ],
                      selected: {s.motion},
                      onSelectionChanged: (v) => n.setMotion(v.first),
                    ),
                    const SizedBox(height: 6),
                    const _Hint(
                        'Snappy reacts instantly; Silky glides and floats down slowly.'),
                    const SizedBox(height: 6),
                    _Switch(
                      title: 'Smooth bars',
                      subtitle: 'Blend neighbouring bars into a softer shape.',
                      value: s.smoothBars,
                      onChanged: n.setSmoothBars,
                    ),
                    const SizedBox(height: 8),
                    const _Label('Quality'),
                    SegmentedButton<SpectrumQuality>(
                      showSelectedIcon: false,
                      segments: [
                        for (final q in SpectrumQuality.values)
                          ButtonSegment(value: q, label: Text(q.label)),
                      ],
                      selected: {s.spectrumQuality},
                      onSelectionChanged: (v) => n.setSpectrumQuality(v.first),
                    ),
                    const SizedBox(height: 6),
                    const _Hint(
                        'Smooth looks best; Battery saver uses the least CPU.'),

                    // --- Behavior ---------------------------------------------
                    const _Section('Behavior'),
                    if (StartupService.isSupported)
                      _Switch(
                        title: Platform.isMacOS
                            ? 'Open at login'
                            : 'Start with Windows',
                        subtitle: Platform.isMacOS
                            ? 'Opens quietly in the menu bar when you log in, so the EQ keeps working.'
                            : 'Opens quietly in the tray when you sign in.',
                        value: s.startWithWindows,
                        onChanged: n.setStartWithWindows,
                      ),
                    _Switch(
                      title: 'Close button hides to tray',
                      subtitle: 'Off: the close button quits SK EQ.',
                      value: s.closeToTray,
                      onChanged: n.setCloseToTray,
                    ),

                    // --- Sound ------------------------------------------------
                    const _Section('Sound'),
                    _Row(
                      title: 'Real sound',
                      subtitle: switch (sound.status) {
                        SoundStatus.live =>
                          'Live on ${sound.liveDevices.map((d) => d.name).join(', ')}',
                        SoundStatus.unsupported => Platform.isMacOS
                            ? 'Needs macOS 14.2 or later'
                            : 'Preview only on this system',
                        SoundStatus.needsPermission =>
                          'Needs permission — open for details',
                        SoundStatus.off => 'Turned off',
                        SoundStatus.notInstalled =>
                          'Needs Equalizer APO (free)',
                        SoundStatus.otherInControl =>
                          'Another app is in control',
                        SoundStatus.notOnDevice =>
                          'Not enabled for your devices yet',
                        SoundStatus.checking => 'Checking…',
                        SoundStatus.error => 'Problem — open for details',
                      },
                      action: OutlinedButton(
                        onPressed: () => showSoundDialog(context),
                        child: const Text('Open'),
                      ),
                    ),

                    // --- Updates ----------------------------------------------
                    const _Section('Updates'),
                    _Row(
                      title: 'Version',
                      subtitle: null,
                      trailingText: FutureBuilder(
                        future:
                            ref.read(updateServiceProvider).currentVersion(),
                        builder: (_, snap) => Text(
                          snap.hasData ? '${snap.data}' : '…',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      action: FilledButton(
                        onPressed: () => checkForUpdatesManually(context, ref),
                        child: const Text('Check now'),
                      ),
                    ),
                    _Switch(
                      title: 'Check for updates automatically',
                      subtitle: 'At start-up and every few hours.',
                      value: s.autoUpdate,
                      onChanged: n.setAutoUpdate,
                    ),

                    // --- About ------------------------------------------------
                    const _Section('About'),
                    _Row(
                      title: 'SK EQ on GitHub',
                      subtitle: 'Release notes and downloads',
                      action: TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(
                              'https://github.com/SK2601S/PureEQ/releases'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                    _Row(
                      title: 'Reset settings',
                      subtitle:
                          'Back to defaults. Your EQ and presets are kept.',
                      action: TextButton(
                        onPressed: n.reset,
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger),
                        child: const Text('Reset'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: AppColors.textMuted, fontSize: 12));
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.accent, required this.selected, required this.onTap});

  final AccentColor accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: accent.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [accent.main, accent.deep]),
            border: Border.all(
                color: selected ? AppColors.textPrimary : Colors.transparent,
                width: 2.5),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: accent.main.withValues(alpha: 0.5),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Row(
      title: title,
      subtitle: subtitle,
      action: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.title,
      required this.subtitle,
      this.action,
      this.trailingText});

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? trailingText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (trailingText != null) ...[
            trailingText!,
            const SizedBox(width: 12)
          ],
          if (action != null) action!,
        ],
      ),
    );
  }
}
