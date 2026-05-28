import Foundation

public struct ClipboardArchive: Codable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let items: [ClipboardArchiveItem]

    public init(version: Int = Self.currentVersion, items: [ClipboardArchiveItem]) {
        self.version = version
        self.items = items
    }

    public init(clipboardItems: [ClipboardItem]) {
        self.version = Self.currentVersion
        self.items = clipboardItems.map(ClipboardArchiveItem.init)
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
            self.items = try container.decodeIfPresent([ClipboardArchiveItem].self, forKey: .items) ?? []
        } else {
            var legacyContainer = try decoder.unkeyedContainer()
            var legacyItems: [ClipboardArchiveItem] = []
            while !legacyContainer.isAtEnd {
                legacyItems.append(try legacyContainer.decode(ClipboardArchiveItem.self))
            }
            self.version = Self.currentVersion
            self.items = legacyItems
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(items, forKey: .items)
    }

    public func clipboardItems() -> [ClipboardItem] {
        items.enumerated().map { offset, archiveItem in
            archiveItem.clipboardItem(fallbackID: Int64(offset + 1))
        }
    }

    public func encoded(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> ClipboardArchive {
        try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case items
    }
}

public struct ClipboardArchiveItem: Codable, Equatable {
    public let id: Int64?
    public let kind: ClipboardKind
    public let content: String
    public let preview: String
    public let ocrText: String
    public let isPinned: Bool
    public let createdAt: TimeInterval
    public let contentHash: String

    public init(
        id: Int64? = nil,
        kind: ClipboardKind,
        content: String,
        preview: String,
        ocrText: String,
        isPinned: Bool,
        createdAt: TimeInterval,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.preview = preview
        self.ocrText = ocrText
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.contentHash = contentHash
    }

    public init(_ item: ClipboardItem) {
        self.id = item.id
        self.kind = item.kind
        self.content = item.content
        self.preview = item.preview
        self.ocrText = item.ocrText
        self.isPinned = item.isPinned
        self.createdAt = item.createdAt.timeIntervalSince1970
        self.contentHash = item.contentHash
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.kind = try container.decodeIfPresent(ClipboardKind.self, forKey: .kind) ?? .text
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? content
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        self.contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
    }

    public func clipboardItem(fallbackID: Int64) -> ClipboardItem {
        ClipboardItem(
            id: id ?? fallbackID,
            kind: kind,
            content: content,
            preview: preview,
            ocrText: ocrText,
            isPinned: isPinned,
            createdAt: Date(timeIntervalSince1970: createdAt),
            contentHash: contentHash
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case content
        case preview
        case ocrText
        case isPinned
        case createdAt
        case contentHash
    }
}
