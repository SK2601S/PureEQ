/// App-wide configuration.
library;

/// Where SK EQ looks for updates: a small JSON manifest (see README →
/// "Releasing an update"). With GitHub Releases the stable URL is
/// `https://github.com/OWNER/REPO/releases/latest/download/latest.json`,
/// which always points at the newest release's manifest.
///
/// Can be overridden at build time, e.g. for testing against a local server:
///   flutter build windows --dart-define=PUREEQ_UPDATE_URL=http://127.0.0.1:8765/latest.json
///
/// An empty value disables update checks (the menu then says updates aren't
/// set up yet).
const String kUpdateManifestUrl = String.fromEnvironment(
  'PUREEQ_UPDATE_URL',
  defaultValue: 'https://github.com/SK2601S/PureEQ/releases/latest/download/latest.json',
);

/// Test builds only: accept an available update automatically, exactly as if
/// "Update now" were clicked (used to test the full update flow end to end
/// without simulating mouse input). Always false in normal builds, so the
/// code behind it is compiled out.
const bool kTestAutoAcceptUpdate = bool.fromEnvironment('PUREEQ_TEST_AUTO_UPDATE');

/// How often a running SK EQ re-checks for updates (besides at startup).
const Duration kUpdateCheckInterval = Duration(hours: 6);

/// Delay before the first automatic check, so startup stays snappy.
const Duration kUpdateStartupDelay = Duration(seconds: 5);
