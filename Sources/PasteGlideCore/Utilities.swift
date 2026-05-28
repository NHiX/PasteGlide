import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

func sqliteTransient() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public enum PanelPosition: String, CaseIterable {
    case bottom
    case top
    case left
    case right
    case center

    public var title: String {
        switch self {
        case .bottom: "Bas"
        case .top: "Haut"
        case .left: "Gauche"
        case .right: "Droite"
        case .center: "Milieu"
        }
    }

    var isVertical: Bool {
        self == .left || self == .right || self == .center
    }
}

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    public var historyLimit: Int {
        get { max(10, defaults.integer(forKey: "historyLimit") == 0 ? 100 : defaults.integer(forKey: "historyLimit")) }
        set { defaults.set(max(10, newValue), forKey: "historyLimit") }
    }

    public var retentionDays: Int {
        get { defaults.integer(forKey: "retentionDays") }
        set { defaults.set(max(0, newValue), forKey: "retentionDays") }
    }

    public var isOCREnabled: Bool {
        get { defaults.object(forKey: "isOCREnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isOCREnabled") }
    }

    public var shouldCapturePasswords: Bool {
        get { defaults.object(forKey: "shouldCapturePasswords") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shouldCapturePasswords") }
    }

    public var shouldMaskSensitiveContent: Bool {
        get { defaults.object(forKey: "shouldMaskSensitiveContent") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shouldMaskSensitiveContent") }
    }

    public var capturePauseUntil: Date? {
        get {
            let timestamp = defaults.double(forKey: "capturePauseUntil")
            guard timestamp > Date().timeIntervalSince1970 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "capturePauseUntil") }
    }

    public var isCapturePaused: Bool {
        capturePauseUntil != nil
    }

    public var excludedApplications: [String] {
        get { defaults.stringArray(forKey: "excludedApplications") ?? [] }
        set { defaults.set(newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, forKey: "excludedApplications") }
    }

    public var hotKeyCharacter: String {
        get { defaults.string(forKey: "hotKeyCharacter") ?? "V" }
        set { defaults.set(String(newValue.uppercased().prefix(1)), forKey: "hotKeyCharacter") }
    }

    public var panelWidthPercent: Int {
        get { defaults.integer(forKey: "panelWidthPercent") == 0 ? 86 : defaults.integer(forKey: "panelWidthPercent") }
        set { defaults.set(min(max(newValue, 50), 95), forKey: "panelWidthPercent") }
    }

    public var panelPosition: PanelPosition {
        get {
            let rawValue = defaults.string(forKey: "panelPosition") ?? PanelPosition.bottom.rawValue
            return PanelPosition(rawValue: rawValue) ?? .bottom
        }
        set { defaults.set(newValue.rawValue, forKey: "panelPosition") }
    }

    func isExcluded(application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        let candidates = [application.bundleIdentifier, application.localizedName].compactMap { $0?.lowercased() }
        return excludedApplications.map { $0.lowercased() }.contains { excluded in
            candidates.contains { $0.contains(excluded) }
        }
    }

    var hotKeyCode: UInt32 {
        switch hotKeyCharacter.uppercased() {
        case "A": UInt32(kVK_ANSI_A)
        case "B": UInt32(kVK_ANSI_B)
        case "C": UInt32(kVK_ANSI_C)
        case "D": UInt32(kVK_ANSI_D)
        case "E": UInt32(kVK_ANSI_E)
        case "F": UInt32(kVK_ANSI_F)
        case "G": UInt32(kVK_ANSI_G)
        case "H": UInt32(kVK_ANSI_H)
        case "I": UInt32(kVK_ANSI_I)
        case "J": UInt32(kVK_ANSI_J)
        case "K": UInt32(kVK_ANSI_K)
        case "L": UInt32(kVK_ANSI_L)
        case "M": UInt32(kVK_ANSI_M)
        case "N": UInt32(kVK_ANSI_N)
        case "O": UInt32(kVK_ANSI_O)
        case "P": UInt32(kVK_ANSI_P)
        case "Q": UInt32(kVK_ANSI_Q)
        case "R": UInt32(kVK_ANSI_R)
        case "S": UInt32(kVK_ANSI_S)
        case "T": UInt32(kVK_ANSI_T)
        case "U": UInt32(kVK_ANSI_U)
        case "W": UInt32(kVK_ANSI_W)
        case "X": UInt32(kVK_ANSI_X)
        case "Y": UInt32(kVK_ANSI_Y)
        case "Z": UInt32(kVK_ANSI_Z)
        default: UInt32(kVK_ANSI_V)
        }
    }
}

func hashContent(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
