import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

public final class ClipboardDatabase {
    private var db: OpaquePointer?
    public let path: String

    public init(path explicitPath: String? = nil) throws {
        if let explicitPath {
            self.path = explicitPath
        } else {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PasteGlide", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            content_hash TEXT NOT NULL
        );
        """)
        try addColumnIfNeeded(table: "clipboard_items", column: "ocr_text", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(table: "clipboard_items", column: "ocr_attempted", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "clipboard_items", column: "is_pinned", definition: "INTEGER NOT NULL DEFAULT 0")
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

        let sql = "INSERT INTO clipboard_items (kind, content, preview, ocr_text, ocr_attempted, created_at, content_hash) VALUES (?, ?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation INSERT impossible")
        }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, content, -1, sqliteTransient())
        sqlite3_bind_text(statement, 3, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 4, ocrText, -1, sqliteTransient())
        sqlite3_bind_int(statement, 5, ocrAttempted ? 1 : 0)
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 7, hash, -1, sqliteTransient())

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError("Insertion impossible")
        }

        try trimHistory(limit: AppSettings.shared.historyLimit, retentionDays: AppSettings.shared.retentionDays)
    }

    public func fetchRecent() -> [ClipboardItem] {
        let sql = "SELECT id, kind, content, preview, ocr_text, is_pinned, created_at, content_hash FROM clipboard_items ORDER BY is_pinned DESC, created_at DESC LIMIT ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_int(statement, 1, Int32(AppSettings.shared.historyLimit))

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

    func fetchImagesMissingOCR() -> [ClipboardItem] {
        let sql = """
        SELECT id, kind, content, preview, ocr_text, is_pinned, created_at, content_hash
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
            items.append(
                ClipboardItem(
                    id: id,
                    kind: ClipboardKind(rawValue: kindRaw) ?? .image,
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
        let sql = """
        INSERT INTO clipboard_items (kind, content, preview, ocr_text, ocr_attempted, is_pinned, created_at, content_hash)
        SELECT ?, ?, ?, ?, 1, ?, ?, ?
        WHERE NOT EXISTS (SELECT 1 FROM clipboard_items WHERE content_hash = ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError("Préparation import impossible")
        }
        sqlite3_bind_text(statement, 1, kind, -1, sqliteTransient())
        sqlite3_bind_text(statement, 2, content, -1, sqliteTransient())
        sqlite3_bind_text(statement, 3, preview, -1, sqliteTransient())
        sqlite3_bind_text(statement, 4, ocrText, -1, sqliteTransient())
        sqlite3_bind_int(statement, 5, isPinned ? 1 : 0)
        sqlite3_bind_double(statement, 6, createdAt)
        sqlite3_bind_text(statement, 7, hash, -1, sqliteTransient())
        sqlite3_bind_text(statement, 8, hash, -1, sqliteTransient())
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
