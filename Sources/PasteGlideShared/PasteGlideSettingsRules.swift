import Foundation

public enum PasteGlideSettingsRules {
    public static let defaultHistoryLimit = 100
    public static let minimumHistoryLimit = 10
    public static let defaultMaxCapturedImageMegabytes = 20
    public static let minimumMaxCapturedImageMegabytes = 1
    public static let maximumMaxCapturedImageMegabytes = 200
    public static let defaultPanelWidthPercent = 86
    public static let minimumPanelWidthPercent = 50
    public static let maximumPanelWidthPercent = 95
    public static let defaultHotKeyCharacter = "V"

    public static func normalizedHistoryLimit(_ value: Int) -> Int {
        max(minimumHistoryLimit, value == 0 ? defaultHistoryLimit : value)
    }

    public static func normalizedRetentionDays(_ value: Int) -> Int {
        max(0, value)
    }

    public static func normalizedMaxCapturedImageMegabytes(_ value: Int) -> Int {
        let effectiveValue = value == 0 ? defaultMaxCapturedImageMegabytes : value
        return min(max(effectiveValue, minimumMaxCapturedImageMegabytes), maximumMaxCapturedImageMegabytes)
    }

    public static func normalizedPanelWidthPercent(_ value: Int) -> Int {
        let effectiveValue = value == 0 ? defaultPanelWidthPercent : value
        return min(max(effectiveValue, minimumPanelWidthPercent), maximumPanelWidthPercent)
    }

    public static func normalizedExcludedApplications(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func normalizedHotKeyCharacter(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let first = normalized.first else {
            return defaultHotKeyCharacter
        }
        return String(first)
    }

    public static func isApplicationExcluded(bundleIdentifier: String?, localizedName: String?, exclusions: [String]) -> Bool {
        let candidates = [bundleIdentifier, localizedName]
            .compactMap { $0?.lowercased() }
        return normalizedExcludedApplications(exclusions)
            .map { $0.lowercased() }
            .contains { excluded in
                candidates.contains { $0.contains(excluded) }
            }
    }
}
