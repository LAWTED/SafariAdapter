import AppKit
import Foundation

@main
struct CommandBarSmoke {
    @MainActor
    static func main() {
        let openGitHub = SafariTab(
            index: 2,
            title: "SafariAdapter · GitHub",
            url: "https://github.com/HA7CH/SafariAdapter"
        )
        let history = [
            HistoryEntry(
                id: HistoryStore.canonicalURL(for: "https://github.com/HA7CH/SafariAdapter")!,
                title: "Duplicate GitHub history",
                url: "https://github.com/HA7CH/SafariAdapter",
                lastVisited: Date(),
                visitCount: 8
            ),
            HistoryEntry(
                id: HistoryStore.canonicalURL(for: "https://developer.apple.com/documentation/safariservices")!,
                title: "Safari Services Documentation",
                url: "https://developer.apple.com/documentation/safariservices",
                lastVisited: Date().addingTimeInterval(-60),
                visitCount: 3
            ),
            HistoryEntry(
                id: HistoryStore.canonicalURL(for: "https://microsoft.ai/careers/")!,
                title: "Microsoft AI Careers",
                url: "https://microsoft.ai/careers/",
                lastVisited: Date().addingTimeInterval(-120),
                visitCount: 2
            )
        ]

        var navigations: [(String, Bool)] = []
        var activatedTab: SafariTab?
        let model = CommandBarModel(
            initialURL: "https://example.com",
            openTabs: [openGitHub],
            historyEntries: history,
            navigate: { navigations.append(($0, $1)) },
            activateTab: { activatedTab = $0 },
            dismiss: {},
            layoutChanged: { _ in }
        )

        // The typed intent is always the first and selected result. Matching
        // tabs and history stay available below it without hijacking Return.
        model.textDidChange("SafariAdapter")
        guard case .action(let googleAction)? = model.results.first else {
            preconditionFailure("Expected Google search as the primary action")
        }
        precondition(googleAction.kind == .search(engine: "Google", query: "SafariAdapter"))
        precondition(model.results.dropFirst().first == .openTab(openGitHub))
        precondition(model.selectedResultIndex == 0)
        model.submit(opensInNewTab: false)
        precondition(activatedTab == nil)
        precondition(navigations.last?.0.contains("google.com/search") == true)
        precondition(navigations.last?.0.contains("q=SafariAdapter") == true)
        precondition(navigations.last?.1 == false)

        model.moveSelection(by: 1)
        model.submit(opensInNewTab: false)
        precondition(activatedTab == openGitHub)

        model.textDidChange("Safari Services")
        guard case .action(let historyQueryAction)? = model.results.first else {
            preconditionFailure("Expected Google search before history")
        }
        precondition(
            historyQueryAction.kind == .search(engine: "Google", query: "Safari Services")
        )
        guard case .history(let matchedHistory)? = model.results.dropFirst().first else {
            preconditionFailure("Expected a history result")
        }
        precondition(matchedHistory.url.contains("developer.apple.com"))
        model.submit(opensInNewTab: false)
        precondition(navigations.last?.0.contains("google.com/search") == true)
        precondition(navigations.last?.0.contains("Safari%20Services") == true)

        model.moveSelection(by: 1)
        model.submit(opensInNewTab: false)
        precondition(navigations.last?.0 == matchedHistory.url)
        precondition(navigations.last?.1 == false)

        // A bare domain opens that domain. A deeper history match is secondary.
        model.textDidChange("microsoft.ai")
        guard case .action(let bareDomainAction)? = model.results.first else {
            preconditionFailure("Expected direct navigation for a bare domain")
        }
        precondition(bareDomainAction.kind == .open)
        precondition(bareDomainAction.url.absoluteString == "https://microsoft.ai")
        guard case .history(let careers)? = model.results.dropFirst().first else {
            preconditionFailure("Expected the careers page as a secondary history result")
        }
        precondition(careers.url == "https://microsoft.ai/careers/")
        model.submit(opensInNewTab: false)
        precondition(navigations.last?.0 == "https://microsoft.ai")

        // An exact URL never gets duplicated by the same history entry.
        model.textDidChange("https://microsoft.ai/careers/")
        precondition(model.results.count == 1)
        guard case .action(let exactURLAction)? = model.results.first else {
            preconditionFailure("Expected direct navigation for an exact URL")
        }
        precondition(exactURLAction.url.absoluteString == "https://microsoft.ai/careers/")

        // Even an already-open exact URL keeps navigation as the default; the
        // existing tab becomes an explicit secondary choice.
        model.textDidChange(openGitHub.url)
        guard case .action(let openURLAction)? = model.results.first else {
            preconditionFailure("Expected direct navigation before an open tab")
        }
        precondition(openURLAction.url.absoluteString == openGitHub.url)
        precondition(model.results.dropFirst().first == .openTab(openGitHub))
        model.submit(opensInNewTab: true)
        precondition(navigations.last?.0 == openGitHub.url)
        precondition(navigations.last?.1 == true)

        let normalized = HistoryStore.canonicalURL(
            for: "HTTPS://Example.com/page?utm_source=test&id=7#section"
        )
        precondition(normalized == "https://example.com/page?id=7")

        // Every non-empty input has to produce somewhere to go. Returning nil
        // means the Return key silently does nothing, which is the one outcome
        // the user cannot see or recover from.
        let mustResolve = [
            "github.com", "asdfqwerzxcv.invalid", "localhost:3000",
            "127.0.0.1:8080", "hello world", "http://", "测试",
            "不存在的网站.com", "a b.com", "example.com/路径", "g swift"
        ]
        for input in mustResolve {
            precondition(
                DestinationParser.destination(for: input) != nil,
                "no destination for \(input)"
            )
        }
        precondition(DestinationParser.destination(for: "   ") == nil)
        precondition(
            DestinationParser.resolution(for: "hello world")?.kind
                == .search(engine: "Google", query: "hello world")
        )
        precondition(DestinationParser.resolution(for: "github.com")?.kind == .open)
        precondition(
            DestinationParser.resolution(for: "gh safari adapter")?.kind
                == .search(engine: "GitHub", query: "safari adapter")
        )

        // Loopback must not be forced onto https, and must not be mistaken for
        // a URL whose scheme is "localhost".
        precondition(
            DestinationParser.destination(for: "localhost:3000")?.absoluteString
                == "http://localhost:3000"
        )
        precondition(
            DestinationParser.destination(for: "127.0.0.1:8080")?.absoluteString
                == "http://127.0.0.1:8080"
        )
        // A bare scheme has nowhere to go, so it should search instead.
        precondition(
            DestinationParser.destination(for: "http://")?.host == "www.google.com"
        )
        // A real URL still wins over search.
        precondition(
            DestinationParser.destination(for: "https://example.com/x")?.absoluteString
                == "https://example.com/x"
        )
        // Non-resolving hosts are still opened, so Safari can report the failure.
        precondition(
            DestinationParser.destination(for: "asdfqwerzxcv.invalid")?.absoluteString
                == "https://asdfqwerzxcv.invalid"
        )

        print("Command bar history smoke tests passed")
    }
}
