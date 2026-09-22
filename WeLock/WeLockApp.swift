import AppKit
import SwiftUI

@main
struct WeLockApp: App {
    @StateObject private var coordinator = ProtectionCoordinator()

    var body: some Scene {
        WindowGroup("WeLock Settings", id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
        }
        .defaultSize(width: 1020, height: 700)
        .windowResizability(.contentSize)

        // Keep the status item structurally stable. Binding MenuBarExtra's
        // insertion directly to @Published settings can make SwiftUI write
        // back during a view update and create a render/update loop.
        MenuBarExtra("WeLock", systemImage: "lock.shield.fill") {
            MenuBarContent()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("WeLock")
            .font(.headline)

        if coordinator.protectedApps.filter(\.isProtected).isEmpty {
            Text("No protected apps")
                .foregroundStyle(.secondary)
        } else {
            Text("Watching \(coordinator.protectedApps.filter(\.isProtected).count) app\(coordinator.protectedApps.filter(\.isProtected).count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button {
            coordinator.lockAllNow()
        } label: {
            Label("Lock All Now", systemImage: "lock.fill")
        }
        .keyboardShortcut("l", modifiers: [.command, .option])

        Button {
            openWindow(id: "settings")
        } label: {
            Label("Open WeLock Settings…", systemImage: "gearshape")
        }

        Divider()

        Button("Quit WeLock") {
            NSApplication.shared.terminate(nil)
        }
    }
}
