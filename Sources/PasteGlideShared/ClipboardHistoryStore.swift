import Foundation

public protocol ClipboardHistoryStore {
    func loadItems() throws -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem]) throws
    func insert(kind: ClipboardKind, content: String, preview: String, ocrText: String, isPinned: Bool, contentHash: String?) throws -> ClipboardItem
    func delete(id: Int64) throws
    func deleteAll() throws
    func setPinned(id: Int64, isPinned: Bool) throws
    func importArchive(_ archive: ClipboardArchive) throws
    func exportArchive() throws -> ClipboardArchive
}

public final class JSONClipboardHistoryStore: ClipboardHistoryStore {
    public let fileURL: URL
    public var historyLimit: Int
    public var retentionDays: Int
    private let now: () -> Date

    public init(fileURL: URL, historyLimit: Int = 100, retentionDays: Int = 0, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.historyLimit = PasteGlideSettingsRules.normalizedHistoryLimit(historyLimit)
        self.retentionDays = PasteGlideSettingsRules.normalizedRetentionDays(retentionDays)
        self.now = now
    }

    public func loadItems() throws -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try ClipboardArchive.decoded(from: data).clipboardItems()
    }

    public func saveItems(_ items: [ClipboardItem]) throws {
        let normalized = normalizedItems(items)
        try writeArchive(ClipboardArchive(clipboardItems: normalized))
    }

    @discardableResult
    public func insert(
        kind: ClipboardKind,
        content: String,
        preview: String,
        ocrText: String = "",
        isPinned: Bool = false,
        contentHash: String? = nil
    ) throws -> ClipboardItem {
        let hash = contentHash ?? Self.hash(kind: kind, content: content)
        guard !content.isEmpty else {
            throw ClipboardHistoryStoreError.emptyContent
        }

        var items = try loadItems()
        items.removeAll { $0.contentHash == hash }
        let item = ClipboardItem(
            id: nextID(in: items),
            kind: kind,
            content: content,
            preview: preview.isEmpty ? content : preview,
            ocrText: ocrText,
            isPinned: isPinned,
            createdAt: now(),
            contentHash: hash
        )
        items.insert(item, at: 0)
        try saveItems(items)
        return item
    }

    public func delete(id: Int64) throws {
        var items = try loadItems()
        items.removeAll { $0.id == id }
        try saveItems(items)
    }

    public func deleteAll() throws {
        try saveItems([])
    }

    public func setPinned(id: Int64, isPinned: Bool) throws {
        let items = try loadItems().map { item in
            guard item.id == id else { return item }
            return ClipboardItem(
                id: item.id,
                kind: item.kind,
                content: item.content,
                preview: item.preview,
                ocrText: item.ocrText,
                isPinned: isPinned,
                createdAt: item.createdAt,
                contentHash: item.contentHash
            )
        }
        try saveItems(items)
    }

    public func importArchive(_ archive: ClipboardArchive) throws {
        var items = try loadItems()
        for item in archive.clipboardItems() {
            guard !item.content.isEmpty else { continue }
            let hash = item.contentHash.isEmpty ? Self.hash(kind: item.kind, content: item.content) : item.contentHash
            items.removeAll { $0.contentHash == hash }
            items.append(
                ClipboardItem(
                    id: nextID(in: items),
                    kind: item.kind,
                    content: item.content,
                    preview: item.preview.isEmpty ? item.content : item.preview,
                    ocrText: item.ocrText,
                    isPinned: item.isPinned,
                    createdAt: item.createdAt,
                    contentHash: hash
                )
            )
        }
        try saveItems(items)
    }

    public func exportArchive() throws -> ClipboardArchive {
        try ClipboardArchive(clipboardItems: loadItems())
    }

    public static func hash(kind: ClipboardKind, content: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(kind.rawValue):\(content)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func normalizedItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let cutoff = retentionDays > 0 ? now().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60)) : nil
        let uniqueItems = deduplicated(items)
        let pinned = uniqueItems
            .filter { $0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
        let unpinned = uniqueItems
            .filter { item in
                guard !item.isPinned else { return false }
                guard let cutoff else { return true }
                return item.createdAt >= cutoff
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(historyLimit)
        return pinned + Array(unpinned)
    }

    private func deduplicated(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var seen: Set<String> = []
        var unique: [ClipboardItem] = []
        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            let hash = item.contentHash.isEmpty ? Self.hash(kind: item.kind, content: item.content) : item.contentHash
            guard !seen.contains(hash) else { continue }
            seen.insert(hash)
            unique.append(
                ClipboardItem(
                    id: item.id,
                    kind: item.kind,
                    content: item.content,
                    preview: item.preview,
                    ocrText: item.ocrText,
                    isPinned: item.isPinned,
                    createdAt: item.createdAt,
                    contentHash: hash
                )
            )
        }
        return unique
    }

    private func nextID(in items: [ClipboardItem]) -> Int64 {
        (items.map(\.id).max() ?? 0) + 1
    }

    private func writeArchive(_ archive: ClipboardArchive) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archive.encoded().write(to: fileURL, options: .atomic)
    }
}

public enum ClipboardHistoryStoreError: Error, Equatable {
    case emptyContent
}
