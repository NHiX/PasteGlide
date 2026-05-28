import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

@MainActor
final class CardView: NSControl {
    private let item: ClipboardItem
    private let onSelect: (ClipboardItem) -> Void
    private let onDelete: (ClipboardItem) -> Void
    private let onTogglePin: (ClipboardItem) -> Void
    private var revealed = false
    private let previewLabel = NSTextField(labelWithString: "")
    private var hoverTrackingArea: NSTrackingArea?
    private var previewPopover: NSPopover?
    var isSelectedCard = false {
        didSet { updateSelectionStyle() }
    }

    init(item: ClipboardItem, onSelect: @escaping (ClipboardItem) -> Void, onDelete: @escaping (ClipboardItem) -> Void, onTogglePin: @escaping (ClipboardItem) -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onTogglePin = onTogglePin
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(String(item.id))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        previewPopover?.close()
        onSelect(item)
    }

    override func rightMouseDown(with event: NSEvent) {
        if item.kind == .password {
            revealed.toggle()
            previewLabel.stringValue = revealed ? item.content : item.preview
            return
        }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: item.isPinned ? "Désépingler" : "Épingler", action: #selector(togglePin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Supprimer", action: #selector(deleteCard), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func togglePin() {
        onTogglePin(item)
    }

    @objc private func deleteCard() {
        onDelete(item)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        guard item.kind != .password else { return }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        showPreviewPopover()
    }

    override func mouseExited(with event: NSEvent) {
        previewPopover?.close()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        toolTip = tooltipText
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 3
        layer?.borderColor = item.kind.borderColor.cgColor

        let leadingView = makeLeadingView()

        let title = NSTextField(labelWithString: item.isPinned ? "★ \(item.kind.title)" : item.kind.title)
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = .secondaryLabelColor
        title.toolTip = tooltipText
        title.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.stringValue = item.preview
        previewLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        previewLabel.textColor = .labelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 3
        previewLabel.toolTip = tooltipText
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        let date = NSTextField(labelWithString: Self.relativeDate(item.createdAt))
        date.font = .systemFont(ofSize: 12)
        date.textColor = .tertiaryLabelColor
        date.toolTip = tooltipText
        date.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, previewLabel, date])
        stack.orientation = .vertical
        stack.spacing = 5
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leadingView)
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 300),
            heightAnchor.constraint(equalToConstant: 112),

            leadingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leadingView.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingView.widthAnchor.constraint(equalToConstant: 72),
            leadingView.heightAnchor.constraint(equalToConstant: 72),

            stack.leadingAnchor.constraint(equalTo: leadingView.trailingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
    }

    private func updateSelectionStyle() {
        layer?.borderWidth = isSelectedCard ? 5 : 3
        layer?.shadowOpacity = isSelectedCard ? 0.22 : 0
        layer?.shadowRadius = isSelectedCard ? 8 : 0
    }

    private func makeLeadingView() -> NSView {
        if item.kind == .image, let data = Data(base64Encoded: item.content), let image = NSImage(data: data) {
            let imageView = NSImageView(image: image)
            imageView.toolTip = tooltipText
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.masksToBounds = true
            imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }

        let badge = NSView()
        badge.toolTip = tooltipText
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.backgroundColor = item.kind.borderColor.withAlphaComponent(0.14).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "\(item.content.count)")
        count.font = .monospacedDigitSystemFont(ofSize: 19, weight: .bold)
        count.alignment = .center
        count.textColor = .labelColor
        count.lineBreakMode = .byTruncatingTail
        count.toolTip = tooltipText
        count.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: badgeExcerpt)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.toolTip = tooltipText
        label.translatesAutoresizingMaskIntoConstraints = false

        badge.addSubview(count)
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            count.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 5),
            count.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -5),
            count.topAnchor.constraint(equalTo: badge.topAnchor, constant: 8),

            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: count.bottomAnchor, constant: 4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: badge.bottomAnchor, constant: -7)
        ])

        return badge
    }

    private func showPreviewPopover() {
        guard item.kind != .password else { return }
        guard previewPopover == nil || previewPopover?.isShown == false else { return }

        guard let popover = item.kind == .image ? makeImagePreviewPopover() : makeTextPreviewPopover() else { return }
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        previewPopover = popover
    }

    private func makeImagePreviewPopover() -> NSPopover? {
        guard let data = Data(base64Encoded: item.content), let image = NSImage(data: data) else { return nil }

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: item.preview)
        caption.font = .systemFont(ofSize: 12, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false

        let ocrLabel = NSTextField(labelWithString: imageOCRPreview)
        ocrLabel.font = .systemFont(ofSize: 12)
        ocrLabel.textColor = .labelColor
        ocrLabel.lineBreakMode = .byTruncatingTail
        ocrLabel.maximumNumberOfLines = 4
        ocrLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        container.addSubview(caption)
        container.addSubview(ocrLabel)

        let maxWidth: CGFloat = 360
        let maxHeight: CGFloat = 260
        let scale = min(maxWidth / max(image.size.width, 1), maxHeight / max(image.size.height, 1), 1)
        let previewWidth = max(160, image.size.width * scale)
        let previewHeight = max(110, image.size.height * scale)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            imageView.widthAnchor.constraint(equalToConstant: previewWidth),
            imageView.heightAnchor.constraint(equalToConstant: previewHeight),

            caption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            caption.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            caption.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),

            ocrLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            ocrLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            ocrLabel.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 6),
            ocrLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        let controller = NSViewController()
        controller.view = container

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: previewWidth + 24, height: previewHeight + imageOCRPopoverExtraHeight)
        return popover
    }

    private func makeTextPreviewPopover() -> NSPopover? {
        let title = NSTextField(labelWithString: "\(item.kind.title) · \(item.content.count) caractères")
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.string = item.content
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            scrollView.widthAnchor.constraint(equalToConstant: 360),
            scrollView.heightAnchor.constraint(equalToConstant: textPreviewHeight)
        ])

        let controller = NSViewController()
        controller.view = container

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 376, height: textPreviewHeight + 42)
        return popover
    }

    private var badgeExcerpt: String {
        switch item.kind {
        case .youtube: "▶"
        case .text: firstWords(maximum: 6)
        case .password: "••"
        case .number: "#"
        case .image: "▧"
        }
    }

    private var tooltipText: String {
        let header = "\(item.kind.title) · \(Self.relativeDate(item.createdAt))"
        switch item.kind {
        case .password:
            return "\(header)\nMot de passe masqué. Clic droit pour révéler dans la carte."
        case .image:
            return imagePreviewText(header: header)
        default:
            return "\(header)\n\(item.content)"
        }
    }

    private func firstWords(maximum: Int) -> String {
        let words = item.content
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(maximum)
        return words.joined(separator: " ")
    }

    private var textPreviewHeight: CGFloat {
        let lineEstimate = max(1, item.content.count / 52)
        return min(max(CGFloat(lineEstimate * 20), 120), 260)
    }

    private func imagePreviewText(header: String) -> String {
        guard !item.ocrText.isEmpty else {
            return "\(header)\n\(item.preview)"
        }
        return "\(header)\n\(item.preview)\n\nTexte reconnu:\n\(item.ocrText)"
    }

    private var imageOCRPreview: String {
        guard !item.ocrText.isEmpty else {
            return "Aucun texte reconnu"
        }
        let normalized = item.ocrText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 180 {
            return "Texte reconnu: \(normalized)"
        }
        return "Texte reconnu: \(normalized.prefix(177))..."
    }

    private var imageOCRPopoverExtraHeight: CGFloat {
        item.ocrText.isEmpty ? 70 : 110
    }

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
