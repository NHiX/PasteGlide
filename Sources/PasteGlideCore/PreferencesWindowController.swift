import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let limitField = NSTextField()
    private let retentionField = NSTextField()
    private let hotKeyField = NSTextField()
    private let panelWidthField = NSTextField()
    private let panelPositionPopUp = NSPopUpButton()
    private let maxImageSizeField = NSTextField()
    private let ocrCheckbox = NSButton(checkboxWithTitle: "Activer l'OCR des images", target: nil, action: nil)
    private let captureImagesCheckbox = NSButton(checkboxWithTitle: "Mémoriser les images", target: nil, action: nil)
    private let capturePasswordsCheckbox = NSButton(checkboxWithTitle: "Mémoriser les mots de passe probables", target: nil, action: nil)
    private let maskSensitiveCheckbox = NSButton(checkboxWithTitle: "Masquer les contenus sensibles dans les cartes", target: nil, action: nil)
    private let excludedAppsField = NSTextField()
    var onSave: (() -> Void)?
    var onDeleteAll: (() -> Void)?
    var onDeleteImages: (() -> Void)?
    var onDeleteOldItems: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Préférences PasteGlide"
        super.init(window: window)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        guard let contentView = window?.contentView else { return }
        let settings = AppSettings.shared

        limitField.stringValue = "\(settings.historyLimit)"
        retentionField.stringValue = "\(settings.retentionDays)"
        hotKeyField.stringValue = settings.hotKeyCharacter
        panelWidthField.stringValue = "\(settings.panelWidthPercent)"
        maxImageSizeField.stringValue = "\(settings.maxCapturedImageMegabytes)"
        PanelPosition.allCases.forEach { panelPositionPopUp.addItem(withTitle: $0.title) }
        panelPositionPopUp.selectItem(withTitle: settings.panelPosition.title)
        ocrCheckbox.state = settings.isOCREnabled ? .on : .off
        captureImagesCheckbox.state = settings.shouldCaptureImages ? .on : .off
        capturePasswordsCheckbox.state = settings.shouldCapturePasswords ? .on : .off
        maskSensitiveCheckbox.state = settings.shouldMaskSensitiveContent ? .on : .off
        excludedAppsField.stringValue = settings.excludedApplications.joined(separator: ", ")
        excludedAppsField.placeholderString = "Bundle id ou nom d'app, séparés par des virgules"

        let saveButton = NSButton(title: "Enregistrer", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        let deleteImagesButton = NSButton(title: "Supprimer les images", target: self, action: #selector(deleteImages))
        deleteImagesButton.bezelStyle = .rounded
        let deleteOldButton = NSButton(title: "Supprimer > rétention", target: self, action: #selector(deleteOldItems))
        deleteOldButton.bezelStyle = .rounded
        let deleteAllButton = NSButton(title: "Vider l'historique", target: self, action: #selector(deleteAll))
        deleteAllButton.bezelStyle = .rounded

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Éléments à conserver", field: limitField))
        stack.addArrangedSubview(row(label: "Rétention en jours (0 = désactivé)", field: retentionField))
        stack.addArrangedSubview(row(label: "Touche raccourci ⌥⌘", field: hotKeyField))
        stack.addArrangedSubview(row(label: "Largeur panneau (%)", field: panelWidthField))
        stack.addArrangedSubview(row(label: "Position du panneau", control: panelPositionPopUp))
        stack.addArrangedSubview(ocrCheckbox)
        stack.addArrangedSubview(captureImagesCheckbox)
        stack.addArrangedSubview(row(label: "Image max (Mo)", field: maxImageSizeField))
        stack.addArrangedSubview(capturePasswordsCheckbox)
        stack.addArrangedSubview(maskSensitiveCheckbox)
        stack.addArrangedSubview(row(label: "Apps exclues", field: excludedAppsField))
        stack.addArrangedSubview(buttonRow([deleteImagesButton, deleteOldButton, deleteAllButton]))
        stack.addArrangedSubview(saveButton)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])
    }

    private func row(label: String, field: NSTextField) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 190).isActive = true
        field.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let row = NSStackView(views: [title, field])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    private func row(label: String, control: NSControl) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 190).isActive = true
        control.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func save() {
        let settings = AppSettings.shared
        settings.historyLimit = Int(limitField.stringValue) ?? settings.historyLimit
        settings.retentionDays = Int(retentionField.stringValue) ?? settings.retentionDays
        settings.hotKeyCharacter = hotKeyField.stringValue
        settings.panelWidthPercent = Int(panelWidthField.stringValue) ?? settings.panelWidthPercent
        settings.maxCapturedImageMegabytes = Int(maxImageSizeField.stringValue) ?? settings.maxCapturedImageMegabytes
        if let selectedTitle = panelPositionPopUp.selectedItem?.title,
           let position = PanelPosition.allCases.first(where: { $0.title == selectedTitle }) {
            settings.panelPosition = position
        }
        settings.isOCREnabled = ocrCheckbox.state == .on
        settings.shouldCaptureImages = captureImagesCheckbox.state == .on
        settings.shouldCapturePasswords = capturePasswordsCheckbox.state == .on
        settings.shouldMaskSensitiveContent = maskSensitiveCheckbox.state == .on
        settings.excludedApplications = excludedAppsField.stringValue.split(separator: ",").map(String.init)
        onSave?()
        window?.orderOut(nil)
    }

    @objc private func deleteAll() {
        onDeleteAll?()
    }

    @objc private func deleteImages() {
        onDeleteImages?()
    }

    @objc private func deleteOldItems() {
        onDeleteOldItems?()
    }
}
