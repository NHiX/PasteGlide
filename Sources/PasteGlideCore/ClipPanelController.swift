import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

@MainActor
final class KeyHandlingPanel: NSPanel {
    weak var keyController: ClipPanelController?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                keyController?.focusSearch()
                return
            case "1":
                keyController?.selectFilterSegment(0)
                return
            case "2":
                keyController?.selectFilterSegment(1)
                return
            case "3":
                keyController?.selectFilterSegment(2)
                return
            case "4":
                keyController?.selectFilterSegment(3)
                return
            case "5":
                keyController?.selectFilterSegment(4)
                return
            case "6":
                keyController?.selectFilterSegment(5)
                return
            case "7":
                keyController?.selectFilterSegment(6)
                return
            case "8":
                keyController?.selectFilterSegment(7)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case UInt16(kVK_LeftArrow):
            keyController?.selectPrevious()
        case UInt16(kVK_RightArrow):
            keyController?.selectNext()
        case UInt16(kVK_UpArrow):
            keyController?.selectPrevious()
        case UInt16(kVK_DownArrow):
            keyController?.selectNext()
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            keyController?.copySelectedItem()
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            keyController?.deleteSelectedItem()
        case UInt16(kVK_Space):
            keyController?.previewSelectedItem()
        case UInt16(kVK_Escape):
            orderOut(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class ClipPanelController: NSObject, NSSearchFieldDelegate {
    private let database: ClipboardDatabase
    private let pasteboard = NSPasteboard.general
    private lazy var panel = makePanel()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl(labels: ["Tous", "★", "YT", "Lien", "Texte", "MDP", "#", "Img"], trackingMode: .selectOne, target: nil, action: nil)
    private let statsLabel = NSTextField(labelWithString: "")
    private let lastCardLabel = NSTextField(labelWithString: "")
    private let lastCardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    private var allItems: [ClipboardItem] = []
    private var visibleItems: [ClipboardItem] = []
    private var cardViews: [CardView] = []
    private var stackSizingConstraint: NSLayoutConstraint?
    private var horizontalStatsConstraints: [NSLayoutConstraint] = []
    private var verticalStatsConstraints: [NSLayoutConstraint] = []
    private var scrollTopConstraint: NSLayoutConstraint?
    private var selectedKindFilter: ClipboardKind?
    private var showsPinnedOnly = false
    private var selectedIndex = 0

    init(database: ClipboardDatabase) {
        self.database = database
        super.init()
        configureContent()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            applyPanelLayout()
            reload()
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func reloadIfVisible() {
        if panel.isVisible {
            applyPanelLayout()
            positionPanel()
            reload()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyHandlingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 242),
            styleMask: [.titled, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.keyController = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        return panel
    }

    private func configureContent() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Rechercher dans l'historique"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))
        filterControl.segmentStyle = .rounded
        filterControl.translatesAutoresizingMaskIntoConstraints = false

        statsLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.maximumNumberOfLines = 1
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        lastCardLabel.font = .systemFont(ofSize: 12)
        lastCardLabel.textColor = .tertiaryLabelColor
        lastCardLabel.alignment = .right
        lastCardLabel.lineBreakMode = .byTruncatingHead
        lastCardLabel.maximumNumberOfLines = 1
        lastCardLabel.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView
        visualEffect.addSubview(searchField)
        visualEffect.addSubview(filterControl)
        visualEffect.addSubview(statsLabel)
        visualEffect.addSubview(lastCardLabel)
        visualEffect.addSubview(scrollView)
        panel.contentView = visualEffect

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 14),

            filterControl.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            filterControl.trailingAnchor.constraint(lessThanOrEqualTo: searchField.trailingAnchor),
            filterControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),

            statsLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statsLabel.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
        horizontalStatsConstraints = [
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: lastCardLabel.leadingAnchor, constant: -12),
            lastCardLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            lastCardLabel.centerYAnchor.constraint(equalTo: statsLabel.centerYAnchor),
            lastCardLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ]
        verticalStatsConstraints = [
            statsLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            lastCardLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            lastCardLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            lastCardLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 2)
        ]
        applyPanelLayout()
    }

    private func reload() {
        allItems = database.fetchRecent()
        updateStats()
        render(items: filteredItems())
    }

    private func render(items: [ClipboardItem]) {
        visibleItems = items
        cardViews = []
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if items.isEmpty {
            let message = allItems.isEmpty ? "Aucun élément copié" : "Aucun résultat"
            let empty = NSTextField(labelWithString: message)
            empty.font = .systemFont(ofSize: 15, weight: .medium)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.frame = NSRect(x: 0, y: 0, width: 300, height: 112)
            stackView.addArrangedSubview(empty)
            return
        }

        for item in items {
            let card = CardView(item: item) { [weak self] selectedItem in
                self?.copyItem(selectedItem)
            } onDelete: { [weak self] selectedItem in
                self?.deleteItem(selectedItem)
            } onTogglePin: { [weak self] selectedItem in
                self?.togglePin(selectedItem)
            } onCopyWithoutClosing: { [weak self] selectedItem in
                self?.copyItem(selectedItem, closesPanel: false)
            } onCopyPlainText: { [weak self] selectedItem in
                self?.copyPlainText(selectedItem)
            } onOpen: { [weak self] selectedItem in
                self?.openItem(selectedItem)
            } onSaveImage: { [weak self] selectedItem in
                self?.saveImage(selectedItem)
            } onDeleteKind: { [weak self] selectedItem in
                self?.deleteKind(selectedItem.kind)
            } contentProvider: { [weak self] selectedItem in
                self?.database.content(for: selectedItem) ?? selectedItem.content
            }
            cardViews.append(card)
            stackView.addArrangedSubview(card)
        }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        updateSelection()
    }

    private func filteredItems() -> [ClipboardItem] {
        let rawQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let search = parsedSearch(rawQuery)
        return allItems.filter { item in
            if showsPinnedOnly, !item.isPinned {
                return false
            }
            if let selectedKindFilter, item.kind != selectedKindFilter {
                return false
            }
            if let kind = search.kind, item.kind != kind {
                return false
            }
            if let pinned = search.pinned, item.isPinned != pinned {
                return false
            }
            if let cutoff = search.createdAfter, item.createdAt < cutoff {
                return false
            }
            guard !search.text.isEmpty else {
                return true
            }
            return item.searchHaystack.contains(search.text)
        }
    }

    private func parsedSearch(_ query: String) -> (text: String, kind: ClipboardKind?, pinned: Bool?, createdAfter: Date?) {
        var terms: [String] = []
        var kind: ClipboardKind?
        var pinned: Bool?
        var createdAfter: Date?

        for token in query.split(separator: " ") {
            if token.hasPrefix("type:") {
                let value = token.dropFirst("type:".count)
                kind = ClipboardKind.allCases.first { $0.rawValue == value || $0.title.lowercased() == value }
            } else if token.hasPrefix("pinned:") {
                let value = token.dropFirst("pinned:".count)
                pinned = value == "true" || value == "yes" || value == "1"
            } else if token.hasPrefix("after:") {
                let value = String(token.dropFirst("after:".count))
                createdAfter = relativeCutoff(from: value)
            } else {
                terms.append(String(token))
            }
        }

        return (terms.joined(separator: " "), kind, pinned, createdAfter)
    }

    private func relativeCutoff(from value: String) -> Date? {
        guard value.count >= 2, let amount = Int(value.dropLast()) else { return nil }
        let unit = value.suffix(1)
        let seconds: TimeInterval
        switch unit {
        case "h": seconds = TimeInterval(amount * 60 * 60)
        case "d": seconds = TimeInterval(amount * 24 * 60 * 60)
        case "w": seconds = TimeInterval(amount * 7 * 24 * 60 * 60)
        default: return nil
        }
        return Date().addingTimeInterval(-seconds)
    }

    private func updateStats() {
        let total = allItems.count
        let countsByKind = Dictionary(grouping: allItems, by: \.kind).mapValues(\.count)
        let totalText = "\(total) \(total == 1 ? "objet mémorisé" : "objets mémorisés")"
        let kindTexts = ClipboardKind.allCases.map { kind in
            "\(kind.title): \(countsByKind[kind, default: 0])"
        }
        if AppSettings.shared.panelPosition.isVertical {
            statsLabel.stringValue = [
                totalText,
                kindTexts.prefix(3).joined(separator: " · "),
                kindTexts.dropFirst(3).joined(separator: " · ")
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        } else {
            statsLabel.stringValue = ([totalText] + kindTexts).joined(separator: " · ")
        }

        if let latestItem = allItems.max(by: { $0.createdAt < $1.createdAt }) {
            lastCardLabel.stringValue = "Dernière carte : \(lastCardDateFormatter.string(from: latestItem.createdAt))"
        } else {
            lastCardLabel.stringValue = "Dernière carte : aucune"
        }
    }

    private func applyPanelLayout() {
        let isVertical = AppSettings.shared.panelPosition.isVertical
        stackView.orientation = isVertical ? .vertical : .horizontal
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        scrollView.hasHorizontalScroller = !isVertical
        scrollView.hasVerticalScroller = isVertical
        statsLabel.lineBreakMode = isVertical ? .byWordWrapping : .byTruncatingTail
        statsLabel.maximumNumberOfLines = isVertical ? 3 : 1
        lastCardLabel.alignment = isVertical ? .left : .right
        lastCardLabel.lineBreakMode = isVertical ? .byTruncatingTail : .byTruncatingHead

        NSLayoutConstraint.deactivate(horizontalStatsConstraints + verticalStatsConstraints)
        NSLayoutConstraint.activate(isVertical ? verticalStatsConstraints : horizontalStatsConstraints)

        stackSizingConstraint?.isActive = false
        stackSizingConstraint = isVertical
            ? stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
            : stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        stackSizingConstraint?.isActive = true

        scrollTopConstraint?.isActive = false
        scrollTopConstraint = scrollView.topAnchor.constraint(equalTo: isVertical ? lastCardLabel.bottomAnchor : statsLabel.bottomAnchor, constant: 8)
        scrollTopConstraint?.isActive = true
        updateStats()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let position = AppSettings.shared.panelPosition
        let margin: CGFloat = 18
        let width: CGFloat
        let height: CGFloat
        let x: CGFloat
        let y: CGFloat

        if position.isVertical {
            width = min(max(visible.width * 0.24, 360), 460)
            height = min(max(visible.height * 0.82, 420), visible.height - margin * 2)
            switch position {
            case .left:
                x = visible.minX + margin
            case .right:
                x = visible.maxX - width - margin
            default:
                x = visible.midX - width / 2
            }
            y = visible.midY - height / 2
        } else {
            let widthPercent = CGFloat(AppSettings.shared.panelWidthPercent) / 100
            width = min(max(visible.width * widthPercent, 680), 1280)
            height = 242
            x = visible.midX - width / 2
            y = position == .top ? visible.maxY - height - margin : visible.minY + margin
        }

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func copyItem(_ item: ClipboardItem, closesPanel: Bool = true) {
        pasteboard.clearContents()
        let content = database.content(for: item)
        if item.kind == .image, let data = Data(base64Encoded: content), let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(content, forType: .string)
        }
        if closesPanel {
            panel.orderOut(nil)
        }
    }

    private func copyPlainText(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.kind == .image ? item.preview : database.content(for: item), forType: .string)
    }

    private func openItem(_ item: ClipboardItem) {
        guard item.kind != .image, let url = URL(string: database.content(for: item)), url.scheme != nil else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveImage(_ item: ClipboardItem) {
        guard item.kind == .image, let data = Data(base64Encoded: database.content(for: item)) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PasteGlide-image.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func deleteKind(_ kind: ClipboardKind) {
        try? database.delete(kind: kind)
        reload()
    }

    func selectPrevious() {
        guard !visibleItems.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        updateSelection()
    }

    func selectNext() {
        guard !visibleItems.isEmpty else { return }
        selectedIndex = min(visibleItems.count - 1, selectedIndex + 1)
        updateSelection()
    }

    func copySelectedItem() {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        copyItem(visibleItems[selectedIndex])
    }

    func deleteSelectedItem() {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        deleteItem(visibleItems[selectedIndex])
    }

    func previewSelectedItem() {
        guard cardViews.indices.contains(selectedIndex) else { return }
        cardViews[selectedIndex].showPreview()
    }

    func focusSearch() {
        panel.makeFirstResponder(searchField)
    }

    func selectFilterSegment(_ segment: Int) {
        guard segment >= 0, segment < filterControl.segmentCount else { return }
        filterControl.selectedSegment = segment
        applyFilter(segment: segment)
    }

    private func updateSelection() {
        for (index, card) in cardViews.enumerated() {
            card.isSelectedCard = index == selectedIndex
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        try? database.delete(id: item.id)
        reload()
    }

    private func togglePin(_ item: ClipboardItem) {
        try? database.setPinned(id: item.id, isPinned: !item.isPinned)
        reload()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        render(items: filteredItems())
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        applyFilter(segment: sender.selectedSegment)
    }

    private func applyFilter(segment: Int) {
        showsPinnedOnly = segment == 1
        selectedKindFilter = switch segment {
        case 2: .youtube
        case 3: .url
        case 4: .text
        case 5: .password
        case 6: .number
        case 7: .image
        default: nil
        }
        selectedIndex = 0
        render(items: filteredItems())
    }

    func controlTextDidChange(_ notification: Notification) {
        render(items: filteredItems())
    }
}
