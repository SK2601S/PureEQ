import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService(manifestUrl: kUpdateManifestUrl);
  ref.onDispose(service.dispose);
  return service;
});

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// Windows: installer launched, the app is about to quit.
  installing,

  /// macOS: the .dmg was opened; the user finishes by dragging the app.
  openedInstaller,
  error,
}

/// Result of a manual "Check for updates", for the snackbar.
enum UpdateCheckResult { upToDate, available, failed, notConfigured }

@immutable
class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.current,
    this.info,
    this.progress,
    this.error,
    this.bannerVisible = false,
  });

  final UpdateStatus status;

  /// The running version (known after the first check).
  final AppVersion? current;

  /// The newer release, when one is available.
  final UpdateInfo? info;

  /// Download progress 0..1 (null = unknown size).
  final double? progress;

  final String? error;

  /// Whether the update banner is shown at the top of the window.
  final bool bannerVisible;

  bool get isBusy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.installing;

  UpdateState copyWith({
    UpdateStatus? status,
    AppVersion? current,
    UpdateInfo? info,
    double? progress,
    bool clearProgress = false,
    String? error,
    bool clearError = false,
    bool? bannerVisible,
  }) {
    return UpdateState(
      status: status ?? this.status,
      current: current ?? this.current,
      info: info ?? this.info,
      progress: clearProgress ? null : progress ?? this.progress,
      error: clearError ? null : error ?? this.error,
      bannerVisible: bannerVisible ?? this.bannerVisible,
    );
  }
}

class UpdateNotifier extends Notifier<UpdateState> {
  Timer? _periodic;
  bool _cancelRequested = false;

  /// "Later" hides the banner for that version until the app restarts.
  AppVersion? _dismissedVersion;

  /// Set by the app shell: closes PureEQ so the installer can replace it.
  Future<void> Function()? quitForInstall;

  UpdateService get _service => ref.read(updateServiceProvider);

  @override
  UpdateState build() {
    ref.onDispose(() => _periodic?.cancel());
    return const UpdateState();
  }

  bool get isConfigured => _service.isConfigured;

  /// Silent check shortly after startup, then every [kUpdateCheckInterval].
  void startAutomaticChecks() {
    if (!_service.isConfigured) return;
    Timer(kUpdateStartupDelay, check);
    _periodic ??= Timer.periodic(kUpdateCheckInterval, (_) => check());
  }

  /// Checks for a newer version. Automatic checks stay silent on failure;
  /// [manual] checks always show the banner when an update exists, even one
  /// the user postponed with "Later".
  Future<UpdateCheckResult> check({bool manual = false}) async {
    if (!_service.isConfigured) return UpdateCheckResult.notConfigured;
    if (state.isBusy) {
      return state.status == UpdateStatus.checking
          ? UpdateCheckResult.upToDate
          : UpdateCheckResult.available;
    }

    final previous = state;
    state = state.copyWith(status: UpdateStatus.checking, clearError: true);
    try {
      final current = state.current ?? await _service.currentVersion();
      final latest = await _service.fetchLatest();
      if (latest.version > current) {
        final show = manual || latest.version != _dismissedVersion;
        state = state.copyWith(
          status: UpdateStatus.available,
          current: current,
          info: latest,
          bannerVisible: show || previous.bannerVisible,
        );
        if (kTestAutoAcceptUpdate) unawaited(downloadAndInstall());
        return UpdateCheckResult.available;
      }
      state = state.copyWith(status: UpdateStatus.upToDate, current: current, bannerVisible: false);
      return UpdateCheckResult.upToDate;
    } on UpdateException catch (e) {
      // Keep a previously found update visible; otherwise report the error.
      state = previous.status == UpdateStatus.available
          ? previous
          : state.copyWith(status: UpdateStatus.error, error: e.message);
      return UpdateCheckResult.failed;
    }
  }

  /// "Update now": download (with progress), verify, then install.
  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null || state.isBusy) return;

    _cancelRequested = false;
    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
      clearError: true,
      bannerVisible: true,
    );
    try {
      final file = await _service.download(
        info,
        onProgress: (p) => state = state.copyWith(progress: p, clearProgress: p == null),
        isCancelled: () => _cancelRequested,
      );
      await _service.install(file);
      if (Platform.isWindows) {
        state = state.copyWith(status: UpdateStatus.installing);
        // Let "Installing…" be seen briefly, then quit: the installer waits
        // for this process to exit (/WAITPID) and reopens PureEQ when done.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await quitForInstall?.call();
      } else {
        state = state.copyWith(status: UpdateStatus.openedInstaller);
      }
    } on UpdateCancelled {
      state = state.copyWith(status: UpdateStatus.available, clearProgress: true);
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.error, error: e.message, clearProgress: true);
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        error: "The update couldn't be installed: $e",
        clearProgress: true,
      );
    }
  }

  void cancelDownload() => _cancelRequested = true;

  /// "Later" / close button.
  void dismiss() {
    _dismissedVersion = state.info?.version;
    state = state.copyWith(bannerVisible: false);
  }

  /// "Retry" after an error: re-download if we know the release, else re-check.
  Future<void> retry() async {
    if (state.info != null) {
      state = state.copyWith(status: UpdateStatus.available, clearError: true);
      await downloadAndInstall();
    } else {
      await check(manual: true);
    }
  }

  Future<void> openReleaseNotes() async {
    final url = state.info?.notesUrl;
    if (url != null) await _service.openLink(url);
  }
}
