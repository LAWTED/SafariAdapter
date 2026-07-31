import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var url: String
    var lastVisited: Date
    var visitCount: Int

    var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

@MainActor
final class HistoryStore {
    private enum Limits {
        static let maximumEntries = 2_000
        static let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    }

    private static let enabledDefaultsKey = "localHistoryEnabled"
    private let fileURL: URL
    private(set) var entries: [HistoryEntry] = []

    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.enabledDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
    }

    func record(title: String, url: String, at date: Date = Date()) {
        guard isEnabled, let canonicalURL = Self.canonicalURL(for: url) else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = entries.firstIndex(where: { $0.id == canonicalURL }) {
            entries[index].title = cleanTitle.isEmpty ? entries[index].title : cleanTitle
            entries[index].url = url
            entries[index].lastVisited = date
            entries[index].visitCount += 1
        } else {
            entries.append(
                HistoryEntry(
                    id: canonicalURL,
                    title: cleanTitle,
                    url: url,
                    lastVisited: date,
                    visitCount: 1
                )
            )
        }

        prune(referenceDate: date)
        save()
    }

    func clear() {
        entries = []
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            NSLog("SafariAdapter could not clear local history: %@", error.localizedDescription)
        }
    }

    static func canonicalURL(for rawURL: String) -> String? {
        guard
            var components = URLComponents(string: rawURL),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if let queryItems = components.queryItems {
            let trackingNames: Set<String> = ["fbclid", "gclid", "mc_cid", "mc_eid"]
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingNames.contains(name)
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        guard let normalized = components.url?.absoluteString else { return nil }
        return normalized
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
            prune(referenceDate: Date())
        } catch {
            NSLog("SafariAdapter could not read local history: %@", error.localizedDescription)
            entries = []
        }
    }

    private func prune(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-Limits.retentionInterval)
        entries = entries
            .filter { $0.lastVisited >= cutoff }
            .sorted { $0.lastVisited > $1.lastVisited }
        if entries.count > Limits.maximumEntries {
            entries.removeLast(entries.count - Limits.maximumEntries)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SafariAdapter could not save local history: %@", error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("SafariAdapter", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
