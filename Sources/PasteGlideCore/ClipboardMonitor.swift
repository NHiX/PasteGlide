import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import PasteGlideShared
import SQLite3
import UniformTypeIdentifiers
import Vision

@MainActor
final class ClipboardMonitor {
    private let database: ClipboardDatabase
    private let classifier = ClipboardClassifier()
    private let imageTextRecognizer = ImageTextRecognizer()
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int
    var onChange: (() -> Void)?

    init(database: ClipboardDatabase) {
        self.database = database
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scanPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !AppSettings.shared.isCapturePaused else { return }
        guard !AppSettings.shared.isExcluded(application: NSWorkspace.shared.frontmostApplication) else { return }

        if let image = NSImage(pasteboard: pasteboard), let base64 = image.pngBase64() {
            guard AppSettings.shared.shouldCaptureImages else { return }
            let maxBytes = AppSettings.shared.maxCapturedImageMegabytes * 1024 * 1024
            guard (base64.count * 3 / 4) <= maxBytes else { return }
            let hash = Self.hash("image:\(base64)")
            let preview = image.previewText()
            try? database.insert(kind: .image, content: base64, preview: preview, ocrAttempted: !AppSettings.shared.isOCREnabled, hash: hash)
            onChange?()
            if AppSettings.shared.isOCREnabled, let data = Data(base64Encoded: base64) {
                runImageOCR(data: data, hash: hash)
            }
            return
        }

        guard let string = pasteboard.string(forType: .string) else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let kind = classifier.classifyString(trimmed)
        guard kind != .password || AppSettings.shared.shouldCapturePasswords else { return }
        let preview = classifier.preview(for: trimmed, kind: kind)
        let hash = Self.hash("\(kind.rawValue):\(trimmed)")
        try? database.insert(kind: kind, content: trimmed, preview: preview, hash: hash)
        onChange?()
    }

    private func runImageOCR(data: Data, hash: String) {
        Task { [weak self] in
            let ocrText = await Task.detached {
                ImageTextRecognizer().recognizeText(in: data)
            }.value
            guard let image = NSImage(data: data) else { return }
            let preview = image.previewText(ocrText: ocrText)
            self?.database.updateOCR(forHash: hash, preview: preview, ocrText: ocrText)
            self?.onChange?()
        }
    }

    static func hash(_ value: String) -> String {
        hashContent(value)
    }
}
