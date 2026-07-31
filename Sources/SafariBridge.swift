import AppKit
import Foundation

struct SafariTab: Identifiable, Equatable, Sendable {
    let index: Int
    let title: String
    let url: String

    var id: String { "\(index)-\(url)" }
}

struct SafariPageSnapshot: Equatable, Sendable {
    let title: String
    let url: String
}

/// Owns every `NSAppleScript` execution.
///
/// An AppleScript round-trip to Safari is a synchronous cross-process call.
/// It usually returns in ~10ms, but it queues behind whatever Safari is doing
/// and has been measured at 3s while a heavy page loads. Calls on the
/// Command-L path stay synchronous on purpose — the panel needs the URL and
/// the window frame before it can position itself — but anything driven by a
/// timer goes through `runInBackground` so it can never stall the UI.
///
/// `NSAppleScript` is not thread-safe, so one serial queue owns all off-main
/// execution.
enum SafariScriptRunner {
    /// `errAEEventNotPermitted` — the user has not granted Automation access.
    static let permissionDeniedCode = -1743

    /// Set by the app delegate. Invoked on the main thread, at most once per
    /// launch, when Safari refuses an event for lack of permission.
    @MainActor static var onAutomationPermissionDenied: (() -> Void)?

    private static let queue = DispatchQueue(
        label: "com.ha7ch.SafariAdapter.applescript",
        qos: .utility
    )

    static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { return result.stringValue }

