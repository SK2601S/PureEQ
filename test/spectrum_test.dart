// The spectrum must not move when nothing is playing.

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_eq/ui/widgets/spectrum_visualizer.dart';

void run(SpectrumSimulation sim, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    sim.step(1 / 60);
  }
}

double tallest(SpectrumSimulation sim) =>
    sim.levels.reduce((a, b) => a > b ? a : b);

void main() {
  test('no live input and nothing playing: bars stay flat', () {
    final sim = SpectrumSimulation(barCount: 128)..demoPlaying = false;
    run(sim, 2);
    expect(tallest(sim), 0);
    expect(sim.isQuiet, isTrue);
  });

  test('demo animation stops when playing stops', () {
    final sim = SpectrumSimulation(barCount: 128)..demoPlaying = true;
    run(sim, 1);
    expect(tallest(sim), greaterThan(0.2));
    sim.demoPlaying = false;
    run(sim, 2);
    expect(tallest(sim), lessThan(0.01));
  });

  test('bars fall when live frames stop coming', () {
    final sim = SpectrumSimulation(barCount: 128);
    for (var i = 0; i < 30; i++) {
      sim.pushLive(List.filled(128, -20));
      sim.step(1 / 60);
    }
    expect(tallest(sim), greaterThan(0.5));
    run(sim, 2); // no more frames
    expect(tallest(sim), lessThan(0.01));
  });

  test('silent live frames: bars fall', () {
    final sim = SpectrumSimulation(barCount: 128);
    for (var i = 0; i < 30; i++) {
      sim.pushLive(List.filled(128, -20));
      sim.step(1 / 60);
    }
    for (var i = 0; i < 120; i++) {
      sim.pushLive(List.filled(128, -180));
      sim.step(1 / 60);
    }
    expect(tallest(sim), lessThan(0.01));
  });
}
