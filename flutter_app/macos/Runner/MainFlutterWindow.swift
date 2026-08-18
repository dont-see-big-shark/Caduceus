import Cocoa
import FlutterMacOS

/// Owns the menu-bar item for the life of the app.
///
/// A status item is a global object, so it must outlive the window that
/// created it: closing the window (tray-resident behaviour) must not drop the
/// tray — it has to stay clickable while the app runs in the background.
final class TrayController: NSObject {
  static let shared = TrayController()

  private var statusItem: NSStatusItem?
  private var channel: FlutterMethodChannel?

  /// Creates the tray and the channel. Idempotent, so a hot restart or a
  /// second window does not stack another icon.
  func install(messenger: FlutterBinaryMessenger) {
    if statusItem != nil { return }

    channel = FlutterMethodChannel(name: "caduceus/macos", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "trayStatus" {
        result(self?.statusItem != nil)
      }
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = Self.trayImage()
      button.image?.isTemplate = true
    }
    let menu = NSMenu()
    // Targets are set explicitly: with `autoenablesItems` (the default) a
    // nil target resolves against the responder chain / NSApp, which cannot
    // perform these selectors, so the items would render disabled and the
    // tray would be unclickable while the app sits in the background.
    let showItem = NSMenuItem(
      title: "显示 Caduceus",
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)

    // The macOS menu-bar shortcuts — ⌘N / ⌘R / ⌘⇧R — act on the active agent.
    // (The rest — ⌘E, ⌘↑/⌘↓, ⌘1–5, ⌘⇧T/⌘⇧P/⌘⇧S — live in Flutter's
    // CallbackShortcuts, since direction/number keys are not menu idioms.)
    let newSessionItem = NSMenuItem(
      title: "新建会话",
      action: #selector(sendShortcut(_:)),
      keyEquivalent: "n"
    )
    newSessionItem.target = self
    newSessionItem.representedObject = "newSession"
    menu.addItem(newSessionItem)

    let reconnectItem = NSMenuItem(
      title: "重新连接",
      action: #selector(sendShortcut(_:)),
      keyEquivalent: "r"
    )
    reconnectItem.target = self
    reconnectItem.representedObject = "reconnect"
    menu.addItem(reconnectItem)

    let refreshItem = NSMenuItem(
      title: "刷新会话",
      action: #selector(sendShortcut(_:)),
      keyEquivalent: "R"
    )
    refreshItem.target = self
    refreshItem.representedObject = "refreshSessions"
    menu.addItem(refreshItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "设置…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "退出 Caduceus",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item

    // The App menu's Settings…（⌘,）points at the same handler.
    if let appMenu = NSApp.mainMenu?.items.first?.submenu,
       let settings = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
      settings.target = self
      settings.action = #selector(openSettings)
    }
  }

  /// The Caduceus mark, template-rendered so the system colours it for the
  /// current menu-bar appearance. The Flutter asset lives inside the app
  /// framework's bundle (`App.framework/Resources/flutter_assets/...`), not
  /// the main bundle.
  ///
  /// `tray_caduceus.png` is the pre-cropped glyph at exactly 2x (48px for the
  /// 24pt square button), with the source's soft glow removed — a 384px
  /// raster downscaled by AppKit ends up as a blurry blob in the menu bar.
  /// Falls back to the app icon and then a wand symbol.
  private static func trayImage() -> NSImage? {
    if let frameworks = Bundle.main.privateFrameworksURL {
      let appFramework = frameworks.appendingPathComponent("App.framework")
      if let bundle = Bundle(url: appFramework) {
        let candidates = ["tray_caduceus", "caduceus-pixel"]
        for name in candidates {
          if let path = bundle.path(
            forResource: name,
            ofType: "png",
            inDirectory: "flutter_assets/assets/images"
          ) {
            let image = NSImage(contentsOfFile: path)
            // Pin to 24pt so the 48px bitmap maps 1:1 on a 2x display
            // instead of being resampled and softened.
            image?.size = NSSize(width: 24, height: 24)
            return image
          }
        }
      }
    }
    if let appIcon = NSImage(named: NSImage.applicationIconName) {
      return appIcon
    }
    return NSImage(
      systemSymbolName: "wand.and.stars",
      accessibilityDescription: "Caduceus"
    )
  }

  @objc func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      window.makeKeyAndOrderFront(nil)
    }
  }

  @objc func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      window.makeKeyAndOrderFront(nil)
    }
    channel?.invokeMethod("openSettings", arguments: nil)
  }

  /// ⌘N / ⌘R / ⌘⇧R — forwards the menu shortcut to Flutter, which routes it
  /// to the active agent's workspace.
  @objc func sendShortcut(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      window.makeKeyAndOrderFront(nil)
    }
    if let name = sender.representedObject as? String {
      channel?.invokeMethod("shortcut", arguments: name)
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The chrome is glass over content, and a system title bar is an opaque
    // strip above all of it. Hiding it lets the sidebar's sheet run to the top
    // of the window with the traffic lights sitting in it.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    self.minSize = NSSize(width: 760, height: 480)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The engine is attached by now — plugin registration above is proof the
    // messenger is live. The tray is owned by [TrayController] (app lifetime),
    // so closing this window does not drop the menu-bar icon.
    TrayController.shared.install(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()

    // The traffic lights are system-drawn; nudge the group down from the
    // system default (~14 pt from the top) so they sit against the tab row.
    // Run after the nib's own layout and again on the next run-loop tick, so
    // the shift is not overwritten by the initial layout pass.
    offsetTrafficLights(down: trafficLightDownOffset)
    DispatchQueue.main.async { [weak self] in
      self?.offsetTrafficLights(down: self?.trafficLightDownOffset ?? 0)
    }

    // A resize re-runs the title-bar layout and resets the buttons; re-apply.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reapplyTrafficLightOffset),
      name: NSWindow.didResizeNotification,
      object: self
    )
  }

  @objc private func reapplyTrafficLightOffset() {
    offsetTrafficLights(down: trafficLightDownOffset)
  }

  /// How far the three window controls are lowered from macOS's default
  /// (~14 pt from the top). Tweak to taste.
  private let trafficLightDownOffset: CGFloat = 6

  /// First-seen origin of each button; the system may relayout the title bar
  /// after we move them, so re-applying the offset is idempotent (base + delta,
  /// never an accumulating +=).
  private var trafficLightBaseY: [NSWindow.ButtonType: CGFloat] = [:]

  /// Moves the close/miniaturize/zoom buttons down as a group. AppKit exposes
  /// them via `standardWindowButton(_:)`; the direction of the shift depends
  /// on whether the title-bar container is flipped.
  private func offsetTrafficLights(down offset: CGFloat) {
    for type in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      guard let button = standardWindowButton(type) else { continue }
      let base = trafficLightBaseY[type] ?? button.frame.origin.y
      trafficLightBaseY[type] = base
      let flipped = button.superview?.isFlipped ?? false
      button.frame.origin.y = base + (flipped ? offset : -offset)
    }
  }
}
