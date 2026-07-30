import AppKit
import SwiftUI

@main
struct SafariAdapterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let safari = SafariBridge()
    private var selectedMaterial: CommandBarMaterial = {
        guard
            let savedValue = UserDefaults.standard.string(forKey: "commandBarMaterial"),
            let material = CommandBarMaterial(rawValue: savedValue)
        else {
            return .oldHUD
        }
        return material
    }()
    private lazy var overlay = OverlayPanelController(
        safari: safari,
        materialProvider: { [weak self] in self?.selectedMaterial ?? .oldHUD }
    )
    private lazy var hotKeys = HotKeyManager(
        openCommandBar: { [weak self] in self?.openCommandBar() },
        toggleSidebar: { [weak self] in self?.toggleSidebar() },
        selectTab: { [weak self] index in self?.selectTab(index: index) }
    )

    private var statusItem: NSStatusItem?
    private var materialMenu: NSMenu?
    private var activationObserver: NSObjectProtocol?
    private var frontmostPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        observeFrontmostApplication()
        startFrontmostPolling()
        updateHotKeyRegistration()

        if ProcessInfo.processInfo.arguments.contains("--preview-command-bar") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.overlay.present()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        frontmostPollTimer?.invalidate()
        frontmostPollTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func observeFrontmostApplication() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateHotKeyRegistration() }
        }
    }

    private func startFrontmostPolling() {
        frontmostPollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.updateHotKeyRegistration() }
        }
    }

    private func updateHotKeyRegistration() {
        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isAdapterFrontmost = frontmostIdentifier == Bundle.main.bundleIdentifier
        if SafariBridge.isSafariFrontmost {
            hotKeys.register()
        } else if isAdapterFrontmost && overlay.isVisible {
            hotKeys.register()
        } else {
            hotKeys.unregister()
            overlay.dismiss(returnFocusToSafari: false)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.and.text.magnifyingglass",
            accessibilityDescription: "SafariAdapter"
        )
        item.button?.toolTip = "SafariAdapter"

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Command Bar",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let sidebarItem = NSMenuItem(
            title: "Toggle Safari Sidebar",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        sidebarItem.target = self
        menu.addItem(sidebarItem)

        let materialItem = NSMenuItem(
            title: "Command Bar Material",
            action: nil,
            keyEquivalent: ""
        )
        let materialMenu = NSMenu(title: "Command Bar Material")
        for material in CommandBarMaterial.allCases {
            let item = NSMenuItem(
                title: material.title,
                action: #selector(changeMaterial(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = material.rawValue
            item.state = material == selectedMaterial ? .on : .off
            materialMenu.addItem(item)
        }
        materialItem.submenu = materialMenu
        menu.addItem(materialItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit SafariAdapter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        self.materialMenu = materialMenu
    }

    @objc private func openFromMenu() {
        safari.activateSafari()
        openCommandBar()
    }

    @objc private func toggleFromMenu() {
        safari.activateSafari()
        toggleSidebar()
    }

    @objc private func changeMaterial(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let material = CommandBarMaterial(rawValue: rawValue)
        else { return }

        selectedMaterial = material
        UserDefaults.standard.set(material.rawValue, forKey: "commandBarMaterial")
        for item in materialMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == material.rawValue ? .on : .off
        }
        overlay.dismiss(returnFocusToSafari: false)
    }

    private func openCommandBar() {
        overlay.present()
    }

    private func toggleSidebar() {
        overlay.dismiss(returnFocusToSafari: false)
        SidebarController.toggleSafariSidebar()
    }

    private func selectTab(index: Int) {
        overlay.dismiss(returnFocusToSafari: false)
        safari.activateTab(at: index)
    }
}
