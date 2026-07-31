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

        model.textDidChange("SafariAdapter")
        precondition(model.results == [.openTab(openGitHub)])
        model.submit(opensInNewTab: false)
        precondition(activatedTab == openGitHub)

        model.submit(opensInNewTab: true)
        precondition(navigations.last?.0 == openGitHub.url)
        precondition(navigations.last?.1 == true)

        model.textDidChange("Safari Services")
        guard case .history(let matchedHistory)? = model.results.first else {
            preconditionFailure("Expected a history result")
        }
        precondition(matchedHistory.url.contains("developer.apple.com"))
        model.submit(opensInNewTab: false)
        precondition(navigations.last?.0 == matchedHistory.url)
        precondition(navigations.last?.1 == false)

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
