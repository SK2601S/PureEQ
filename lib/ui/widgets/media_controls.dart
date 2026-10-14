import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/media_provider.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';

/// ⏮ ⏯ ⏭ ⏹ — controls whatever app is playing music (Windows).
class MediaControls extends ConsumerWidget {
  const MediaControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!MediaService.isSupported) return const SizedBox.shrink();
    final media = ref.read(mediaServiceProvider);
    final playing = ref.watch(audioPlayingProvider);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MediaButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Previous',
              onTap: media.previous),
          _MediaButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing ? 'Pause' : 'Play',
            onTap: media.playPause,
            primary: true,
          ),
          _MediaButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Next',
              onTap: media.next),
          // Native side pauses (not a real stop): many players end their
          // session on Stop, after which Play can no longer resume.
          _MediaButton(
              icon: Icons.stop_rounded, tooltip: 'Stop', onTap: media.stop),
        ],
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: primary ? 40 : 34,
          height: 36,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: primary ? 26 : 22,
                color: primary ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
