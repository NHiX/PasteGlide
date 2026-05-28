import Foundation
import PasteGlideShared

enum SharedTestFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SharedTestFailure.failed(message)
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

let tests: [(String, () throws -> Void)] = [
    ("sharedClassifierDetectsExpectedKinds", testClassifierDetectsExpectedKinds),
    ("sharedSearchHaystackUsesOCRButSkipsImageBase64", testSearchHaystackUsesOCRButSkipsImageBase64)
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
