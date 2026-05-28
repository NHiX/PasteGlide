import Foundation

public struct ClipboardSearchQuery: Equatable {
    public let text: String
    public let kind: ClipboardKind?
    public let pinned: Bool?
    public let createdAfter: Date?

    public init(text: String, kind: ClipboardKind?, pinned: Bool?, createdAfter: Date?) {
        self.text = text
        self.kind = kind
        self.pinned = pinned
        self.createdAfter = createdAfter
    }
}

public struct ClipboardSearch {
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func parse(_ query: String) -> ClipboardSearchQuery {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var terms: [String] = []
        var kind: ClipboardKind?
        var pinned: Bool?
        var createdAfter: Date?

        for token in normalizedQuery.split(separator: " ") {
            if token.hasPrefix("type:") {
                let value = token.dropFirst("type:".count)
                kind = ClipboardKind.allCases.first { $0.rawValue == value || $0.title.lowercased() == value }
            } else if token.hasPrefix("pinned:") {
                let value = token.dropFirst("pinned:".count)
                pinned = value == "true" || value == "yes" || value == "1"
            } else if token.hasPrefix("after:") {
                let value = String(token.dropFirst("after:".count))
                createdAfter = relativeCutoff(from: value)
            } else {
                terms.append(String(token))
            }
        }

        return ClipboardSearchQuery(
            text: terms.joined(separator: " "),
            kind: kind,
            pinned: pinned,
            createdAfter: createdAfter
        )
    }

    public func filter(
        _ items: [ClipboardItem],
        rawQuery: String,
        showsPinnedOnly: Bool,
        selectedKindFilter: ClipboardKind?
    ) -> [ClipboardItem] {
        let search = parse(rawQuery)
        return items.filter { item in
            matches(
                item,
                query: search,
                showsPinnedOnly: showsPinnedOnly,
                selectedKindFilter: selectedKindFilter
            )
        }
    }

    public func matches(
        _ item: ClipboardItem,
        query: ClipboardSearchQuery,
        showsPinnedOnly: Bool = false,
        selectedKindFilter: ClipboardKind? = nil
    ) -> Bool {
        if showsPinnedOnly, !item.isPinned {
            return false
        }
        if let selectedKindFilter, item.kind != selectedKindFilter {
            return false
        }
        if let kind = query.kind, item.kind != kind {
            return false
        }
        if let pinned = query.pinned, item.isPinned != pinned {
            return false
        }
        if let cutoff = query.createdAfter, item.createdAt < cutoff {
            return false
        }
        guard !query.text.isEmpty else {
            return true
        }
        return item.searchHaystack.contains(query.text)
    }

    private func relativeCutoff(from value: String) -> Date? {
        guard value.count >= 2, let amount = Int(value.dropLast()) else { return nil }
        let unit = value.suffix(1)
        let seconds: TimeInterval
        switch unit {
        case "h": seconds = TimeInterval(amount * 60 * 60)
        case "d": seconds = TimeInterval(amount * 24 * 60 * 60)
        case "w": seconds = TimeInterval(amount * 7 * 24 * 60 * 60)
        default: return nil
        }
        return now().addingTimeInterval(-seconds)
    }
}
