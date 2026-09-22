import AppKit
import Foundation

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []

    private let fileManager = FileManager.default

    func refresh() {
        var candidates: [String: InstalledApp] = [:]
        let discoveredApps = searchRoots().flatMap { root -> [InstalledApp] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            var discovered: [InstalledApp] = []
            for case let url as URL in enumerator {
                guard url.pathExtension == "app",
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier else { continue }
                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                discovered.append(
                    InstalledApp(bundleIdentifier: bundleIdentifier, displayName: displayName, path: url.path)
                )
            }
            return discovered
        }

        for app in discoveredApps {
            candidates[app.bundleIdentifier] = app
        }

        for running in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = running.bundleIdentifier,
                  let url = running.bundleURL else { continue }
            let name = running.localizedName ?? url.deletingPathExtension().lastPathComponent
            candidates[bundleIdentifier] = InstalledApp(bundleIdentifier: bundleIdentifier, displayName: name, path: url.path)
        }

        apps = candidates.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func app(for bundleIdentifier: String) -> InstalledApp? {
        apps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func searchRoots() -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true)
        ]
        if let userApplications = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(userApplications)
        }
        return roots.filter { fileManager.fileExists(atPath: $0.path) }
    }
}
