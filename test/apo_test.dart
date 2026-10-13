// Tests for the Equalizer APO config text handling (no files touched).

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_eq/services/apo_service.dart';

void main() {
  const peaceConfig = 'Include: peace.txt\r\n';

  group('connect / disconnect', () {
    test('takes over from Peace and can give control back exactly', () {
      final connected = ApoConfig.connect(peaceConfig);
      expect(ApoConfig.otherActiveIncludes(connected), isEmpty);
      expect(connected, contains('Include: sk-eq.txt'));
      expect(ApoConfig.switchedOffIncludes(connected), ['peace.txt']);

      final restored = ApoConfig.disconnect(connected);
      expect(restored, peaceConfig);
      expect(ApoConfig.otherActiveIncludes(restored), ['peace.txt']);
    });

    test('connecting twice changes nothing', () {
      final once = ApoConfig.connect(peaceConfig);
      expect(ApoConfig.connect(once), once);
    });

    test('keeps unrelated lines (filters, comments) untouched', () {
      const config = '# my notes\r\nPreamp: -3 dB\r\nInclude: peace.txt\r\n';
      final connected = ApoConfig.connect(config);
      expect(connected, startsWith('# my notes\r\nPreamp: -3 dB\r\n'));
      expect(ApoConfig.disconnect(connected), config);
    });

    test('a config Peace re-enabled itself is taken over again', () {
      final connected = ApoConfig.connect(peaceConfig);
      final peaceAgain = '${connected}Include: peace.txt\r\n';
      expect(ApoConfig.otherActiveIncludes(ApoConfig.connect(peaceAgain)), isEmpty);
    });
  });

  group('render', () {
    test('flat file when bypassed (EQ off / A/B "B")', () {
      final text = ApoConfig.render(List.filled(10, 6.0), processing: false);
      expect(text, contains('Preamp: 0 dB'));
      expect(text, isNot(contains('GraphicEQ')));
    });

    test('curve with headroom equal to the largest boost', () {
      final gains = <double>[6, 4, 2, 0, 0, 0, 0, -3, -3, 0];
      final text = ApoConfig.render(gains, processing: true);
      expect(text, contains('Preamp: -6.0 dB'));
      final eq = RegExp(r'GraphicEQ: (.*)').firstMatch(text)![1]!;
      final points = eq.split('; ');
      expect(points.length, ApoConfig.frequencies.length);
      expect(points.first, '20 6.0'); // below the first band: same as 31 Hz
      expect(points, contains('1000 0.0'));
      expect(points, contains('31.5 6.0'));
    });
  });
}
