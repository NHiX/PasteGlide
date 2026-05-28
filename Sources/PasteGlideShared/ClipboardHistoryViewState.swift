import Foundation

public struct ClipboardHistoryStats: Equatable {
    public let total: Int
    public let countsByKind: [ClipboardKind: Int]
    public let latestItemDate: Date?

    public init(total: Int, countsByKind: [ClipboardKind: Int], latestItemDate: Date?) {
        self.total = total
        self.countsByKind = countsByKind
        self.latestItemDate = latestItemDate
    }
}

public struct ClipboardHistoryViewSnapshot: Equatable {
    public let items: [ClipboardItem]
    public let stats: ClipboardHistoryStats
    public let statsLines: [String]
    public let latestItemText: String
    public let isVerticalLayout: Bool
    public let selectedItemID: Int64?

    public init(
        items: [ClipboardItem],
        stats: ClipboardHistoryStats,
        statsLines: [String],
        latestItemText: String,
        isVerticalLayout: Bool,
        selectedItemID: Int64?
    ) {
        self.items = items
        self.stats = stats
        self.statsLines = statsLines
        self.latestItemText = latestItemText
        self.isVerticalLayout = isVerticalLayout
        self.selectedItemID = selectedItemID
    }
}

public struct ClipboardHistoryViewState {
    public var allItems: [ClipboardItem]
    public var searchText: String
    public var showsPinnedOnly: Bool
    public var selectedKindFilter: ClipboardKind?
    public var panelPosition: PanelPosition
    public var selectedIndex: Int

    private let search: ClipboardSearch
    private let formatDate: (Date) -> String

    public init(
        allItems: [ClipboardItem] = [],
        searchText: String = "",
        showsPinnedOnly: Bool = false,
        selectedKindFilter: ClipboardKind? = nil,
        panelPosition: PanelPosition = .bottom,
        selectedIndex: Int = 0,
        search: ClipboardSearch = ClipboardSearch(),
        formatDate: @escaping (Date) -> String
    ) {
        self.allItems = allItems
        self.searchText = searchText
        self.showsPinnedOnly = showsPinnedOnly
        self.selectedKindFilter = selectedKindFilter
        self.panelPosition = panelPosition
        self.selectedIndex = selectedIndex
        self.search = search
        self.formatDate = formatDate
    }

    public func filteredItems() -> [ClipboardItem] {
        search.filter(
            allItems,
            rawQuery: searchText,
            showsPinnedOnly: showsPinnedOnly,
            selectedKindFilter: selectedKindFilter
        )
    }

    public func stats() -> ClipboardHistoryStats {
        let countsByKind = Dictionary(grouping: allItems, by: \.kind).mapValues(\.count)
        let latestDate = allItems.max(by: { $0.createdAt < $1.createdAt })?.createdAt
        return ClipboardHistoryStats(total: allItems.count, countsByKind: countsByKind, latestItemDate: latestDate)
    }

    public func snapshot() -> ClipboardHistoryViewSnapshot {
        let items = filteredItems()
        let stats = stats()
        let clampedIndex = Self.clampedSelectedIndex(selectedIndex, itemCount: items.count)
        return ClipboardHistoryViewSnapshot(
            items: items,
            stats: stats,
            statsLines: statsLines(for: stats, isVertical: panelPosition.isVertical),
            latestItemText: latestItemText(for: stats),
            isVerticalLayout: panelPosition.isVertical,
            selectedItemID: items.indices.contains(clampedIndex) ? items[clampedIndex].id : nil
        )
    }

    public mutating func moveSelection(by delta: Int) {
        selectedIndex = Self.clampedSelectedIndex(selectedIndex + delta, itemCount: filteredItems().count)
    }

    public mutating func selectFirst() {
        selectedIndex = 0
    }

    public mutating func selectLast() {
        selectedIndex = Self.clampedSelectedIndex(Int.max, itemCount: filteredItems().count)
    }

    public mutating func setSearchText(_ value: String) {
        searchText = value
        selectedIndex = Self.clampedSelectedIndex(selectedIndex, itemCount: filteredItems().count)
    }

    public mutating func setKindFilter(_ value: ClipboardKind?) {
        selectedKindFilter = value
        selectedIndex = Self.clampedSelectedIndex(selectedIndex, itemCount: filteredItems().count)
    }

    public mutating func setShowsPinnedOnly(_ value: Bool) {
        showsPinnedOnly = value
        selectedIndex = Self.clampedSelectedIndex(selectedIndex, itemCount: filteredItems().count)
    }

    private func statsLines(for stats: ClipboardHistoryStats, isVertical: Bool) -> [String] {
        let totalText = "\(stats.total) \(stats.total == 1 ? "objet memorise" : "objets memorises")"
        let kindTexts = ClipboardKind.allCases.map { kind in
            "\(kind.title): \(stats.countsByKind[kind, default: 0])"
        }
        guard isVertical else {
            return [([totalText] + kindTexts).joined(separator: " · ")]
        }
        return [
            totalText,
            kindTexts.prefix(3).joined(separator: " · "),
            kindTexts.dropFirst(3).joined(separator: " · ")
        ]
        .filter { !$0.isEmpty }
    }

    private func latestItemText(for stats: ClipboardHistoryStats) -> String {
        guard let latestItemDate = stats.latestItemDate else {
            return "Derniere carte : aucune"
        }
        return "Derniere carte : \(formatDate(latestItemDate))"
    }

    private static func clampedSelectedIndex(_ index: Int, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return min(max(index, 0), itemCount - 1)
    }
}
