// Tests for the in-app updater, using a fake HTTP client (no network).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_eq/providers/update_provider.dart';
import 'package:pure_eq/services/update_service.dart';

const _manifestUrl = 'https://updates.example/latest.json';
final _installer = utf8.encode('fake installer bytes');

Map<String, dynamic> _manifest(String version, {String? sha}) => {
      'version': version,
      'notes': 'Faster spectrum.',
      'notesUrl': 'https://updates.example/notes',
      UpdateService.platformKey!: {
        'url': 'https://updates.example/PureEQ-Setup-$version.exe',
        'sha256': sha ?? sha256.convert(_installer).toString(),
      },
    };

MockClient _server(Map<String, dynamic>? manifest, {int status = 200}) => MockClient((req) async {
      if (req.url.path.endsWith('latest.json')) {
        return manifest == null
            ? http.Response('not found', 404)
            : http.Response(jsonEncode(manifest), status);
      }
      return http.Response.bytes(_installer, 200);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'PureEQ',
      packageName: 'pure_eq',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('AppVersion', () {
    test('parses and compares', () {
      expect(AppVersion.tryParse('v1.2.3-beta+7'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('2'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('nope'), isNull);
      expect(const AppVersion(1, 10, 0) > const AppVersion(1, 9, 9), isTrue);
      expect(const AppVersion(1, 0, 0) > const AppVersion(1, 0, 0), isFalse);
    });
  });

  group('UpdateService', () {
    test('rejects insecure addresses except localhost', () {
      expect(() => UpdateService.checkedUri('http://evil.example/x.json'),
          throwsA(isA<UpdateException>()));
      expect(UpdateService.checkedUri('http://127.0.0.1:8765/latest.json').port, 8765);
    });

    test('reads the manifest entry for this platform', () async {
      final service = UpdateService(manifestUrl: _manifestUrl, client: _server(_manifest('1.1.0')));
      final info = await service.fetchLatest();
      expect(info.version, const AppVersion(1, 1, 0));
      expect(info.downloadUrl.path, endsWith('PureEQ-Setup-1.1.0.exe'));
      expect(info.notes, 'Faster spectrum.');
    });

    test('no release yet → friendly error', () async {
      final service = UpdateService(manifestUrl: _manifestUrl, client: _server(null));
      expect(service.fetchLatest(),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('No release'))));
    });

    test('download verifies the checksum', () async {
      final good = UpdateService(manifestUrl: _manifestUrl, client: _server(_manifest('1.1.0')));
      final progress = <double?>[];
      final file = await good.download(await good.fetchLatest(), onProgress: progress.add);
      expect(await file.readAsBytes(), _installer);
      expect(progress.last, 1.0);
      await file.delete();

      final bad = UpdateService(
        manifestUrl: _manifestUrl,
        client: _server(_manifest('1.1.0', sha: 'deadbeef')),
      );
      expect(bad.download(await bad.fetchLatest()), throwsA(isA<UpdateException>()));
    });
  });

  group('UpdateNotifier', () {
    ProviderContainer containerWith(MockClient client) => ProviderContainer(overrides: [
          updateServiceProvider
              .overrideWithValue(UpdateService(manifestUrl: _manifestUrl, client: client)),
        ]);

    test('newer version → banner shown', () async {
      final c = containerWith(_server(_manifest('1.1.0')));
      addTearDown(c.dispose);
      final result = await c.read(updateProvider.notifier).check();
      expect(result, UpdateCheckResult.available);
      expect(c.read(updateProvider).bannerVisible, isTrue);
      expect(c.read(updateProvider).current, const AppVersion(1, 0, 0));
    });

    test('same version → up to date, no banner', () async {
      final c = containerWith(_server(_manifest('1.0.0')));
      addTearDown(c.dispose);
      expect(await c.read(updateProvider.notifier).check(), UpdateCheckResult.upToDate);
      expect(c.read(updateProvider).bannerVisible, isFalse);
    });

    test('"Later" hides it from automatic checks but not manual ones', () async {
      final c = containerWith(_server(_manifest('1.1.0')));
      addTearDown(c.dispose);
      final n = c.read(updateProvider.notifier);
      await n.check();
      n.dismiss();
      await n.check();
      expect(c.read(updateProvider).bannerVisible, isFalse);
      await n.check(manual: true);
      expect(c.read(updateProvider).bannerVisible, isTrue);
    });

    test('server error → failed, quietly', () async {
      final c = containerWith(_server({}, status: 500));
      addTearDown(c.dispose);
      expect(await c.read(updateProvider.notifier).check(), UpdateCheckResult.failed);
      expect(c.read(updateProvider).bannerVisible, isFalse);
      expect(c.read(updateProvider).error, contains('500'));
    });
  });

  tearDownAll(() async {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}pureeq-update');
    if (await dir.exists()) await dir.delete(recursive: true);
  });
}
