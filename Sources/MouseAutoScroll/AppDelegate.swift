import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let controller = EventTapController()
  private var statusItem: NSStatusItem!
  private var statusMenuItem: NSMenuItem!
  private var enabledMenuItem: NSMenuItem!

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()

    controller.onStatusChange = { [weak self] status in
      self?.updateStatus(status)
    }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
      self,
      selector: #selector(environmentChanged),
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    workspaceCenter.addObserver(
      self,
      selector: #selector(environmentChanged),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )

    controller.start(requestPermissions: true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.setEnabled(false)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "arrow.up.and.down.circle",
      accessibilityDescription: "鼠标自动滚动"
    )

    let menu = NSMenu()
    statusMenuItem = NSMenuItem(title: "状态：正在启动", action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false
    menu.addItem(statusMenuItem)
    menu.addItem(.separator())

    enabledMenuItem = NSMenuItem(
      title: "启用中键自动滚动",
      action: #selector(toggleEnabled),
      keyEquivalent: ""
    )
    enabledMenuItem.target = self
    enabledMenuItem.state = .on
    menu.addItem(enabledMenuItem)

    let permissionItem = NSMenuItem(
      title: "重新检查并申请权限",
      action: #selector(requestPermissions),
      keyEquivalent: ""
    )
    permissionItem.target = self
    menu.addItem(permissionItem)

    menu.addItem(.separator())
    let helpItem = NSMenuItem(
      title: "中键激活；任意鼠标键或 Esc 退出",
      action: nil,
      keyEquivalent: ""
    )
    helpItem.isEnabled = false
    menu.addItem(helpItem)

    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "退出",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)
    statusItem.menu = menu
  }

  private func updateStatus(_ status: EventTapController.Status) {
    statusMenuItem.title = status.menuText
    statusItem.button?.image = NSImage(
      systemSymbolName: status == .scrolling
        ? "arrow.up.and.down.circle.fill"
        : "arrow.up.and.down.circle",
      accessibilityDescription: "鼠标自动滚动"
    )
  }

  @objc private func toggleEnabled() {
    let shouldEnable = enabledMenuItem.state != .on
    enabledMenuItem.state = shouldEnable ? .on : .off
    controller.setEnabled(shouldEnable)
  }

  @objc private func requestPermissions() {
    enabledMenuItem.state = .on
    controller.start(requestPermissions: true)
  }

  @objc private func environmentChanged() {
    controller.applicationEnvironmentChanged()
  }
}
