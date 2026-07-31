import AppKit
import SwiftUI

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD
 *
 * Read top-to-bottom. Each value is ms after the relevant trigger.
 *
 *    0ms   panel appears at 96% scale and 0% opacity
 *  140ms   panel reaches 100% scale and full opacity
 *  110ms   address field is focused and fully selected
 *
 *    0ms   matching tabs change; command field stays pinned
 *  200ms   bottom edge settles at its new height, revealing rows
 * ───────────────────────────────────────────────────────── */

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private enum Timing {
        static let appearDuration: TimeInterval = 0.14
        static let expandDuration: TimeInterval = 0.28
        static let collapseDuration: TimeInterval = 0.15
        static let focusDelay: TimeInterval = 0.11
        static let initialScale: CGFloat = 0.96
        static let finalScale: CGFloat = 1.0
    }

    private enum Layout {
        static let visibleWidth: CGFloat = 720
        static let effectInset: CGFloat = 48
        static let verticalOffset: CGFloat = 92

        static func panelSize(for contentHeight: CGFloat) -> CGSize {
            CGSize(
                width: visibleWidth + effectInset * 2,
                height: contentHeight + effectInset * 2
            )
        }
    }

    private let safari: SafariBridge
    private let materialProvider: () -> CommandBarMaterial
    private let historyProvider: () -> [HistoryEntry]
    private var panel: CommandPanel?
    private var model: CommandBarModel?
    private var dismissesOnResign = true
    private var resizeTimer: Timer?
    private var resizeStartFrame = NSRect.zero
    private var resizeEndFrame = NSRect.zero
    private var resizeStartTime: TimeInterval = 0
    private var resizeDuration: TimeInterval = 0
    private var resizeIsExpanding = false

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(
        safari: SafariBridge,
        materialProvider: @escaping () -> CommandBarMaterial,
        historyProvider: @escaping () -> [HistoryEntry]
    ) {
        self.safari = safari
        self.materialProvider = materialProvider
        self.historyProvider = historyProvider
        super.init()
    }

    func present(
        prefilledQuery: String? = nil,
        dismissesOnResign: Bool = true
    ) {
        NSLog("SafariAdapter presenting command bar")
        if panel?.isVisible == true {
            dismiss(returnFocusToSafari: true)
            return
        }

        // The address and tab list arrive asynchronously (see
        // `loadSafariContext`). Only the *position* still reads Safari
        // synchronously — that one has to be exact before the panel appears.
        let model = CommandBarModel(
            initialURL: "",
            openTabs: [],
            historyEntries: historyProvider(),
            navigate: { [weak self] value, newTab in
                // Dismiss first: the AppleScript that performs the navigation
                // can take hundreds of milliseconds, and doing it the other way
                // round left the panel frozen on screen for that whole time,
                // which read as "the page is slow to load".
                self?.dismiss(returnFocusToSafari: false)
                self?.safari.navigateInBackground(to: value, inNewTab: newTab)
            },
            activateTab: { [weak self] tab in
                self?.dismiss(returnFocusToSafari: false)
                self?.safari.activateInBackground(tab: tab)
            },
            dismiss: { [weak self] in self?.dismiss(returnFocusToSafari: true) },
            layoutChanged: { [weak self] contentHeight in
                self?.resizePanel(for: contentHeight)
            }
        )
        self.dismissesOnResign = dismissesOnResign
        if let prefilledQuery {
            model.textDidChange(prefilledQuery)
        }
        self.model = model
        let initialSize = Layout.panelSize(for: model.contentHeight)

        let material = materialProvider()
        let view = GeometryReader { geometry in
            let visibleHeight = max(
                CommandBarModel.searchHeight,
                geometry.size.height - Layout.effectInset * 2
            )
            CommandBarView(
                model: model,
                material: material,
                visibleHeight: visibleHeight
            )
                .frame(
                    width: Layout.visibleWidth,
                    height: visibleHeight,
                    alignment: .top
                )
                .position(
                    x: geometry.size.width / 2,
                    y: Layout.effectInset + visibleHeight / 2
                )
        }
        let hosting = NSHostingController(rootView: view)
        // The panel owns its animated size. If the hosting controller publishes
        // its new intrinsic height, AppKit expands the window immediately
        // before our frame animation can run.
        hosting.sizingOptions = []
        let panel = CommandPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        hosting.view.frame = NSRect(origin: .zero, size: initialSize)
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentMinSize = CGSize(width: initialSize.width, height: 0)
        panel.contentMaxSize = CGSize(width: initialSize.width, height: 1_000)
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

        loadSafariContext(into: model)
    }

    private func loadSafariContext(into model: CommandBarModel) {
        safari.contextInBackground { currentURL, tabs in
            Task { @MainActor [weak self] in
                // The panel may already have been dismissed and replaced.
                guard let self, self.model === model else { return }
                model.applySafariContext(currentURL: currentURL, openTabs: tabs)
            }
        }
    }

    func dismiss(returnFocusToSafari: Bool = false) {
        guard let panel else { return }
        NSLog("SafariAdapter dismissing command bar")
        resizeTimer?.invalidate()
        resizeTimer = nil
        panel.orderOut(nil)
        self.panel = nil
        model = nil
        if returnFocusToSafari {
            safari.activateSafari()
        }
    }

    func updateQueryForPreview(_ query: String) {
        model?.textDidChange(query)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard dismissesOnResign else { return }
        dismiss(returnFocusToSafari: false)
    }

    private func resizePanel(for contentHeight: CGFloat) {
        guard let panel else { return }
        let newSize = Layout.panelSize(for: contentHeight)
        guard abs(panel.frame.height - newSize.height) > 0.5 else { return }
        let isExpanding = newSize.height > panel.frame.height

        let topEdge = panel.frame.maxY
        let newFrame = NSRect(
            x: panel.frame.minX,
            y: topEdge - newSize.height,
            width: newSize.width,
            height: newSize.height
        )

        resizeTimer?.invalidate()
        resizeTimer = nil

        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0
            : (isExpanding ? Timing.expandDuration : Timing.collapseDuration)
        guard duration > 0 else {
            panel.setFrame(newFrame, display: true)
            return
        }

        resizeStartFrame = panel.frame
        resizeEndFrame = newFrame
        resizeStartTime = CACurrentMediaTime()
        resizeDuration = duration
        resizeIsExpanding = isExpanding

        let timer = Timer(
            timeInterval: 1.0 / 120.0,
            target: self,
            selector: #selector(stepResizeAnimation(_:)),
            userInfo: nil,
            repeats: true
        )
        resizeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    @objc private func stepResizeAnimation(_ timer: Timer) {
        guard let panel, timer === resizeTimer else {
            timer.invalidate()
            return
        }

        let elapsed = CACurrentMediaTime() - resizeStartTime
        let linearProgress = min(max(elapsed / resizeDuration, 0), 1)
        let easedProgress: CGFloat
        if resizeIsExpanding {
            // Smoothstep starts gently, accelerates through the middle, and
            // settles without the near-instant first jump of the old curve.
            easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
        } else {
            let remaining = 1 - linearProgress
            easedProgress = 1 - remaining * remaining * remaining
        }

        let frame = NSRect(
            x: interpolate(resizeStartFrame.minX, resizeEndFrame.minX, easedProgress),
            y: interpolate(resizeStartFrame.minY, resizeEndFrame.minY, easedProgress),
            width: interpolate(resizeStartFrame.width, resizeEndFrame.width, easedProgress),
            height: interpolate(resizeStartFrame.height, resizeEndFrame.height, easedProgress)
        )
        panel.setFrame(frame, display: true)
        panel.contentViewController?.view.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentViewController?.view.needsLayout = true
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()

        if linearProgress >= 1 {
            timer.invalidate()
            resizeTimer = nil
        }
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
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
