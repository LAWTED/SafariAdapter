import AppKit
import ApplicationServices

enum SidebarController {
    private static let safariBundleIdentifier = "com.apple.Safari"
    private static let sidebarIdentifier = "SidebarButton"

    static func toggleSafariSidebar() {
        guard ensureAccessibilityPermission() else { return }
        guard let safari = NSRunningApplication.runningApplications(
            withBundleIdentifier: safariBundleIdentifier
        ).first else { return }

        let application = AXUIElementCreateApplication(safari.processIdentifier)
        if let button = findElement(in: application, matchingIdentifier: sidebarIdentifier) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

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

    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private static func findElement(
        in root: AXUIElement,
        matchingIdentifier target: String,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }

        var identifierValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            root,
            kAXIdentifierAttribute as CFString,
            &identifierValue
        ) == .success,
        let identifier = identifierValue as? String,
        identifier.contains(target) {
            return root
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] else { return nil }

        for child in children {
            if let match = findElement(in: child, matchingIdentifier: target, depth: depth + 1) {
                return match
            }
        }
        return nil
    }
}
