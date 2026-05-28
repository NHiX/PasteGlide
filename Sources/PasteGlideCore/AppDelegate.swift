import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: ClipboardDatabase?
    private var monitor: ClipboardMonitor?
    private var ocrBackfillService: OCRBackfillService?
    private var panelController: ClipPanelController?
    private var hotKeyController: HotKeyController?
    private var statusItem: NSStatusItem?
    private var preferencesWindowController: PreferencesWindowController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let database = try ClipboardDatabase()
            let panelController = ClipPanelController(database: database)
            let ocrBackfillService = OCRBackfillService(database: database)
            ocrBackfillService.onChange = { [weak panelController] in
                panelController?.reloadIfVisible()
            }
            let monitor = ClipboardMonitor(database: database)
            monitor.onChange = { [weak panelController] in
                panelController?.reloadIfVisible()
            }
            monitor.start()
            ocrBackfillService.run()

            let hotKeyController = HotKeyController {
                DispatchQueue.main.async {
                    panelController.toggle()
                }
            }
            hotKeyController.register()

            self.database = database
            self.ocrBackfillService = ocrBackfillService
            self.panelController = panelController
            self.monitor = monitor
            self.hotKeyController = hotKeyController
            configureStatusItem()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeStatusBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "PasteGlide"
            button.setAccessibilityLabel("PasteGlide")
        }
        let menu = NSMenu()
        menu.addItem(menuItem(title: "Afficher l'historique", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Préférences", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Pause capture 5 min", action: #selector(pauseCaptureFiveMinutes), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Pause capture 15 min", action: #selector(pauseCaptureFifteenMinutes), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Pause capture 30 min", action: #selector(pauseCaptureThirtyMinutes), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Reprendre la capture", action: #selector(resumeCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Exporter l'historique", action: #selector(exportHistory), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Importer un historique", action: #selector(importHistory), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Exporter JSON", action: #selector(exportJSON), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Importer JSON", action: #selector(importJSON), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func makeStatusBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setFill()

        let clipboard = NSBezierPath(roundedRect: NSRect(x: 4, y: 3, width: 10, height: 12), xRadius: 2, yRadius: 2)
        clipboard.fill()

        NSColor.white.setFill()
        let sheet = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 4.5, width: 7, height: 8.5), xRadius: 1, yRadius: 1)
        sheet.fill()

        NSColor.black.setFill()
        let clip = NSBezierPath(roundedRect: NSRect(x: 6, y: 13, width: 6, height: 2.2), xRadius: 1, yRadius: 1)
        clip.fill()

        for y in [10.5, 8.2, 5.9] {
            let card = NSBezierPath(roundedRect: NSRect(x: 6.7, y: y, width: 5.4, height: 1.1), xRadius: 0.5, yRadius: 0.5)
            card.fill()
        }

        let glide = NSBezierPath()
        glide.lineWidth = 1.4
        glide.lineCapStyle = .round
        glide.move(to: NSPoint(x: 2.5, y: 5))
        glide.curve(to: NSPoint(x: 8.5, y: 3.3), controlPoint1: NSPoint(x: 4, y: 3.8), controlPoint2: NSPoint(x: 6.5, y: 3.1))
        glide.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func showPreferences() {
        let controller = preferencesWindowController ?? PreferencesWindowController()
        controller.onSave = { [weak self] in
            try? self?.database?.applyRetention()
            self?.hotKeyController?.register()
            self?.panelController?.reloadIfVisible()
        }
        controller.onDeleteAll = { [weak self] in
            try? self?.database?.deleteAll()
            self?.panelController?.reloadIfVisible()
        }
        controller.onDeleteImages = { [weak self] in
            try? self?.database?.delete(kind: .image)
            self?.panelController?.reloadIfVisible()
        }
        controller.onDeleteOldItems = { [weak self] in
            let days = AppSettings.shared.retentionDays
            if days > 0 {
                try? self?.database?.deleteOlderThan(days: days)
                self?.panelController?.reloadIfVisible()
            }
        }
        preferencesWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func pauseCaptureFiveMinutes() {
        pauseCapture(minutes: 5)
    }

    @objc private func pauseCaptureFifteenMinutes() {
        pauseCapture(minutes: 15)
    }

    @objc private func pauseCaptureThirtyMinutes() {
        pauseCapture(minutes: 30)
    }

    @objc private func resumeCapture() {
        AppSettings.shared.capturePauseUntil = nil
    }

    private func pauseCapture(minutes: Int) {
        AppSettings.shared.capturePauseUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    @objc private func exportHistory() {
        guard let database else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PasteGlide-history.sqlite"
        panel.allowedContentTypes = [.database]
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: database.path), to: url)
        }
    }

    @objc private func importHistory() {
        guard let database else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.database]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            try? database.importItems(from: url.path)
            panelController?.reloadIfVisible()
        }
    }

    @objc private func exportJSON() {
        guard let database else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PasteGlide-history.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? database.exportJSON(to: url)
        }
    }

    @objc private func importJSON() {
        guard let database else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            try? database.importJSON(from: url)
            panelController?.reloadIfVisible()
        }
    }
}
