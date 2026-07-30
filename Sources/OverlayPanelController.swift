import AppKit
import SwiftUI

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD
 *
 * Read top-to-bottom. Each value is ms after Command-L.
 *
 *    0ms   panel appears at 96% scale and 0% opacity
 *   90ms   panel reaches 100% scale and full opacity
 *  110ms   address field is focused and fully selected
 *  160ms   current-page row settles into view
 * ───────────────────────────────────────────────────────── */

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private enum Timing {
        static let appearDuration: TimeInterval = 0.14
        static let focusDelay: TimeInterval = 0.11
        static let initialScale: CGFloat = 0.96
        static let finalScale: CGFloat = 1.0
    }

    private enum Layout {
        static let visibleBarSize = CGSize(width: 720, height: 68)
        static let effectInset: CGFloat = 48
        static let panelSize = CGSize(
            width: visibleBarSize.width + effectInset * 2,
            height: visibleBarSize.height + effectInset * 2
        )
        static let verticalOffset: CGFloat = 92
    }

    private let safari: SafariBridge
    private let materialProvider: () -> CommandBarMaterial
    private var panel: CommandPanel?
    private var model: CommandBarModel?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(
        safari: SafariBridge,
        materialProvider: @escaping () -> CommandBarMaterial
    ) {
        self.safari = safari
        self.materialProvider = materialProvider
        super.init()
    }

    func present() {
        NSLog("SafariAdapter presenting command bar")
        if panel?.isVisible == true {
            dismiss(returnFocusToSafari: true)
            return
        }

        let currentURL = safari.currentURL()
        let model = CommandBarModel(
            initialURL: currentURL,
            navigate: { [weak self] value, newTab in
                self?.safari.navigate(to: value, inNewTab: newTab)
                self?.dismiss(returnFocusToSafari: false)
            },
            dismiss: { [weak self] in self?.dismiss(returnFocusToSafari: true) }
        )
        self.model = model
        let initialSize = Layout.panelSize

        let material = materialProvider()
        let view = CommandBarView(model: model, material: material)
            .frame(
                width: Layout.visibleBarSize.width,
                height: Layout.visibleBarSize.height
            )
            .padding(Layout.effectInset)
            .frame(width: initialSize.width, height: initialSize.height)
        let hosting = NSHostingController(rootView: view)
        let panel = CommandPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        hosting.view.frame = NSRect(origin: .zero, size: initialSize)
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentMinSize = initialSize
        panel.contentMaxSize = initialSize
        panel.setContentSize(initialSize)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Liquid Glass renders its own edge light and shadow. The larger clear
        // canvas lets that effect fade naturally instead of clipping at the
        // rectangular NSPanel boundary.
        panel.hasShadow = material != .liquidGlass
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let origin = panelOrigin(for: initialSize)
        panel.setFrameOrigin(origin)
        NSLog("SafariAdapter command bar origin: %.0f, %.0f", origin.x, origin.y)
        self.panel = panel

        panel.alphaValue = 0
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        panel.contentView?.layer?.setAffineTransform(
            CGAffineTransform(scaleX: Timing.initialScale, y: Timing.initialScale)
        )

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // NSHostingController may publish a compact intrinsic size while being
        // attached. Reassert the command-bar canvas after the panel is visible.
        panel.setContentSize(initialSize)
        hosting.view.frame = NSRect(origin: .zero, size: initialSize)
        NSLog(
            "SafariAdapter command bar size: %.0f × %.0f",
            panel.frame.width,
            panel.frame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(
                CGAffineTransform(scaleX: Timing.finalScale, y: Timing.finalScale)
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focusDelay) {
            model.focusRequest += 1
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss(returnFocusToSafari: false) }
        }
    }

    func dismiss(returnFocusToSafari: Bool = false) {
        guard let panel else { return }
        NSLog("SafariAdapter dismissing command bar")
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel.orderOut(nil)
        self.panel = nil
        model = nil
        if returnFocusToSafari {
            safari.activateSafari()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss(returnFocusToSafari: false)
    }

    private func panelOrigin(for size: CGSize) -> CGPoint {
        let targetFrame = SidebarController.safariWindowFrame()
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        return CGPoint(
            x: targetFrame.midX - size.width / 2,
            y: targetFrame.midY - size.height / 2 + Layout.verticalOffset
        )
    }

}

final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
