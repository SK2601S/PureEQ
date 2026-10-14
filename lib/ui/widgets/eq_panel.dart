import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/eq_band.dart';
import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';
import 'band_slider.dart';
import 'eq_curve.dart';
import 'panel.dart';
import 'spectrum_visualizer.dart';

/// Width of the left gutter holding the dB scales. The spectrum and the band
/// row both start after it, so each slider sits exactly under its band.
const double _gutter = 40;

/// The main card: spectrum + EQ curve on top, 10 band sliders underneath.
class EqPanel extends ConsumerStatefulWidget {
  const EqPanel({super.key});

  @override
  ConsumerState<EqPanel> createState() => _EqPanelState();
}

class _EqPanelState extends ConsumerState<EqPanel> {
  bool _showOutput = true;
  bool _showCurve = true;

  @override
  Widget build(BuildContext context) {
    final eq = ref.watch(eqProvider);
    final notifier = ref.read(eqProvider.notifier);
    final bands = eq.bands;

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 12),
      child: Column(
        children: [
          // --- Header: title, status badge, layer toggles. ---
          Row(
            children: [
              const SizedBox(width: _gutter + 8),
              const SectionLabel('Spectrum'),
              const SizedBox(width: 10),
              _StatusBadge(enabled: eq.enabled, bypassed: eq.compareBypass),
              const Spacer(),
              _LayerToggle(
                label: 'Output',
                selected: _showOutput,
                swatch: const _BarSwatch(),
                onTap: () => setState(() => _showOutput = !_showOutput),
              ),
              const SizedBox(width: 8),
              _LayerToggle(
                label: 'EQ curve',
                selected: _showCurve,
                swatch: const _LineSwatch(),
                onTap: () => setState(() => _showCurve = !_showCurve),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // --- Spectrum + curve, with the dB scale on the left. ---
          Expanded(
            flex: 11,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _gutter,
                  child: CustomPaint(
                    painter: DbScalePainter(
                        (db, size) => CurveGeometry(size).yForDb(db)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.inset,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: SpectrumVisualizer(
                        showOutput: _showOutput,
                        showCurve: _showCurve,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // --- 10-band equalizer. ---
          Expanded(
            flex: 7,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: _gutter, child: BandScale()),
                const SizedBox(width: 8),
                for (var i = 0; i < kBandCount; i++)
                  Expanded(
                    child: BandSlider(
                      label: bands[i].label,
                      value: bands[i].gain,
                      enabled: eq.enabled,
                      onChanged: (v) => notifier.setBandGain(i, v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "EQ OFF" / "B · BYPASS" badge next to the section title.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.enabled, required this.bypassed});

  final bool enabled;
  final bool bypassed;

  @override
  Widget build(BuildContext context) {
    final (String text, Color color)? badge = !enabled
        ? ('EQ OFF', AppColors.textMuted)
        : bypassed
            ? ('B · BYPASSED', AppColors.bypass)
            : null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: badge == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(badge.$1),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badge.$2.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badge.$2.withValues(alpha: 0.4)),
              ),
              child: Text(
                badge.$1,
                style: TextStyle(
                  color: badge.$2,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
    );
  }
}

/// Clickable legend chip that shows / hides a spectrum layer.
class _LayerToggle extends StatelessWidget {
  const _LayerToggle({
    required this.label,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: selected ? 'Hide $label' : 'Show $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: selected ? 1 : 0.45,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  swatch,
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarSwatch extends StatelessWidget {
  const _BarSwatch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.accentDeep, AppColors.accent],
        ),
      ),
    );
  }
}

class _LineSwatch extends StatelessWidget {
  const _LineSwatch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 2,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 4)
        ],
      ),
    );
  }
}
