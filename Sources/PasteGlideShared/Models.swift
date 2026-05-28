import Foundation

public enum ClipboardKind: String, CaseIterable, Codable {
    case youtube
    case url
    case text
    case password
    case number
    case image

    public var title: String {
        switch self {
        case .youtube: "YouTube"
        case .url: "Lien"
        case .text: "Texte"
        case .password: "Mot de passe"
        case .number: "Chiffres"
        case .image: "Image"
        }
    }
}

public struct ClipboardItem: Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipboardKind
    public let content: String
    public let preview: String
    public let ocrText: String
    public let isPinned: Bool
    public let createdAt: Date
    public let contentHash: String

    public init(id: Int64, kind: ClipboardKind, content: String, preview: String, ocrText: String, isPinned: Bool, createdAt: Date, contentHash: String) {
        self.id = id
        self.kind = kind
        self.content = content
        self.preview = preview
        self.ocrText = ocrText
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.contentHash = contentHash
    }

    public var searchHaystack: String {
        let searchableContent = kind == .image ? "" : content
        return [
            kind.title,
            preview,
            searchableContent,
            ocrText
        ]
        .joined(separator: "\n")
        .lowercased()
    }
}
