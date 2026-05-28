import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

public final class ClipboardClassifier {
    public init() {}

    public func classifyString(_ value: String) -> ClipboardKind {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isYouTubeURL(trimmed) {
            return .youtube
        }
        if trimmed.range(of: #"^\d{2,}$"#, options: .regularExpression) != nil {
            return .number
        }
        if isLikelyPassword(trimmed) {
            return .password
        }
        return .text
    }

    public func preview(for value: String, kind: ClipboardKind) -> String {
        if kind == .password {
            return String(repeating: "•", count: min(max(value.count, 8), 16))
        }

        let normalized = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 80 {
            return normalized
        }
        return String(normalized.prefix(77)) + "..."
    }

    private func isYouTubeURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host?.lowercased() else {
            return false
        }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private func isLikelyPassword(_ value: String) -> Bool {
        guard (8...128).contains(value.count), value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }

        let hasLower = value.range(of: #"[a-z]"#, options: .regularExpression) != nil
        let hasUpper = value.range(of: #"[A-Z]"#, options: .regularExpression) != nil
        let hasDigit = value.range(of: #"\d"#, options: .regularExpression) != nil
        let hasSymbol = value.range(of: #"[^A-Za-z0-9]"#, options: .regularExpression) != nil
        let classes = [hasLower, hasUpper, hasDigit, hasSymbol].filter { $0 }.count

        return classes >= 3
    }
}
