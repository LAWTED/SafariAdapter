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
    private let historyStore = HistoryStore()
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
        materialProvider: { [weak self] in self?.selectedMaterial ?? .oldHUD },
        historyProvider: { [weak self] in self?.historyStore.entries ?? [] }
    )
    private let copyToast = CopyToastController()
    private lazy var hotKeys = HotKeyManager(
        openCommandBar: { [weak self] in self?.openCommandBar() },
        selectTab: { [weak self] index in self?.selectTab(index: index) },
        copyCurrentAddress: { [weak self] asMarkdown in
            self?.copyCurrentAddress(asMarkdown: asMarkdown)
        },
        reportCommandBarUnavailable: { [weak self] status in
            self?.presentCommandBarUnavailableAlert(status: status)
        }
    )

    private var activationObserver: NSObjectProtocol?
    private var frontmostPollTimer: Timer?
    private var historyPollTimer: Timer?
    private var pendingHistoryPage: SafariPageSnapshot?
    private var pendingHistorySince = Date()
    private var lastCommittedHistoryURL: String?
    private var isSamplingHistory = false
    private var isCommandBarPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-command-bar")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SafariScriptRunner.onAutomationPermissionDenied = { [weak self] in
            self?.presentAutomationPermissionAlert()
        }
        observeFrontmostApplication()
        startFrontmostPolling()
        startHistoryPolling()
        updateHotKeyRegistration()

        if ProcessInfo.processInfo.arguments.contains("--preview-command-bar") {
            let arguments = ProcessInfo.processInfo.arguments
            let animatesQuery = arguments.contains("--preview-animate-query")
            let animationDelay: TimeInterval
            if
                let delayIndex = arguments.firstIndex(of: "--preview-animation-delay"),
                arguments.indices.contains(delayIndex + 1),
                let delay = TimeInterval(arguments[delayIndex + 1])
            {
                animationDelay = delay
            } else {
                animationDelay = 3.0
            }
            let query: String?
            if
                let flagIndex = arguments.firstIndex(of: "--preview-query"),
                arguments.indices.contains(flagIndex + 1)
            {
                query = arguments[flagIndex + 1]
            } else {
                query = nil
            }
            let collapseDelay: TimeInterval?
            if
                let collapseIndex = arguments.firstIndex(of: "--preview-collapse-delay"),
                arguments.indices.contains(collapseIndex + 1),
                let delay = TimeInterval(arguments[collapseIndex + 1])
            {
                collapseDelay = delay
            } else {
                collapseDelay = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.overlay.present(
                    prefilledQuery: animatesQuery ? nil : query,
                    dismissesOnResign: false
                )
                if animatesQuery, let query {
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) { [weak self] in
                        self?.overlay.updateQueryForPreview(query)
                    }
                    if let collapseDelay {
                        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay) { [weak self] in
                            self?.overlay.updateQueryForPreview("")
                        }
                    }
                }
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--preview-copy-toast") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.copyToast.show(message: "Markdown link copied", symbolName: "text.badge.checkmark")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        frontmostPollTimer?.invalidate()
        frontmostPollTimer = nil
        historyPollTimer?.invalidate()
        historyPollTimer = nil
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
            Task { @MainActor in
                self?.updateHotKeyRegistration()
            }
        }
    }

    private func startHistoryPolling() {
        guard !isCommandBarPreview else { return }
        historyPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.captureStableHistoryPage() }
        }
    }

    /// Samples the front tab off the main thread. The AppleScript round-trip is
    /// normally ~10ms but can stall for seconds behind a loading page, so the
    /// timer must never wait on it — and a slow sample must not let the next
    /// ticks pile up behind it.
    private func captureStableHistoryPage() {
        guard historyStore.isEnabled, SafariBridge.isSafariFrontmost else {
            pendingHistoryPage = nil
            return
        }
        guard !isSamplingHistory else { return }

        isSamplingHistory = true
        safari.currentPageInBackground { page in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSamplingHistory = false
                self.commitHistorySample(page)
            }
        }
    }

    private func commitHistorySample(_ sampledPage: SafariPageSnapshot?) {
        guard historyStore.isEnabled, SafariBridge.isSafariFrontmost else {
            pendingHistoryPage = nil
            return
        }
        guard
            let page = sampledPage,
            let canonicalURL = HistoryStore.canonicalURL(for: page.url)
        else {
            pendingHistoryPage = nil
            return
        }

        let pendingCanonicalURL = pendingHistoryPage.flatMap {
            HistoryStore.canonicalURL(for: $0.url)
        }
        guard pendingCanonicalURL == canonicalURL else {
            pendingHistoryPage = page
            pendingHistorySince = Date()
            return
        }
        // Keep the newest title without restarting the stability timer when a
        // site updates only its document title (for example an unread count).
        pendingHistoryPage = page

        guard Date().timeIntervalSince(pendingHistorySince) >= 1.5 else { return }
        guard canonicalURL != lastCommittedHistoryURL else { return }
        historyStore.record(title: page.title, url: page.url)
        lastCommittedHistoryURL = canonicalURL
    }

    private func updateHotKeyRegistration() {
        if isCommandBarPreview {
            hotKeys.unregister()
            return
        }

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

    private func openCommandBar() {
        overlay.present()
    }

    private func selectTab(index: Int) {
        overlay.dismiss(returnFocusToSafari: false)
        safari.activateTabInBackground(at: index)
    }

    private func copyCurrentAddress(asMarkdown: Bool) {
        guard safari.copyCurrentAddress(asMarkdown: asMarkdown) else { return }
        copyToast.show(
            message: asMarkdown ? "Markdown link copied" : "Address copied",
            symbolName: asMarkdown ? "text.badge.checkmark" : "link"
        )
    }

    /// Without this, a missing Automation grant looks like the app doing
    /// nothing: the command bar opens with an empty address and no explanation.
    /// Shown at most once per launch.
    private func presentAutomationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "SafariAdapter needs permission to control Safari"
        alert.informativeText = """
        macOS blocked SafariAdapter from reading the current tab, so the \
        command bar cannot show or change the address.

        Open System Settings → Privacy & Security → Automation, then enable \
        Safari under SafariAdapter.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentCommandBarUnavailableAlert(status: OSStatus) {
        let alert = NSAlert()
        alert.messageText = "Command-L is unavailable"
        alert.informativeText = """
        Another app already owns the Command-L shortcut, so SafariAdapter \
        could not claim it (error \(status)).

        Quit whichever app registered it, then switch back to Safari — \
        SafariAdapter retries every time Safari comes forward.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
