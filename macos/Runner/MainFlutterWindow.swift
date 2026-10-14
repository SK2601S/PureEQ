import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Real sound + live spectrum (macOS 14.2+); see SystemAudioEQ.swift.
  private var systemAudio: SystemAudioEQ?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    systemAudio = SystemAudioEQ(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
