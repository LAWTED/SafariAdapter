import AppKit
import Carbon
import SwiftUI

enum CommandBarMaterial: String, CaseIterable, Hashable {
    case oldHUD
    case popoverBlur
    case liquidGlass

    var title: String {
        switch self {
        case .oldHUD: "Old HUD · Original"
        case .popoverBlur: "Popover Blur"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

enum CommandResult: Identifiable, Equatable {
    case openTab(SafariTab)
    case history(HistoryEntry)

    var id: String {
        switch self {
        case .openTab(let tab): "tab:\(tab.id)"
        case .history(let entry): "history:\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .openTab(let tab): tab.title
        case .history(let entry): entry.title
        }
    }

    var url: String {
        switch self {
        case .openTab(let tab): tab.url
        case .history(let entry): entry.url
        }
    }

    var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

@MainActor
final class CommandBarModel: ObservableObject {
    static let searchHeight: CGFloat = 68
    static let resultsSeparatorHeight: CGFloat = 1
    static let resultsTopPadding: CGFloat = 4
    static let resultHeight: CGFloat = 40
    static let resultsBottomPadding: CGFloat = 6
    static let maximumResults = 4

    @Published var text: String
    @Published private(set) var results: [CommandResult] = []
    @Published private(set) var selectedResultIndex: Int?
    @Published private(set) var activeShortcutName: String?
    @Published var focusRequest = 0

    private var openTabs: [SafariTab]
    private let historyEntries: [HistoryEntry]
    private let navigate: (String, Bool) -> Void
    private let activateTab: (SafariTab) -> Void
    private let dismiss: () -> Void
    private let layoutChanged: (CGFloat) -> Void
    private var hasEdited = false

    var contentHeight: CGFloat {
        guard !results.isEmpty else { return Self.searchHeight }
        return Self.searchHeight
            + Self.resultsSeparatorHeight
            + Self.resultsTopPadding
            + CGFloat(results.count) * Self.resultHeight
            + Self.resultsBottomPadding
    }

    init(
        initialURL: String,
        openTabs: [SafariTab],
        historyEntries: [HistoryEntry] = [],
        navigate: @escaping (String, Bool) -> Void,
        activateTab: @escaping (SafariTab) -> Void,
        dismiss: @escaping () -> Void,
        layoutChanged: @escaping (CGFloat) -> Void
    ) {
        text = initialURL
        self.openTabs = openTabs
        self.historyEntries = historyEntries
        self.navigate = navigate
        self.activateTab = activateTab
        self.dismiss = dismiss
        self.layoutChanged = layoutChanged
    }

    /// Fills in what Safari reported after the panel was already on screen.
    /// Anything the user has already typed wins — the answer can arrive a few
    /// frames late and must never overwrite a keystroke.
    func applySafariContext(currentURL: String, openTabs: [SafariTab]) {
        self.openTabs = openTabs

        if !hasEdited, text.isEmpty, !currentURL.isEmpty {
            text = currentURL
            focusRequest += 1
        }

        guard hasEdited else { return }
        refreshResults()
        layoutChanged(contentHeight)
    }

    func textDidChange(_ value: String) {
        text = value
        hasEdited = true
        activeShortcutName = SearchShortcut.matching(value)?.shortcut.name
        refreshResults()
        layoutChanged(contentHeight)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        guard let selectedResultIndex else {
            self.selectedResultIndex = offset >= 0 ? 0 : results.count - 1
            return
        }
        self.selectedResultIndex = (
            selectedResultIndex + offset + results.count
        ) % results.count
    }

    func submit(opensInNewTab: Bool) {
        guard let selectedResult else {
            navigate(text, opensInNewTab)
            return
        }

        switch selectedResult {
        case .openTab(let tab) where !opensInNewTab:
            activateTab(tab)
        case .openTab(let tab):
            navigate(tab.url, true)
        case .history(let entry):
            navigate(entry.url, opensInNewTab)
        }
    }

    func activate(_ result: CommandResult) {
        switch result {
        case .openTab(let tab): activateTab(tab)
        case .history(let entry): navigate(entry.url, false)
        }
    }

    func cancel() {
        dismiss()
    }

    private var selectedResult: CommandResult? {
        guard let selectedResultIndex, results.indices.contains(selectedResultIndex) else {
            return nil
        }
        return results[selectedResultIndex]
    }

    private func refreshResults() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            hasEdited,
            query.count >= 2,
            SearchShortcut.matching(query) == nil
        else {
            results = []
            selectedResultIndex = nil
            return
        }

        let normalizedQuery = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let rankedTabs = openTabs
            .compactMap { tab -> (CommandResult, Int, Int)? in
                guard let score = matchScore(
                    title: tab.title,
                    url: tab.url,
                    normalizedQuery: normalizedQuery,
                    tokens: tokens
                ) else { return nil }
                return (.openTab(tab), score, tab.index)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 < rhs.1
            }

        let openURLs = Set(openTabs.compactMap { HistoryStore.canonicalURL(for: $0.url) })
        let rankedHistory = historyEntries
            .filter { !openURLs.contains($0.id) }
            .compactMap { entry -> (CommandResult, Int, Date, Int)? in
                guard let score = matchScore(
                    title: entry.title,
                    url: entry.url,
                    normalizedQuery: normalizedQuery,
                    tokens: tokens
                ) else { return nil }
                return (.history(entry), score, entry.lastVisited, entry.visitCount)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.3 != rhs.3 { return lhs.3 > rhs.3 }
                return lhs.2 > rhs.2
            }

        let combined = rankedTabs.map { ($0.0, $0.1) }
            + rankedHistory.map { ($0.0, $0.1) }
        let visible = Array(combined.prefix(Self.maximumResults))
        results = visible.map(\.0)

        guard let first = visible.first else {
            selectedResultIndex = nil
            return
        }
        switch first.0 {
        case .openTab:
            selectedResultIndex = 0
        case .history:
            // A loose substring remains available with ↓, but does not hijack
            // Return away from a normal web search.
            selectedResultIndex = first.1 <= 2 ? 0 : nil
        }
    }

    private func matchScore(
        title rawTitle: String,
        url rawURL: String,
        normalizedQuery: String,
        tokens: [String]
    ) -> Int? {
        let title = rawTitle
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let url = rawURL.lowercased()
        let host = URL(string: rawURL)?.host?.lowercased() ?? ""
        let searchable = "\(title) \(host) \(url)"
        guard tokens.allSatisfy(searchable.contains) else { return nil }

        if title == normalizedQuery || host == normalizedQuery { return 0 }
        if title.hasPrefix(normalizedQuery) { return 1 }
        if host.hasPrefix(normalizedQuery) { return 2 }
        if title.contains(normalizedQuery) { return 3 }
        return 4
    }
}

struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel
    @Environment(\.colorScheme) private var colorScheme
    let material: CommandBarMaterial
    let visibleHeight: CGFloat

    private enum Palette {
        static let cornerRadius: CGFloat = 22
    }

    var body: some View {
        switch material {
        case .oldHUD:
            content
                .frame(height: visibleHeight, alignment: .top)
                .background {
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        Color.black.opacity(0.12)
                    }
                    .clipShape(containerShape)
                    .overlay {
                        containerShape.stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
                }
                .preferredColorScheme(.dark)
        case .popoverBlur:
            content
                .frame(height: visibleHeight, alignment: .top)
                .background {
                    VisualEffectView(material: .popover, blendingMode: .behindWindow)
                        .clipShape(containerShape)
                        .overlay {
                            containerShape.stroke(Color.white.opacity(0.13), lineWidth: 1)
                        }
                }
        case .liquidGlass:
            liquidGlassContent
        }
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var liquidGlassContent: some View {
        if #available(macOS 26.0, *) {
            content
                .frame(height: visibleHeight, alignment: .top)
                .glassEffect(
                    .regular.tint(
                        colorScheme == .dark
                            ? Color.black.opacity(0.22)
                            : Color.white.opacity(0.16)
                    ),
                    in: .rect(cornerRadius: Palette.cornerRadius)
                )
        } else {
            content
                .frame(height: visibleHeight, alignment: .top)
                .background(
                    Color(red: 0.11, green: 0.11, blue: 0.14),
                    in: containerShape
                )
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchField

            if !model.results.isEmpty {
                commandResults
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            AutoSelectingTextField(
                text: $model.text,
                focusRequest: model.focusRequest,
                onTextChange: model.textDidChange,
                onSubmit: model.submit,
                onMoveSelection: model.moveSelection,
                onCancel: model.cancel
            )
            .frame(height: 34)

            if let shortcutName = model.activeShortcutName {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(shortcutName)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: CommandBarModel.searchHeight)
    }

    private var commandResults: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: CommandBarModel.resultsSeparatorHeight)
                .padding(.horizontal, 20)
                .padding(.bottom, CommandBarModel.resultsTopPadding)

            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                Button {
                    model.activate(result)
                } label: {
                    CommandResultRow(
                        result: result,
                        isSelected: index == model.selectedResultIndex
                    )
                }
                .buttonStyle(.plain)
                .frame(height: CommandBarModel.resultHeight)
            }
        }
        .padding(.bottom, CommandBarModel.resultsBottomPadding)
    }
}

private struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.primary.opacity(isSelected ? 0.58 : 0))
                .frame(width: 2, height: 16)

            Image(systemName: resultIcon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 18)

            Text(result.title.isEmpty ? result.host : result.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .layoutPriority(1)

            Text(result.host)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 10)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else if case .history(let entry) = result {
                Text(entry.lastVisited, style: .relative)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    private var resultIcon: String {
        switch result {
        case .openTab: "rectangle.stack"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct AutoSelectingTextField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onTextChange: (String) -> Void
    let onSubmit: (Bool) -> Void
    let onMoveSelection: (Int) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.delegate = context.coordinator
        field.onCommandReturn = { onSubmit(true) }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "Search or enter URL"
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        context.coordinator.parent = self
        field.onCommandReturn = { onSubmit(true) }
        if field.stringValue != text {
            field.stringValue = text
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoSelectingTextField
        var lastFocusRequest = -1

        init(parent: AutoSelectingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange(field.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(false)
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(true)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class CommandTextField: NSTextField {
    var onCommandReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == UInt16(kVK_Return)
            || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturn, flags.contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
