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

func testSearchParsesOperatorsAndFiltersItems() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let search = ClipboardSearch(now: { now })
    let query = search.parse("type:text pinned:true after:2h facture")

    try expect(query.kind == .text, "type:text should select text kind")
    try expect(query.pinned == true, "pinned:true should select pinned items")
    try expect(query.text == "facture", "plain terms should remain searchable text")
    try expect(query.createdAfter == now.addingTimeInterval(-7_200), "after:2h should build relative cutoff")

    let matching = ClipboardItem(
        id: 1,
        kind: .text,
        content: "Facture fournisseur",
        preview: "Facture fournisseur",
        ocrText: "",
        isPinned: true,
        createdAt: now.addingTimeInterval(-60),
        contentHash: "matching"
    )
    let wrongKind = ClipboardItem(
        id: 2,
        kind: .url,
        content: "https://example.com/facture",
        preview: "https://example.com/facture",
        ocrText: "",
        isPinned: true,
        createdAt: now.addingTimeInterval(-60),
        contentHash: "wrong-kind"
    )
    let tooOld = ClipboardItem(
        id: 3,
        kind: .text,
        content: "Facture ancienne",
        preview: "Facture ancienne",
        ocrText: "",
        isPinned: true,
        createdAt: now.addingTimeInterval(-8_000),
        contentHash: "too-old"
    )

    let results = search.filter([matching, wrongKind, tooOld], rawQuery: "type:text pinned:true after:2h facture", showsPinnedOnly: false, selectedKindFilter: nil)
    try expect(results.map(\.id) == [1], "search should keep only matching items")
}

func testClipboardArchiveRoundTripsPortableItems() throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let item = ClipboardItem(
        id: 42,
        kind: .image,
        content: "base64-image",
        preview: "Image 64x64",
        ocrText: "texte reconnu",
        isPinned: true,
        createdAt: createdAt,
        contentHash: "image-hash"
    )

    let archive = ClipboardArchive(clipboardItems: [item])
    let data = try archive.encoded()
    let json = String(data: data, encoding: .utf8) ?? ""
    try expect(json.contains("\"version\""), "archive JSON should include a version")
    try expect(json.contains("\"items\""), "archive JSON should include an items array")

    let decoded = try ClipboardArchive.decoded(from: data)
    let roundTripItems = decoded.clipboardItems()
    try expect(decoded.version == ClipboardArchive.currentVersion, "archive should keep the current version")
    try expect(roundTripItems.count == 1, "archive should round-trip one item")
    try expect(roundTripItems[0].id == 42, "archive should preserve item id when present")
    try expect(roundTripItems[0].kind == .image, "archive should preserve kind")
    try expect(roundTripItems[0].content == "base64-image", "archive should preserve content")
    try expect(roundTripItems[0].ocrText == "texte reconnu", "archive should preserve OCR text")
    try expect(roundTripItems[0].isPinned, "archive should preserve pin state")
    try expect(roundTripItems[0].createdAt == createdAt, "archive should preserve creation date")
    try expect(roundTripItems[0].contentHash == "image-hash", "archive should preserve content hash")
}

func testClipboardArchiveDecodesLegacyArrayExports() throws {
    let legacyJSON = """
    [
      {
        "kind": "text",
        "content": "Bonjour",
        "preview": "Bonjour",
        "ocrText": "",
        "createdAt": 1700000100,
        "contentHash": "text-hash",
        "isPinned": false
      }
    ]
    """

    let archive = try ClipboardArchive.decoded(from: Data(legacyJSON.utf8))
    let items = archive.clipboardItems()
    try expect(archive.version == ClipboardArchive.currentVersion, "legacy arrays should be treated as current archive version")
    try expect(items.count == 1, "legacy archive should decode one item")
    try expect(items[0].id == 1, "legacy archive should assign a stable fallback id")
    try expect(items[0].kind == .text, "legacy archive should decode kind")
    try expect(items[0].content == "Bonjour", "legacy archive should decode content")
    try expect(items[0].createdAt == Date(timeIntervalSince1970: 1_700_000_100), "legacy archive should decode creation date")
}

func testPanelPositionSharedLayoutMetadata() throws {
    try expect(PanelPosition.bottom.title == "Bas", "bottom title should stay localized")
    try expect(PanelPosition.top.isVertical == false, "top layout should be horizontal")
    try expect(PanelPosition.left.isVertical == true, "left layout should be vertical")
    try expect(PanelPosition.right.isVertical == true, "right layout should be vertical")
    try expect(PanelPosition.center.isVertical == true, "center layout should be vertical")
}

func testSettingsRulesNormalizePortablePreferences() throws {
    try expect(PasteGlideSettingsRules.normalizedHistoryLimit(0) == 100, "missing history limit should use default")
    try expect(PasteGlideSettingsRules.normalizedHistoryLimit(3) == 10, "history limit should be clamped to minimum")
    try expect(PasteGlideSettingsRules.normalizedRetentionDays(-4) == 0, "retention days should not be negative")
    try expect(PasteGlideSettingsRules.normalizedMaxCapturedImageMegabytes(0) == 20, "missing image limit should use default")
    try expect(PasteGlideSettingsRules.normalizedMaxCapturedImageMegabytes(500) == 200, "image limit should be capped")
    try expect(PasteGlideSettingsRules.normalizedPanelWidthPercent(0) == 86, "missing panel width should use default")
    try expect(PasteGlideSettingsRules.normalizedPanelWidthPercent(12) == 50, "panel width should be clamped to minimum")
    try expect(PasteGlideSettingsRules.normalizedPanelWidthPercent(120) == 95, "panel width should be capped")
    try expect(PasteGlideSettingsRules.normalizedHotKeyCharacter(" m ") == "M", "hotkey should normalize to first uppercase character")
    try expect(PasteGlideSettingsRules.normalizedHotKeyCharacter("") == "V", "empty hotkey should use default")
}

func testSettingsRulesMatchExcludedApplications() throws {
    let exclusions = PasteGlideSettingsRules.normalizedExcludedApplications(["  safari  ", "", "com.secret"])
    try expect(exclusions == ["safari", "com.secret"], "excluded apps should be trimmed and empty values removed")
    try expect(
        PasteGlideSettingsRules.isApplicationExcluded(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            exclusions: exclusions
        ),
        "bundle/name should match excluded app fragments case-insensitively"
    )
    try expect(
        !PasteGlideSettingsRules.isApplicationExcluded(
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            exclusions: exclusions
        ),
        "unlisted apps should not be excluded"
    )
}

let tests: [(String, () throws -> Void)] = [
    ("sharedClassifierDetectsExpectedKinds", testClassifierDetectsExpectedKinds),
    ("sharedSearchHaystackUsesOCRButSkipsImageBase64", testSearchHaystackUsesOCRButSkipsImageBase64),
    ("sharedSearchParsesOperatorsAndFiltersItems", testSearchParsesOperatorsAndFiltersItems),
    ("sharedClipboardArchiveRoundTripsPortableItems", testClipboardArchiveRoundTripsPortableItems),
    ("sharedClipboardArchiveDecodesLegacyArrayExports", testClipboardArchiveDecodesLegacyArrayExports),
    ("sharedPanelPositionSharedLayoutMetadata", testPanelPositionSharedLayoutMetadata),
    ("sharedSettingsRulesNormalizePortablePreferences", testSettingsRulesNormalizePortablePreferences),
    ("sharedSettingsRulesMatchExcludedApplications", testSettingsRulesMatchExcludedApplications)
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
