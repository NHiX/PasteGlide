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
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 214),
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
        visualEffect.addSubview(statsLabel)
        visualEffect.addSubview(lastCardLabel)
        visualEffect.addSubview(scrollView)
        panel.contentView = visualEffect

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 14),

            statsLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statsLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),

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
            }
            cardViews.append(card)
            stackView.addArrangedSubview(card)
        }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        updateSelection()
    }

    private func filteredItems() -> [ClipboardItem] {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allItems }

        return allItems.filter { item in
            item.searchHaystack.contains(query)
        }
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
            height = 214
            x = visible.midX - width / 2
            y = position == .top ? visible.maxY - height - margin : visible.minY + margin
        }

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func copyItem(_ item: ClipboardItem) {
        pasteboard.clearContents()
        if item.kind == .image, let data = Data(base64Encoded: item.content), let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(item.content, forType: .string)
        }
        panel.orderOut(nil)
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

    func controlTextDidChange(_ notification: Notification) {
        render(items: filteredItems())
    }
}
