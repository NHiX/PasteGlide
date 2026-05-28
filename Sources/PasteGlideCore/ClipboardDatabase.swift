import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import PasteGlideShared
import SQLite3
import UniformTypeIdentifiers
import Vision

public final class ClipboardDatabase {
    private var db: OpaquePointer?
    public let path: String
    private let imageDirectory: URL

    public init(path explicitPath: String? = nil) throws {
        if let explicitPath {
            self.path = explicitPath
            self.imageDirectory = URL(fileURLWithPath: explicitPath).deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true)
        } else {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PasteGlide", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.imageDirectory = directory.appendingPathComponent("Images", isDirectory: true)
            let databaseURL = directory.appendingPathComponent("history.sqlite")
            let legacyURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(["Clip", "Card"].joined())
                .appendingPathComponent("history.sqlite")
            if !FileManager.default.fileExists(atPath: databaseURL.path),
               FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.copyItem(at: legacyURL, to: databaseURL)
            }
            self.path = directory.appendingPathComponent("history.sqlite").path
        }
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw databaseError("Impossible d'ouvrir SQLite")
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            content TEXT NOT NULL,
            preview TEXT NOT NULL,
            ocr_text TEXT NOT NULL DEFAULT '',
            ocr_attempted INTEGER NOT NULL DEFAULT 0,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            content_hash TEXT NOT NULL,
            content_path TEXT NOT NULL DEFAULT '',
            thumbnail TEXT NOT NULL DEFAULT ''
        );
        """)
        try addColumnIfNeeded(table: "clipboard_items", column: "ocr_text", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(table: "clipboard_items", column: "ocr_attempted", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "clipboard_items", column: "is_pinned", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "clipboard_items", column: "content_path", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(table: "clipboard_items", column: "thumbnail", definition: "TEXT NOT NULL DEFAULT ''")
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(is_pinned DESC, created_at DESC);")
    }

    deinit {
        sqlite3_close(db)
    }

    public func latestHash() -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT content_hash FROM clipboard_items ORDER BY created_at DESC LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    public func insert(kind: ClipboardKind, content: String, preview: String, ocrText: String = "", ocrAttempted: Bool = false, hash: String) throws {
        guard latestHash() != hash else { return }

        let storedImage = storeImageIfNeeded(kind: kind, content: content, hash: hash)
        let storedContent = storedImage == nil ? content : ""
        let sql = "INSERT INTO clipboard_items (kind, content, preview, ocr_text, ocr_attempted, created_at, content_hash, content_path, thumbnail) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation INSERT impossible")
        }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, storedContent, -1, sqliteTransient())
        sqlite3_bind_text(statement, 3, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 4, ocrText, -1, sqliteTransient())
        sqlite3_bind_int(statement, 5, ocrAttempted ? 1 : 0)
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 7, hash, -1, sqliteTransient())
        sqlite3_bind_text(statement, 8, storedImage?.path ?? "", -1, sqliteTransient())
        sqlite3_bind_text(statement, 9, storedImage?.thumbnail ?? "", -1, sqliteTransient())

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Insertion impossible")
        }

        try trimHistory(limit: AppSettings.shared.historyLimit, retentionDays: AppSettings.shared.retentionDays)
    }

    public func fetchRecent() -> [ClipboardItem] {
        let sql = """
        SELECT id, kind,
               CASE WHEN kind = ? THEN thumbnail ELSE content END,
               preview, ocr_text, is_pinned, created_at, content_hash
        FROM clipboard_items
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, ClipboardKind.image.rawValue, -1, sqliteTransient())
        sqlite3_bind_int(statement, 2, Int32(AppSettings.shared.historyLimit))

        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let kindRaw = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ClipboardKind.text.rawValue
            let content = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let preview = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let ocrText = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let isPinned = sqlite3_column_int(statement, 5) == 1
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            let contentHash = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            items.append(
                ClipboardItem(
                    id: id,
                    kind: ClipboardKind(rawValue: kindRaw) ?? .text,
                    content: content,
                    preview: preview,
                    ocrText: ocrText,
                    isPinned: isPinned,
                    createdAt: createdAt,
                    contentHash: contentHash
                )
            )
        }
        return items
    }

    public func content(for item: ClipboardItem) -> String {
        content(forID: item.id) ?? item.content
    }

    public func content(forID id: Int64) -> String? {
        let sql = "SELECT content, content_path FROM clipboard_items WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let content = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let contentPath = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        if !contentPath.isEmpty,
           let data = try? Data(contentsOf: URL(fileURLWithPath: contentPath)) {
            return data.base64EncodedString()
        }
        return content
    }

    func fetchImagesMissingOCR() -> [ClipboardItem] {
        let sql = """
        SELECT id, kind, content, preview, ocr_text, is_pinned, created_at, content_hash, content_path
        FROM clipboard_items
        WHERE kind = ? AND ocr_attempted = 0
        ORDER BY created_at DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, ClipboardKind.image.rawValue, -1, sqliteTransient())
        sqlite3_bind_int(statement, 2, Int32(AppSettings.shared.historyLimit))

        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let kindRaw = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ClipboardKind.image.rawValue
            let content = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let preview = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let ocrText = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let isPinned = sqlite3_column_int(statement, 5) == 1
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            let contentHash = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            let contentPath = sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? ""
            let resolvedContent: String
            if content.isEmpty, !contentPath.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: contentPath)) {
                resolvedContent = data.base64EncodedString()
            } else {
                resolvedContent = content
            }
            items.append(
                ClipboardItem(
                    id: id,
                    kind: ClipboardKind(rawValue: kindRaw) ?? .image,
                    content: resolvedContent,
                    preview: preview,
                    ocrText: ocrText,
                    isPinned: isPinned,
                    createdAt: createdAt,
                    contentHash: contentHash
                )
            )
        }
        return items
    }

    private func storeImageIfNeeded(kind: ClipboardKind, content: String, hash: String) -> (path: String, thumbnail: String)? {
        guard kind == .image,
              let data = Data(base64Encoded: content),
              let image = NSImage(data: data) else {
            return nil
        }
        let fileURL = imageDirectory.appendingPathComponent("\(hash).png")
        try? data.write(to: fileURL, options: .atomic)
        return (fileURL.path, image.thumbnailPNGBase64() ?? "")
    }

    private func removeImageFile(forID id: Int64) {
        let sql = "SELECT content_path FROM clipboard_items WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else { return }
        let path = String(cString: text)
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func removeImageFiles(whereClause: String) {
        let sql = "SELECT content_path FROM clipboard_items WHERE \(whereClause) AND content_path != '';"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            try? FileManager.default.removeItem(atPath: String(cString: text))
        }
    }

    func updateOCR(for id: Int64, preview: String, ocrText: String) throws {
        let sql = "UPDATE clipboard_items SET preview = ?, ocr_text = ?, ocr_attempted = 1 WHERE id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation UPDATE OCR impossible")
        }

        sqlite3_bind_text(statement, 1, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, ocrText, -1, sqliteTransient())
        sqlite3_bind_int64(statement, 3, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Mise à jour OCR impossible")
        }
    }

    func updateOCR(forHash hash: String, preview: String, ocrText: String) {
        let sql = "UPDATE clipboard_items SET preview = ?, ocr_text = ?, ocr_attempted = 1 WHERE content_hash = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, ocrText, -1, sqliteTransient())
        sqlite3_bind_text(statement, 3, hash, -1, sqliteTransient())
        sqlite3_step(statement)
    }

    public func delete(id: Int64) throws {
        removeImageFile(forID: id)
        let sql = "DELETE FROM clipboard_items WHERE id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation DELETE impossible")
        }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Suppression impossible")
        }
    }

    public func delete(kind: ClipboardKind) throws {
        if kind == .image {
            removeImageFiles(whereClause: "kind = '\(ClipboardKind.image.rawValue)'")
        }
        let sql = "DELETE FROM clipboard_items WHERE kind = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation DELETE type impossible")
        }
        sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Suppression du type impossible")
        }
    }

    public func deleteAll() throws {
        removeImageFiles(whereClause: "1 = 1")
        try execute("DELETE FROM clipboard_items;")
    }

    public func deleteOlderThan(days: Int) throws {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60)).timeIntervalSince1970
        removeImageFiles(whereClause: "is_pinned = 0 AND created_at < \(cutoff)")
        try execute("DELETE FROM clipboard_items WHERE is_pinned = 0 AND created_at < \(cutoff);")
    }

    public func setPinned(id: Int64, isPinned: Bool) throws {
        let sql = "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation PIN impossible")
        }
        sqlite3_bind_int(statement, 1, isPinned ? 1 : 0)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Épinglage impossible")
        }
    }

    func applyRetention() throws {
        try trimHistory(limit: AppSettings.shared.historyLimit, retentionDays: AppSettings.shared.retentionDays)
    }

    func exportJSON(to destinationURL: URL) throws {
        let sql = "SELECT kind, content, preview, ocr_text, created_at, content_hash, is_pinned, content_path FROM clipboard_items ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Export JSON impossible")
        }

        var items: [ClipboardArchiveItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let kind = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ClipboardKind.text.rawValue
            var content = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let contentPath = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            if content.isEmpty, !contentPath.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: contentPath)) {
                content = data.base64EncodedString()
            }
            items.append(
                ClipboardArchiveItem(
                    kind: ClipboardKind(rawValue: kind) ?? .text,
                    content: content,
                    preview: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "",
                    ocrText: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                    isPinned: sqlite3_column_int(statement, 6) == 1,
                    createdAt: sqlite3_column_double(statement, 4),
                    contentHash: sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                )
            )
        }

        let data = try ClipboardArchive(items: items).encoded()
        try data.write(to: destinationURL, options: .atomic)
    }

    func importJSON(from sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let archive = try ClipboardArchive.decoded(from: data)
        for item in archive.items {
            guard !item.content.isEmpty else { continue }
            let hash = item.contentHash.isEmpty ? hashContent("\(item.kind.rawValue):\(item.content)") : item.contentHash
            try insertImported(kind: item.kind.rawValue, content: item.content, preview: item.preview, ocrText: item.ocrText, createdAt: item.createdAt, hash: hash, isPinned: item.isPinned)
        }
        try applyRetention()
    }

    func importItems(from sourcePath: String) throws {
        var sourceDB: OpaquePointer?
        guard sqlite3_open(sourcePath, &sourceDB) == SQLITE_OK else {
            throw databaseError("Import SQLite impossible")
        }
        defer { sqlite3_close(sourceDB) }

        let sql = "SELECT kind, content, preview, COALESCE(ocr_text, ''), created_at, content_hash, COALESCE(is_pinned, 0) FROM clipboard_items ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(sourceDB, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Lecture import impossible")
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let kind = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ClipboardKind.text.rawValue
            let content = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let preview = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let ocrText = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let createdAt = sqlite3_column_double(statement, 4)
            let hash = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? hashContent("\(kind):\(content)")
            let isPinned = sqlite3_column_int(statement, 6) == 1
            try insertImported(kind: kind, content: content, preview: preview, ocrText: ocrText, createdAt: createdAt, hash: hash, isPinned: isPinned)
        }
        try applyRetention()
    }

    private func insertImported(kind: String, content: String, preview: String, ocrText: String, createdAt: Double, hash: String, isPinned: Bool) throws {
        guard !content.isEmpty else { return }
        let clipboardKind = ClipboardKind(rawValue: kind) ?? .text
        let storedImage = storeImageIfNeeded(kind: clipboardKind, content: content, hash: hash)
        let storedContent = storedImage == nil ? content : ""
        let sql = """
        INSERT INTO clipboard_items (kind, content, preview, ocr_text, ocr_attempted, is_pinned, created_at, content_hash, content_path, thumbnail)
        SELECT ?, ?, ?, ?, 1, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (SELECT 1 FROM clipboard_items WHERE content_hash = ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation import impossible")
        }
        sqlite3_bind_text(statement, 1, kind, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, storedContent, -1, sqliteTransient())
        sqlite3_bind_text(statement, 3, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 4, ocrText, -1, sqliteTransient())
        sqlite3_bind_int(statement, 5, isPinned ? 1 : 0)
        sqlite3_bind_double(statement, 6, createdAt)
        sqlite3_bind_text(statement, 7, hash, -1, sqliteTransient())
        sqlite3_bind_text(statement, 8, storedImage?.path ?? "", -1, sqliteTransient())
        sqlite3_bind_text(statement, 9, storedImage?.thumbnail ?? "", -1, sqliteTransient())
        sqlite3_bind_text(statement, 10, hash, -1, sqliteTransient())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Import impossible")
        }
    }

    private func trimHistory(limit: Int, retentionDays: Int) throws {
        try execute("""
        DELETE FROM clipboard_items
        WHERE is_pinned = 0 AND id NOT IN (
            SELECT id FROM clipboard_items WHERE is_pinned = 0 ORDER BY created_at DESC LIMIT \(limit)
        );
        """)
        if retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60)).timeIntervalSince1970
            try execute("DELETE FROM clipboard_items WHERE is_pinned = 0 AND created_at < \(cutoff);")
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "Erreur SQLite inconnue"
            sqlite3_free(error)
            throw databaseError(message)
        }
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Inspection du schéma impossible")
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let columnName = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            if columnName == column {
                return
            }
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func databaseError(_ message: String) -> NSError {
        NSError(domain: "PasteGlide.SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
