import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: WeLockSettings

    private let defaults: UserDefaults
    private let key = "weLock.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WeLockSettings.self, from: data) {
            settings = decoded
        } else {
            settings = WeLockSettings()
        }
    }

    func update(_ mutation: (inout WeLockSettings) -> Void) {
        var next = settings
        mutation(&next)
        settings = next
        save()
    }

    func replace(_ value: WeLockSettings) {
        settings = value
        save()
    }

    func addOrUpdate(_ app: ProtectedApp) {
        update { value in
            if let index = value.protectedApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                value.protectedApps[index] = app
            } else {
                value.protectedApps.append(app)
            }
            value.protectedApps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    func remove(bundleIdentifier: String) {
        update { value in
            value.protectedApps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

