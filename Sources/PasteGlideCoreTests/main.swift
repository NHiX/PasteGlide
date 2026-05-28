import Foundation
import PasteGlideCore

enum TestFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.failed(message)
    }
}

func testClassifierDetectsExpectedKinds() throws {
    let classifier = ClipboardClassifier()
    try expect(classifier.classifyString("https://www.youtube.com/watch?v=abc") == .youtube, "YouTube URL should be youtube")
    try expect(classifier.classifyString("https://example.com/page") == .url, "general URL should be url")
    try expect(classifier.classifyString("1234567890") == .number, "digit-only string should be number")
    try expect(classifier.classifyString("Abcdef1!") == .password, "complex short token should be password")
    try expect(classifier.classifyString("Un texte simple") == .text, "plain sentence should be text")
}

func testSearchHaystackUsesOCRButSkipsImageBase64() throws {
    let item = ClipboardItem(
        id: 1,
        kind: .image,
        content: "combinaison",
        preview: "Image 100x100",
        ocrText: "mot reconnu",
        isPinned: false,
        createdAt: Date(),
        contentHash: "hash"
    )

    try expect(item.searchHaystack.contains("mot reconnu"), "OCR text should be searchable")
    try expect(!item.searchHaystack.contains("combinaison"), "image base64/content should not be searched")
}

func testPinnedItemsSurviveRetention() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteGlideTests-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }

    AppSettings.shared.historyLimit = 1
    AppSettings.shared.retentionDays = 0

    let database = try ClipboardDatabase(path: url.path)
    try database.insert(kind: .text, content: "first", preview: "first", hash: "first")
    guard let first = database.fetchRecent().first else {
        throw TestFailure.failed("first item should exist")
    }
    try database.setPinned(id: first.id, isPinned: true)
    try database.insert(kind: .text, content: "second", preview: "second", hash: "second")

    let contents = database.fetchRecent().map(\.content)
    try expect(contents.contains("first"), "pinned item should survive retention")
    try expect(contents.contains("second"), "latest unpinned item should remain")
}

func testImageContentLoadsLazily() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteGlideTests-\(UUID().uuidString).sqlite")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("Images"))
    }

    let database = try ClipboardDatabase(path: url.path)
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/luz8XwAAAABJRU5ErkJggg=="
    try database.insert(kind: .image, content: base64, preview: "Image 1x1", hash: "image-test")
    guard let item = database.fetchRecent().first else {
        throw TestFailure.failed("image item should exist")
    }

    try expect(item.content != base64, "recent image should expose thumbnail instead of original content")
    try expect(database.content(for: item) == base64, "full image content should resolve on demand")
}

let tests: [(String, () throws -> Void)] = [
    ("classifierDetectsExpectedKinds", testClassifierDetectsExpectedKinds),
    ("searchHaystackUsesOCRButSkipsImageBase64", testSearchHaystackUsesOCRButSkipsImageBase64),
    ("pinnedItemsSurviveRetention", testPinnedItemsSurviveRetention),
    ("imageContentLoadsLazily", testImageContentLoadsLazily)
]

for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        print("FAIL \(name): \(error)")
        exit(1)
    }
}
