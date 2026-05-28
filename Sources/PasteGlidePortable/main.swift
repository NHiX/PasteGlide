import Foundation
import PasteGlideShared

struct PasteGlidePortableCLI {
    let arguments: [String]
    let output: (String) -> Void

    init(arguments: [String] = Array(CommandLine.arguments.dropFirst()), output: @escaping (String) -> Void = { print($0) }) {
        self.arguments = arguments
        self.output = output
    }

    func run() -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return 0
        }

        switch command {
        case "classify":
            return classify(Array(arguments.dropFirst()))
        case "search-demo":
            return searchDemo(Array(arguments.dropFirst()))
        case "settings-demo":
            return settingsDemo()
        case "store-demo":
            return storeDemo()
        case "view-demo":
            return viewDemo(Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
            return 0
        default:
            output("Unknown command: \(command)")
            printUsage()
            return 2
        }
    }

    private func classify(_ values: [String]) -> Int32 {
        let value = values.joined(separator: " ")
        guard !value.isEmpty else {
            output("Missing text to classify.")
            return 2
        }

        let classifier = ClipboardClassifier()
        let kind = classifier.classifyString(value)
        output("kind=\(kind.rawValue)")
        output("preview=\(classifier.preview(for: value, kind: kind))")
        return 0
    }

    private func searchDemo(_ values: [String]) -> Int32 {
        let query = values.joined(separator: " ")
        let now = Date()
        let items = [
            ClipboardItem(
                id: 1,
                kind: .text,
                content: "Invoice PasteGlide portable demo",
                preview: "Invoice PasteGlide portable demo",
                ocrText: "",
                isPinned: true,
                createdAt: now.addingTimeInterval(-60),
                contentHash: "demo-text"
            ),
            ClipboardItem(
                id: 2,
                kind: .url,
                content: "https://example.com",
                preview: "https://example.com",
                ocrText: "",
                isPinned: false,
                createdAt: now.addingTimeInterval(-120),
                contentHash: "demo-url"
            )
        ]

        let results = ClipboardSearch(now: { now }).filter(
            items,
            rawQuery: query,
            showsPinnedOnly: false,
            selectedKindFilter: nil
        )
        if results.isEmpty {
            output("No matches")
        } else {
            for item in results {
                output("\(item.id)\t\(item.kind.rawValue)\t\(item.preview)")
            }
        }
        return 0
    }

    private func settingsDemo() -> Int32 {
        output("historyLimit=\(PasteGlideSettingsRules.normalizedHistoryLimit(0))")
        output("panelWidthPercent=\(PasteGlideSettingsRules.normalizedPanelWidthPercent(0))")
        output("maxCapturedImageMegabytes=\(PasteGlideSettingsRules.normalizedMaxCapturedImageMegabytes(0))")
        output("hotKeyCharacter=\(PasteGlideSettingsRules.normalizedHotKeyCharacter(""))")
        return 0
    }

    private func storeDemo() -> Int32 {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PasteGlidePortable-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = JSONClipboardHistoryStore(fileURL: directory.appendingPathComponent("history.json"), historyLimit: 10)
            try store.insert(kind: .text, content: "Portable history item", preview: "Portable history item")
            try store.insert(kind: .url, content: "https://example.com", preview: "https://example.com")
            let items = try store.loadItems()
            output("items=\(items.count)")
            output("archiveVersion=\(try store.exportArchive().version)")
            output("path=\(store.fileURL.path)")
            return 0
        } catch {
            output("store-demo failed: \(error)")
            return 1
        }
    }

    private func viewDemo(_ values: [String]) -> Int32 {
        let query = values.joined(separator: " ")
        let now = Date()
        let state = ClipboardHistoryViewState(
            allItems: [
                ClipboardItem(
                    id: 1,
                    kind: .text,
                    content: "Invoice PasteGlide portable demo",
                    preview: "Invoice PasteGlide portable demo",
                    ocrText: "",
                    isPinned: true,
                    createdAt: now.addingTimeInterval(-60),
                    contentHash: "demo-text"
                ),
                ClipboardItem(
                    id: 2,
                    kind: .url,
                    content: "https://example.com",
                    preview: "https://example.com",
                    ocrText: "",
                    isPinned: false,
                    createdAt: now.addingTimeInterval(-120),
                    contentHash: "demo-url"
                )
            ],
            searchText: query,
            panelPosition: .left,
            formatDate: { ISO8601DateFormatter().string(from: $0) }
        )
        let snapshot = state.snapshot()
        output("layout=\(snapshot.isVerticalLayout ? "vertical" : "horizontal")")
        output("items=\(snapshot.items.count)")
        for line in snapshot.statsLines {
            output("stats=\(line)")
        }
        output("latest=\(snapshot.latestItemText)")
        return 0
    }

    private func printUsage() {
        output("""
        PasteGlidePortable

        Commands:
          classify <text>       Classify text with the shared PasteGlide classifier.
          search-demo <query>   Run the shared search engine against demo items.
          settings-demo         Print normalized shared default settings.
          store-demo            Write and read a portable JSON history store.
          view-demo <query>     Build a portable UI snapshot for demo items.
          help                  Show this help.
        """)
    }
}

exit(PasteGlidePortableCLI().run())
