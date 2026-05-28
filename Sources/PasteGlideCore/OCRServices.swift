import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import PasteGlideShared
import SQLite3
import UniformTypeIdentifiers
import Vision

final class ImageTextRecognizer {
    func recognizeText(in image: NSImage) -> String {
        guard let cgImage = image.cgImageForVision else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recognizeText(in imageData: Data) -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return ""
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class OCRBackfillService {
    private let database: ClipboardDatabase
    private let recognizer = ImageTextRecognizer()
    var onChange: (() -> Void)?

    init(database: ClipboardDatabase) {
        self.database = database
    }

    func run() {
        let items = database.fetchImagesMissingOCR()
        guard !items.isEmpty else { return }

        for item in items {
            runOCR(for: item)
        }
    }

    private func runOCR(for item: ClipboardItem) {
        guard AppSettings.shared.isOCREnabled, let data = Data(base64Encoded: item.content) else {
            try? database.updateOCR(for: item.id, preview: item.preview, ocrText: "")
            return
        }

        Task { [weak self] in
            let ocrText = await Task.detached {
                ImageTextRecognizer().recognizeText(in: data)
            }.value
            self?.finishOCR(item: item, data: data, ocrText: ocrText)
        }
    }

    private func finishOCR(item: ClipboardItem, data: Data, ocrText: String) {
        let image = NSImage(data: data)
        let preview = image?.previewText(ocrText: ocrText) ?? item.preview
        try? database.updateOCR(for: item.id, preview: preview, ocrText: ocrText)
        onChange?()
    }
}
