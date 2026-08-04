import AppKit
import ApplicationServices

enum SidebarController {
    private static let safariBundleIdentifier = "com.apple.Safari"

    static func safariWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let safari = NSRunningApplication.runningApplications(
            withBundleIdentifier: safariBundleIdentifier
        ).first else { return nil }

        let application = AXUIElementCreateApplication(safari.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue else { return nil }

        let window = focusedWindowValue as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        // Accessibility coordinates have a top-left origin; AppKit uses bottom-left.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(position) }) ?? NSScreen.main else {
            return nil
        }
        let appKitY = screen.frame.maxY - position.y - size.height
        return CGRect(x: position.x, y: appKitY, width: size.width, height: size.height)
    }

}
