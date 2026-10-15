import Cocoa
import FlutterMacOS
import ServiceManagement

// "Open at login" for macOS (Settings → Behavior), on channel skeq/app:
//   loginItem          → {supported, enabled, needsApproval}
//   setLoginItem(bool) → same, after the change
//   launchedAtLogin    → true when macOS opened SK EQ at login; it then
//                        stays hidden in the menu bar, like Windows' --minimized.
//
// Uses SMAppService (macOS 13+). Older versions report supported = false.

final class AppChannel {
  private let channel: FlutterMethodChannel
  private var launchedAtLogin: Bool?
  private var waiting: [FlutterResult] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "skeq/app", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    // The "open application" event tells how SK EQ was started; it is only
    // available while launching finishes.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      let event = NSAppleEventManager.shared().currentAppleEvent
      let atLogin = event?.eventID == AEEventID(kAEOpenApplication)
        && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
          == OSType(keyAELaunchedAsLogInItem)
      self.launchedAtLogin = atLogin
      self.waiting.forEach { $0(atLogin) }
      self.waiting.removeAll()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "launchedAtLogin":
      if let launchedAtLogin {
        result(launchedAtLogin)
      } else {
        waiting.append(result)  // answered when launching finishes
      }
    case "loginItem":
      result(loginItemState())
    case "setLoginItem":
      let on = call.arguments as? Bool ?? false
      var failure: String?
      if #available(macOS 13.0, *) {
        do {
          if on {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
        } catch {
          failure = "\(error)"
        }
        // Some Macs ask the user to allow it in System Settings first.
        if on, SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
      }
      var state = loginItemState()
      if let failure { state["error"] = failure }
      result(state)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loginItemState() -> [String: Any] {
    guard #available(macOS 13.0, *) else {
      return ["supported": false, "enabled": false, "needsApproval": false]
    }
    let status = SMAppService.mainApp.status
    return [
      "supported": true,
      "enabled": status == .enabled,
      "needsApproval": status == .requiresApproval,
    ]
  }
}