        NSLog("SafariAdapter AppleScript error: %@", error)
        if (error[NSAppleScript.errorNumber] as? Int) == permissionDeniedCode {
            Task { @MainActor in
                guard let handler = onAutomationPermissionDenied else { return }
                onAutomationPermissionDenied = nil
                handler()
            }
        }
        return nil
    }

    static func runInBackground(
        _ source: String,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        queue.async { completion(run(source)) }
    }
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
        currentPage()?.url ?? ""
    }

    nonisolated private static let currentPageScript = """
    tell application "Safari"
        if (count of windows) is 0 then return ""
        set fieldSeparator to ASCII character 30
        set activeTab to current tab of front window
        set tabTitle to name of activeTab
        if tabTitle is missing value then set tabTitle to ""
        set tabAddress to URL of activeTab
        if tabAddress is missing value then return ""
        return tabTitle & fieldSeparator & tabAddress
    end tell
    """

    nonisolated private static func decodePage(_ encoded: String?) -> SafariPageSnapshot? {
        guard let encoded, !encoded.isEmpty else { return nil }
        let fields = encoded.components(separatedBy: "\u{001E}")
        guard fields.count >= 2, let url = fields.last, !url.isEmpty else { return nil }
        return SafariPageSnapshot(title: fields[0], url: url)
    }

    /// Synchronous — only for the Command-L path, which needs the answer before
    /// it can place the panel.
    func currentPage() -> SafariPageSnapshot? {
        Self.decodePage(SafariScriptRunner.run(Self.currentPageScript))
    }

    /// Off-main variant for the history sampler, which runs on a timer and must
    /// never block the UI.
    nonisolated func currentPageInBackground(
        completion: @escaping @Sendable (SafariPageSnapshot?) -> Void
    ) {
        SafariScriptRunner.runInBackground(Self.currentPageScript) { encoded in
            completion(SafariBridge.decodePage(encoded))
        }
    }

    /// One round-trip for everything the command bar shows: the front tab's
    /// address plus every open tab. Presenting used to make two synchronous
    /// calls before the panel could appear; this makes one, off the main
    /// thread, after it is already on screen.
    nonisolated func contextInBackground(
        completion: @escaping @Sendable (String, [SafariTab]) -> Void
    ) {
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set fieldSeparator to ASCII character 30
            set rowSeparator to ASCII character 31
            set output to ""
            tell front window
                set activeTab to current tab
                repeat with tabNumber from 1 to count of tabs
                    set candidateTab to tab tabNumber
                    set marker to "0"
                    if candidateTab is activeTab then set marker to "1"
                    set tabTitle to name of candidateTab
                    if tabTitle is missing value then set tabTitle to "Untitled"
                    set tabAddress to URL of candidateTab
                    if tabAddress is missing value then set tabAddress to ""
                    set output to output & marker & fieldSeparator & tabNumber & fieldSeparator & tabTitle & fieldSeparator & tabAddress & rowSeparator
                end repeat
            end tell
            return output
        end tell
        """

        SafariScriptRunner.runInBackground(source) { encoded in
            guard let encoded, !encoded.isEmpty else {
                completion("", [])
                return
            }

            var currentURL = ""
            var tabs: [SafariTab] = []
            for row in encoded.components(separatedBy: "\u{001F}") {
                let fields = row.components(separatedBy: "\u{001E}")
                guard fields.count >= 4, let index = Int(fields[1]) else { continue }
                tabs.append(SafariTab(index: index, title: fields[2], url: fields[3]))
                if fields[0] == "1" { currentURL = fields[3] }
            }
            completion(currentURL, tabs)
        }
    }

    func copyCurrentAddress(asMarkdown: Bool) -> Bool {
        let fieldSeparator = "\u{001E}"
        guard
            let encoded = SafariScriptRunner.run(Self.currentPageScript),
            !encoded.isEmpty
        else { return false }

        let fields = encoded.components(separatedBy: fieldSeparator)
        guard let url = fields.last, !url.isEmpty else { return false }
        let title = fields.first?.isEmpty == false ? fields[0] : url
        let clipboardValue = ClipboardFormatter.value(
            title: title,
            url: url,
            asMarkdown: asMarkdown
        )

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(clipboardValue, forType: .string)
    }

    /// Acting on the user's choice. Nothing reads the result and the command
    /// bar is already dismissed by the time these run, so they stay off the
    /// main thread — a slow Safari must not freeze the UI after the keystroke.
    nonisolated func activateInBackground(tab: SafariTab) {
        activateTabInBackground(at: tab.index)
    }

    nonisolated func activateTabInBackground(at index: Int) {
        guard index > 0 else { return }
        SafariScriptRunner.runInBackground(Self.activateTabScript(index: index)) { _ in }
    }

    nonisolated func navigateInBackground(to rawInput: String, inNewTab: Bool) {
        guard let source = Self.navigationScript(for: rawInput, inNewTab: inNewTab) else {
            return
        }
        SafariScriptRunner.runInBackground(source) { _ in }
    }

    nonisolated private static func activateTabScript(index: Int) -> String {
        """
        tell application "Safari"
            if (count of windows) is 0 then return
            tell front window
                if (count of tabs) >= \(index) then set current tab to tab \(index)
            end tell
            activate
        end tell
        """
    }

    nonisolated private static func navigationScript(
        for rawInput: String,
        inNewTab: Bool
    ) -> String? {
        guard let destination = DestinationParser.destination(for: rawInput) else {
            return nil
        }
        let literal = appleScriptLiteral(destination.absoluteString)

        if inNewTab {
            return """
            tell application "Safari"
                if (count of windows) is 0 then make new document
                tell front window
                    set createdTab to make new tab at end of tabs with properties {URL:\(literal)}
                    set current tab to createdTab
                end tell
                activate
            end tell
            """
        }
        return """
        tell application "Safari"
            if (count of windows) is 0 then make new document
            set URL of current tab of front window to \(literal)
            activate
        end tell
        """
    }

    nonisolated private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

enum ClipboardFormatter {
    static func value(title: String, url: String, asMarkdown: Bool) -> String {
        guard asMarkdown else { return url }
        let safeTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(safeTitle)](\(url))"
    }
}

enum DestinationParser {
    /// Schemes Safari can actually open. This list matters: `URL(string:)`
    /// happily reads "localhost:3000" as scheme "localhost", and handing that
    /// straight to Safari made the keystroke do nothing at all.
    private static let openableSchemes: Set<String> = [
        "http", "https", "file", "about", "data", "ftp"
    ]

    /// Returns nil only for empty input.
    ///
    /// Anything we cannot confidently interpret becomes a web search, and a
    /// host that does not resolve is still handed to Safari so it can show its
    /// own "can't find the server" page. Doing nothing is the one outcome the
    /// user can neither see nor act on.
    static func destination(for rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let match = SearchShortcut.matching(input) {
            return match.shortcut.destination(for: match.query) ?? searchURL(for: input)
        }
        if let explicit = explicitURL(for: input) {
            return explicit
        }
        if let host = hostURL(for: input) {
            return host
        }
        return searchURL(for: input)
    }

    private static func explicitURL(for input: String) -> URL? {
        guard
            let url = URL(string: input),
            let scheme = url.scheme?.lowercased(),
            openableSchemes.contains(scheme)
        else { return nil }

        // "http://" parses fine but points nowhere; let it fall through to
        // search rather than opening a blank failure.
        let hasDestination = !(url.host?.isEmpty ?? true)
            || scheme == "about"
            || scheme == "file"
            || scheme == "data"
        return hasDestination ? url : nil
    }

    private static func hostURL(for input: String) -> URL? {
        guard !input.contains(" ") else { return nil }

        let isLoopback = input.hasPrefix("localhost")
            || input.hasPrefix("127.0.0.1")
            || input.hasPrefix("0.0.0.0")
        guard isLoopback || input.contains(".") else { return nil }

        // Local dev servers are almost never on TLS, and https://localhost:3000
        // fails in a way that looks like the app ignored the input.
        let scheme = isLoopback ? "http" : "https"
        if let url = URL(string: "\(scheme)://\(input)") {
            return url
        }
        // Characters URL() rejects outright — encode rather than give up.
        guard let encoded = input.addingPercentEncoding(
            withAllowedCharacters: .urlFragmentAllowed
        ) else { return nil }
        return URL(string: "\(scheme)://\(encoded)")
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

struct SearchShortcutMatch {
    let shortcut: SearchShortcut
    let query: String
}

struct SearchShortcut: Hashable {
    let name: String
    let aliases: Set<String>
    let baseURL: String
    let queryItemName: String

    static let all: [SearchShortcut] = [
        SearchShortcut(
            name: "Google",
            aliases: ["g", "google"],
            baseURL: "https://www.google.com/search",
            queryItemName: "q"
        ),
        SearchShortcut(
            name: "GitHub",
            aliases: ["gh", "github"],
            baseURL: "https://github.com/search",
            queryItemName: "q"
        ),
        SearchShortcut(
            name: "YouTube",
            aliases: ["yt", "youtube"],
            baseURL: "https://www.youtube.com/results",
            queryItemName: "search_query"
        ),
        SearchShortcut(
            name: "X",
            aliases: ["x"],
            baseURL: "https://x.com/search",
            queryItemName: "q"
        ),
        SearchShortcut(
            name: "Google Maps",
            aliases: ["maps"],
            baseURL: "https://www.google.com/maps/search/",
            queryItemName: "query"
        )
    ]

    static func matching(_ rawInput: String) -> SearchShortcutMatch? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard
            let alias = pieces.first?.lowercased(),
            let shortcut = all.first(where: { $0.aliases.contains(alias) })
        else { return nil }

        let query = pieces.count > 1
            ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return SearchShortcutMatch(shortcut: shortcut, query: query)
    }

    func destination(for query: String) -> URL? {
        if query.isEmpty {
            switch name {
            case "GitHub": return URL(string: "https://github.com")
            case "YouTube": return URL(string: "https://www.youtube.com")
            case "X": return URL(string: "https://x.com")
            case "Google Maps": return URL(string: "https://www.google.com/maps")
            default: return URL(string: "https://www.google.com")
            }
        }

        var components = URLComponents(string: baseURL)
        var queryItems = [URLQueryItem(name: queryItemName, value: query)]
        if name == "Google Maps" {
            queryItems.insert(URLQueryItem(name: "api", value: "1"), at: 0)
        }
        components?.queryItems = queryItems
        return components?.url
    }
}
