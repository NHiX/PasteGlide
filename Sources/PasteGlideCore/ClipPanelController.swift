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
    private let stackView = NSStackView()
    private let searchField = NSSearchField()
    private var allItems: [ClipboardItem] = []
    private var visibleItems: [ClipboardItem] = []
    private var cardViews: [CardView] = []
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
            reload()
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func reloadIfVisible() {
        if panel.isVisible {
            reload()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyHandlingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 188),
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

        let scrollView = NSScrollView()
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
        visualEffect.addSubview(scrollView)
        panel.contentView = visualEffect

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])
    }

    private func reload() {
        allItems = database.fetchRecent()
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

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let widthPercent = CGFloat(AppSettings.shared.panelWidthPercent) / 100
        let width = min(max(visible.width * widthPercent, 680), 1280)
        let height: CGFloat = 188
        let x = visible.midX - width / 2
        let y = visible.minY + 18
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
