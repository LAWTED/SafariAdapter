import AppKit
import SwiftUI

@MainActor
final class CopyToastController {
    private enum Timing {
        static let appearDuration: TimeInterval = 0.12
        static let visibleDuration: TimeInterval = 1.35
        static let dismissDuration: TimeInterval = 0.16
        static let initialScale: CGFloat = 0.94
    }

    private enum Layout {
        static let visibleSize = CGSize(width: 196, height: 46)
        static let effectInset: CGFloat = 32
        static let verticalOffset: CGFloat = 164
        static let panelSize = CGSize(
            width: visibleSize.width + effectInset * 2,
            height: visibleSize.height + effectInset * 2
        )
    }

    private var panel: NSPanel?
    private var presentationID = UUID()

    func show(message: String, symbolName: String) {
        dismissImmediately()
        let currentPresentationID = UUID()
        presentationID = currentPresentationID

        let view = CopyToastView(message: message, symbolName: symbolName)
            .frame(width: Layout.visibleSize.width, height: Layout.visibleSize.height)
            .padding(Layout.effectInset)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        hosting.view.frame = NSRect(origin: .zero, size: Layout.panelSize)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let targetFrame = SidebarController.safariWindowFrame()
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        panel.setFrameOrigin(
            CGPoint(
                x: targetFrame.midX - Layout.panelSize.width / 2,
                y: targetFrame.midY - Layout.panelSize.height / 2 + Layout.verticalOffset
            )
        )
        panel.alphaValue = 0
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        panel.contentView?.layer?.setAffineTransform(
            CGAffineTransform(scaleX: Timing.initialScale, y: Timing.initialScale)
        )
        self.panel = panel
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(.identity)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.visibleDuration) { [weak self] in
            guard self?.presentationID == currentPresentationID else { return }
            self?.dismissAnimated()
        }
    }

    private func dismissAnimated() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.dismissDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                if self?.panel === panel {
                    self?.panel = nil
                }
            }
        }
    }

    private func dismissImmediately() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CopyToastView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let symbolName: String

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(
                        .regular.tint(
                            colorScheme == .dark
                                ? Color.black.opacity(0.2)
                                : Color.white.opacity(0.14)
                        ),
                        in: .capsule
                    )
            } else {
                content
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var content: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
