// Unit tests for the EQ state logic. Kept free of window_manager, the tray
// and the volume plugin so they run headless with `flutter test`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_eq/models/eq_band.dart';
import 'package:pure_eq/models/preset.dart';
import 'package:pure_eq/providers/eq_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  EqNotifier notifier() => container.read(eqProvider.notifier);
  EqState state() => container.read(eqProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('starts flat, enabled and clean', () {
    expect(state().enabled, isTrue);
    expect(state().presetName, 'Flat');
    expect(state().gains, everyElement(0.0));
    expect(state().isDirty, isFalse);
  });

  test('selecting a preset loads its gains and is not dirty', () {
    notifier().selectPreset('Bass Boost');
    final bassBoost = kBuiltInPresets.firstWhere((p) => p.name == 'Bass Boost');
    expect(state().presetName, 'Bass Boost');
    expect(state().gains, bassBoost.gains);
    expect(state().isDirty, isFalse);
  });

  test('editing a band switches to Custom, marks dirty, and is remembered', () {
    notifier().setBandGain(3, 4.5);
    expect(state().presetName, Preset.customName);
    expect(state().isDirty, isTrue);
    notifier().selectPreset('Flat');
    notifier().selectPreset(Preset.customName);
    expect(state().gains[3], 4.5);
  });

  test('changing bass on a preset marks it dirty; reset cleans it', () {
    notifier().selectPreset('Rock');
    notifier().setBass(3);
    expect(state().presetName, 'Rock');
    expect(state().isDirty, isTrue);
    notifier().reset();
    expect(state().isDirty, isFalse);
  });

  test('gains are clamped to ±12 dB', () {
    notifier().setBandGain(0, 40);
    expect(state().gains[0], kMaxGain);
  });

  test('bass shelf affects low bands only', () {
    notifier().setBass(6);
    final g = state().effectiveGains;
    expect(g.first, 6);
    expect(g.last, 0);
  });

  test('dragging the curve compensates for the shelves', () {
    notifier().setBass(4); // adds 4 dB at band 0
    notifier().setBandFromCurve(0, 6); // user drags the point to +6 dB
    expect(state().gains[0], closeTo(2, 1e-9));
    expect(state().effectiveGains[0], closeTo(6, 1e-9));
  });

  test('A/B compare bypasses instantly and only while EQ is on', () {
    notifier().toggleCompare();
    expect(state().compareBypass, isTrue);
    expect(state().isProcessing, isFalse);
    notifier().toggleCompare();
    expect(state().isProcessing, isTrue);

    notifier().setEnabled(false);
    notifier().toggleCompare();
    expect(state().compareBypass, isFalse);
  });

  test('save stores bass/treble; delete falls back to Custom', () async {
    notifier().setBandGain(5, 3);
    notifier().setTreble(2);
    await notifier().savePreset('Mine');
    expect(state().presetName, 'Mine');
    expect(state().isDirty, isFalse);
    expect(state().findPreset('Mine')!.treble, 2);

    await notifier().deletePreset('Mine');
    expect(state().userPresets, isEmpty);
    expect(state().presetName, Preset.customName);
  });

  test('reserved names cannot be saved', () async {
    await notifier().savePreset('rock');
    expect(state().userPresets, isEmpty);
  });

  test('interpolated response passes through band gains', () {
    final gains = <double>[0, 2, 4, 6, 8, 6, 4, 2, 0, -2];
    for (var i = 0; i < kBandCount; i++) {
      expect(interpolateGain(gains, 31.25 * (1 << i)), closeTo(gains[i], 1e-9));
    }
  });
}
