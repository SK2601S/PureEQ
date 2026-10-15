import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  /// Real sound + live spectrum (macOS 14.2+); see SystemAudioEQ.swift.
  private var systemAudio: SystemAudioEQ?
  /// Open at login; see AppChannel.swift.
  private var appChannel: AppChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    systemAudio = SystemAudioEQ(messenger: flutterViewController.engine.binaryMessenger)
    appChannel = AppChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Start hidden; Dart shows the window (unless opened at login, when SK EQ
  // stays in the menu bar).
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
