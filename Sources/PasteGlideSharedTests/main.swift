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
