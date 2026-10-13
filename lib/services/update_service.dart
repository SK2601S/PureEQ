import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// A `major.minor.patch` version. Ignores a leading "v", pre-release and
/// build suffixes ("v1.2.3-beta+4" → 1.2.3).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static AppVersion? tryParse(String text) {
    final m = RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2] ?? '0'), int.parse(m[3] ?? '0'));
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// One available release, for the current platform.
///
/// Parsed from the update manifest (`latest.json`):
/// ```json
/// {
///   "version": "1.1.0",
///   "notes": "What's new…",
///   "notesUrl": "https://github.com/…/releases/tag/v1.1.0",
///   "windows": { "url": "https://…/PureEQ-Setup-1.1.0.exe", "sha256": "…" },
///   "macos":   { "url": "https://…/PureEQ-1.1.0.dmg",       "sha256": "…" }
/// }
/// ```
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.sha256,
    this.notes,
    this.notesUrl,
  });

  final AppVersion version;
  final Uri downloadUrl;

  /// Expected SHA-256 of the download (lowercase hex). Checked if present.
  final String? sha256;
  final String? notes;
  final Uri? notesUrl;

  /// Reads the entry for [platform] ("windows" / "macos").
  factory UpdateInfo.fromManifest(Map<String, dynamic> json, {required String platform}) {
    final version = AppVersion.tryParse(json['version'] as String? ?? '');
    if (version == null) throw const UpdateException('The update information is invalid.');
    final entry = json[platform];
    if (entry is! Map || entry['url'] is! String) {
      throw const UpdateException('No update is published for this platform yet.');
    }
    final notes = (json['notes'] as String?)?.trim();
    final notesUrl = json['notesUrl'] as String?;
    return UpdateInfo(
      version: version,
      downloadUrl: UpdateService.checkedUri(entry['url'] as String),
      sha256: (entry['sha256'] as String?)?.toLowerCase(),
      notes: notes == null || notes.isEmpty ? null : notes,
      notesUrl: notesUrl == null ? null : UpdateService.checkedUri(notesUrl),
    );
  }
}

/// A user-presentable update failure.
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the user cancels a download.
class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Checks for, downloads and launches PureEQ updates.
class UpdateService {
  UpdateService({required String manifestUrl, http.Client? client})
      : _manifestUrl = manifestUrl.isEmpty ? null : checkedUri(manifestUrl),
        _client = client ?? http.Client();

  final Uri? _manifestUrl;
  final http.Client _client;

  /// False when no update URL is configured (see config.dart).
  bool get isConfigured => _manifestUrl != null;

  /// "windows" / "macos" — the manifest key for this machine.
  static String? get platformKey => Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
          ? 'macos'
          : null;

  /// Only HTTPS is accepted, except plain HTTP to this machine (for testing
  /// against a local server).
  static Uri checkedUri(String url) {
    final uri = Uri.tryParse(url);
    final local = uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
    if (uri == null || !(uri.scheme == 'https' || (uri.scheme == 'http' && local))) {
      throw UpdateException('Refusing insecure update address: $url');
    }
    return uri;
  }

  Future<AppVersion> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.tryParse(info.version) ?? const AppVersion(0, 0, 0);
  }

  /// Fetches the newest published release for this platform.
  Future<UpdateInfo> fetchLatest() async {
    final url = _manifestUrl;
    final platform = platformKey;
    if (url == null) throw const UpdateException('Updates are not set up for this build.');
    if (platform == null) throw const UpdateException('Updates are not supported on this system.');

    final http.Response res;
    try {
      res = await _client
          .get(url, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const UpdateException('The update server did not respond. Check your internet connection.');
    } on Exception {
      throw const UpdateException("Couldn't reach the update server. Check your internet connection.");
    }
    if (res.statusCode == 404) {
      throw const UpdateException('No release has been published yet.');
    }
    if (res.statusCode != 200) {
      throw UpdateException('The update server returned an error (${res.statusCode}).');
    }
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return UpdateInfo.fromManifest(json, platform: platform);
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw const UpdateException('The update information is invalid.');
    }
  }

  /// Downloads the installer to a temp folder, reporting progress (0..1, or
  /// null when the size is unknown), and verifies its SHA-256.
  Future<File> download(
    UpdateInfo info, {
    void Function(double? progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}pureeq-update');
    await dir.create(recursive: true);
    final name = info.downloadUrl.pathSegments.isEmpty
        ? 'PureEQ-update'
        : info.downloadUrl.pathSegments.last;
    final file = File('${dir.path}${Platform.pathSeparator}$name');

    final http.StreamedResponse res;
    try {
      res = await _client.send(http.Request('GET', info.downloadUrl));
    } on Exception {
      throw const UpdateException("Couldn't download the update. Check your internet connection.");
    }
    if (res.statusCode != 200) {
      throw UpdateException('Download failed (${res.statusCode}).');
    }

    final total = res.contentLength;
    var received = 0;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final out = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        if (isCancelled?.call() ?? false) throw const UpdateCancelled();
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : received / total);
      }
    } on Exception catch (e) {
      await out.close();
      await file.delete().catchError((_) => file);
      if (e is UpdateCancelled) rethrow;
      throw const UpdateException('The download was interrupted. Please try again.');
    }
    await out.close();
    hasher.close();

    final expected = info.sha256;
    if (expected != null && digest.value.toString() != expected) {
      await file.delete().catchError((_) => file);
      throw const UpdateException('The downloaded file is damaged (checksum mismatch). Please try again.');
    }
    return file;
  }

  /// Starts installing [file].
  ///
  /// * Windows: runs the Inno Setup installer silently. It shows a small
  ///   progress window, replaces the app, and restarts PureEQ (see the
  ///   `/UPDATE=1` handling in installer/pureeq.iss). The caller must quit
  ///   the app right after this returns.
  ///
  ///   `/WAITPID=<pid>` makes the installer wait until this process has
  ///   exited before it touches any file. Without it the two would race:
  ///   the installer would ask PureEQ to close while its files are still in
  ///   use, PureEQ would treat that like the close button (hide to tray),
  ///   and the silent install would give up.
  ///
  ///   (The installer is a windowed program, so it can be started
  ///   "detached"; console helpers such as PowerShell cannot — Dart starts
  ///   detached processes without a console and they exit immediately.)
  /// * macOS: opens the .dmg; the user drags PureEQ into Applications.
  Future<void> install(File file) async {
    if (Platform.isWindows) {
      // Match the existing install mode so the update replaces it in place
      // (an all-users install in Program Files needs admin → UAC prompt).
      final programFiles = (Platform.environment['ProgramFiles'] ?? r'C:\Program Files').toLowerCase();
      final allUsers = Platform.resolvedExecutable.toLowerCase().startsWith(programFiles);
      await Process.start(
        file.path,
        [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/UPDATE=1',
          '/WAITPID=$pid',
          allUsers ? '/ALLUSERS' : '/CURRENTUSER',
        ],
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isMacOS) {
      if (!await launchUrl(Uri.file(file.path))) {
        throw const UpdateException("Couldn't open the downloaded update.");
      }
    } else {
      throw const UpdateException('Updates are not supported on this system.');
    }
  }

  /// Opens a link (e.g. release notes) in the default browser.
  Future<void> openLink(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  void dispose() => _client.close();
}

/// Receives the final digest of a chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
