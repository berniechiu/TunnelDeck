public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let `default` = AppAppearance.system
    public static let storageKey = "appearance"

    public var id: String { rawValue }
}
