import AppKit
import Foundation

struct SafariTab: Identifiable, Equatable {
    let index: Int
    let title: String
    let url: String

    var id: String { "\(index)-\(url)" }
}

@MainActor
final class SafariBridge {
    static let safariBundleIdentifier = "com.apple.Safari"

    static var isSafariFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleIdentifier
    }

    func activateSafari() {
        guard let safari = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.safariBundleIdentifier
        ).first else { return }
        safari.activate()
    }

    func currentURL() -> String {
        runAppleScript("""
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set currentAddress to URL of current tab of front window
            if currentAddress is missing value then return ""
            return currentAddress
        end tell
        """) ?? ""
    }

    func openTabs() -> [SafariTab] {
        let fieldSeparator = "\u{001E}"
        let rowSeparator = "\u{001F}"
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set fieldSeparator to ASCII character 30
            set rowSeparator to ASCII character 31
            set output to ""
            tell front window
                repeat with tabNumber from 1 to count of tabs
                    set candidateTab to tab tabNumber
                    set tabTitle to name of candidateTab
                    if tabTitle is missing value then set tabTitle to "Untitled"
                    set tabAddress to URL of candidateTab
                    if tabAddress is missing value then set tabAddress to ""
                    set output to output & tabNumber & fieldSeparator & tabTitle & fieldSeparator & tabAddress & rowSeparator
                end repeat
            end tell
            return output
        end tell
        """

        guard let encodedTabs = runAppleScript(source) else { return [] }
        return encodedTabs
            .components(separatedBy: rowSeparator)
            .compactMap { row in
                let fields = row.components(separatedBy: fieldSeparator)
                guard fields.count >= 3, let index = Int(fields[0]) else { return nil }
                return SafariTab(index: index, title: fields[1], url: fields[2])
            }
    }

    func activate(tab: SafariTab) {
        activateTab(at: tab.index)
    }

    func activateTab(at index: Int) {
        guard index > 0 else { return }
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then return
            tell front window
                if (count of tabs) >= \(index) then set current tab to tab \(index)
            end tell
            activate
        end tell
        """
        _ = runAppleScript(source)
    }

    func navigate(to rawInput: String, inNewTab: Bool) {
        guard let destination = DestinationParser.destination(for: rawInput) else { return }
        let literal = appleScriptLiteral(destination.absoluteString)

        let source: String
        if inNewTab {
            source = """
            tell application "Safari"
                if (count of windows) is 0 then make new document
                tell front window
                    set createdTab to make new tab at end of tabs with properties {URL:\(literal)}
                    set current tab to createdTab
                end tell
                activate
            end tell
            """
        } else {
            source = """
            tell application "Safari"
                if (count of windows) is 0 then make new document
                set URL of current tab of front window to \(literal)
                activate
            end tell
            """
        }

        _ = runAppleScript(source)
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("SafariAdapter AppleScript error: %@", error)
            return nil
        }
        return result.stringValue
    }

    private func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

enum DestinationParser {
    static func destination(for rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let explicitURL = URL(string: input), explicitURL.scheme != nil {
            return explicitURL
        }

        let looksLikeHost = !input.contains(" ") && (
            input.contains(".") ||
            input.hasPrefix("localhost") ||
            input.hasPrefix("127.0.0.1")
        )

        if looksLikeHost, let url = URL(string: "https://\(input)") {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: input)]
        return components?.url
    }
}
