import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 托盘常驻：关窗不退出 —— the app lives in the menu bar, not in the
  /// window. Quit is the menu-bar item or ⌘Q, and a closed window is the
  /// app tucked away, not gone.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon after the window was closed brings it back —
  /// a tray-resident app with no way to reopen is a trap.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      TrayController.shared.showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
