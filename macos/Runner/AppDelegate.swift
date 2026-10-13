import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // SK EQ hides its window to the menu bar instead of closing, so the app
  // must keep running when no window is visible.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Clicking the Dock icon brings the hidden window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
