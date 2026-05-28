import AppKit
import PasteGlideShared

extension ClipboardKind {
    var borderColor: NSColor {
        switch self {
        case .youtube: .systemRed
        case .url: .systemTeal
        case .text: .systemYellow
        case .password: .systemPurple
        case .number: .systemBlue
        case .image: .systemGreen
        }
    }
}
