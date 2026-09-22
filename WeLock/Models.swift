import Foundation

enum WeLockSection: String, CaseIterable, Identifiable {
    case general = "General"
    case apps = "Apps"
    case security = "Security"
    case appearance = "Appearance"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .apps: return "square.stack.3d.up"
        case .security: return "lock.shield"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum DelayOption: Int, Codable, CaseIterable, Identifiable {
    case off = -1
    case immediately = 0
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Never"
        case .immediately: return "Immediately"
        case .fifteenSeconds: return "15 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: return "Never"
        case .immediately: return "Now"
        case .fifteenSeconds: return "15s"
        case .thirtySeconds: return "30s"
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        }
    }
}

struct ProtectedApp: Codable, Identifiable, Equatable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var path: String
    var isProtected: Bool
    var autoClose: Bool
    var relockDelayOverride: DelayOption?

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        displayName: String,
        path: String,
        isProtected: Bool = true,
        autoClose: Bool = false,
        relockDelayOverride: DelayOption? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.path = path
        self.isProtected = isProtected
        self.autoClose = autoClose
        self.relockDelayOverride = relockDelayOverride
    }
}

struct WeLockSettings: Codable {
    var launchAtLogin = false
    var lockOnSleep = true
    var idleLock: DelayOption = .fiveMinutes
    var lockOnAppSwitch = true
    var appSwitchDelay: DelayOption = .immediately
    var authenticationGrace: DelayOption = .oneMinute
    var showNotifications = true
    var showMenuBar = true
    var appearance: AppearanceMode = .system
    var protectedApps: [ProtectedApp] = []
}

struct InstalledApp: Identifiable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var path: String

    var id: String { bundleIdentifier }
}

