import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

extension NSImage {
    func pngBase64() -> String? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])?.base64EncodedString()
    }

    func previewText(ocrText: String = "") -> String {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return "Image"
        }
        let dimensions = "Image \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)"
        guard !ocrText.isEmpty else {
            return dimensions
        }
        return "\(dimensions) · OCR \(ocrText.count) caractères"
    }

    var cgImageForVision: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

extension String {
    var fourCharCode: FourCharCode {
        utf8.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
