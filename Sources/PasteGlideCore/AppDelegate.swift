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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "PasteGlide"
        let menu = NSMenu()
        menu.addItem(menuItem(title: "Afficher l'historique", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Préférences", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Exporter l'historique", action: #selector(exportHistory), keyEquivalent: ""))
        menu.addItem(menuItem(title: "Importer un historique", action: #selector(importHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
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
        preferencesWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
}
