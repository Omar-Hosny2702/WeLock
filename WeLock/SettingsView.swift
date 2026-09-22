import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator
    @State private var selection: WeLockSection? = .general
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        WeLockMark(size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("WeLock")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("by Omar Hosny")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Private app protection for macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)

                List(WeLockSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 205)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralView()
                case .apps:
                    AppsView(searchText: $searchText)
                case .security:
                    SecurityView()
                case .appearance:
                    AppearanceView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(colorScheme)
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var colorScheme: ColorScheme? {
        switch coordinator.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct GeneralView: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator

    var body: some View {
        ScrollView {
            SettingsPage(title: "General", subtitle: "Choose how WeLock starts and behaves day to day.") {
                SettingsCard {
                    HStack(spacing: 14) {
                        StatusDot(isActive: !coordinator.protectedApps.filter(\.isProtected).isEmpty)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Protection engine")
                                .font(.headline)
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Lock All Now") {
                            coordinator.lockAllNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                }

                SettingsCard(title: "Startup") {
                    SettingToggle(
                        title: "Launch WeLock at login",
                        subtitle: "Start the protection engine when you sign in to macOS.",
                        isOn: Binding(
                            get: { coordinator.settings.launchAtLogin },
                            set: { coordinator.setLaunchAtLogin($0) }
                        )
                    )
                }

                SettingsCard(title: "System events") {
                    SettingToggle(
                        title: "Lock protected apps when Mac sleeps or locks",
                        subtitle: "The next time a protected app is opened, authentication will be required.",
                        isOn: boolBinding(\.lockOnSleep)
                    )
                    Divider()
                    SettingToggle(
                        title: "Show lock notifications",
                        subtitle: "Keep notifications local to this Mac; no activity is sent anywhere.",
                        isOn: Binding(
                            get: { coordinator.settings.showNotifications },
                            set: { coordinator.setNotifications($0) }
                        )
                    )
                    Divider()
                    SettingToggle(
                        title: "Show menu-bar controls",
                        subtitle: "Keep Lock All Now and status controls in the menu bar.",
                        isOn: boolBinding(\.showMenuBar)
                    )
                }
            }
        }
    }

    private var statusText: String {
        let count = coordinator.protectedApps.filter(\.isProtected).count
        return count == 0 ? "No applications are currently protected." : "Watching (count) protected application\(count == 1 ? "" : "s")."
    }

    private func boolBinding(_ keyPath: WritableKeyPath<WeLockSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { coordinator.settings[keyPath: keyPath] },
            set: { value in coordinator.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct AppsView: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator
    @Binding var searchText: String

    private var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return coordinator.catalog.apps }
        return coordinator.catalog.apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            SettingsPage(title: "Apps", subtitle: "Choose which installed apps WeLock should protect.") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search installed applications", text: $searchText)
                        .textFieldStyle(.plain)
                    Button {
                        addApplication()
                    } label: {
                        Label("Add Application", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
                .padding(12)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

                SettingsCard(title: "Protected apps") {
                    if coordinator.protectedApps.isEmpty {
                        EmptyState(
                            icon: "lock.open",
                            title: "No protected apps yet",
                            message: "Search below or use Add Application to choose an app such as WhatsApp."
                        )
                    } else {
                        ForEach(coordinator.protectedApps) { app in
                            ProtectedAppRow(app: app)
                            if app.id != coordinator.protectedApps.last?.id { Divider() }
                        }
                    }
                }

                SettingsCard(title: "Installed applications") {
                    if filteredApps.isEmpty {
                        EmptyState(icon: "app.dashed", title: "No matching applications", message: "Try a different name or bundle identifier.")
                    } else {
                        ForEach(filteredApps.prefix(80)) { app in
                            InstalledAppRow(app: app)
                            if app.id != filteredApps.prefix(80).last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .onAppear { coordinator.catalog.refresh() }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application to protect"
        panel.message = "WeLock will protect only the application you choose."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                coordinator.addOrUpdateApp(ProtectedApp(
                    bundleIdentifier: bundleIdentifier,
                    displayName: name,
                    path: url.path
                ))
            }
            coordinator.catalog.refresh()
        }
    }
}

private struct InstalledAppRow: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator
    let app: InstalledApp

    private var alreadyAdded: Bool {
        coordinator.protectedApps.contains { $0.bundleIdentifier == app.bundleIdentifier }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: coordinator.icon(for: app))
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(alreadyAdded ? "Added" : "Protect") {
                coordinator.addOrUpdateApp(ProtectedApp(
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.displayName,
                    path: app.path
                ))
            }
            .buttonStyle(.bordered)
            .disabled(alreadyAdded)
        }
        .padding(.vertical, 3)
    }
}

private struct ProtectedAppRow: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator
    let app: ProtectedApp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: coordinator.appIcon(for: app))
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.body.weight(.semibold))
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Toggle("Protect", isOn: Binding(
                    get: { app.isProtected },
                    set: { value in
                        var next = app
                        next.isProtected = value
                        coordinator.addOrUpdateApp(next)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Protect \(app.displayName)")
            }

            HStack(spacing: 18) {
                Label {
                    Text("Re-lock delay")
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                Picker("Re-lock delay", selection: Binding(
                    get: { app.relockDelayOverride ?? .off },
                    set: { value in
                        var next = app
                        next.relockDelayOverride = value == .off ? nil : value
                        coordinator.addOrUpdateApp(next)
                    }
                )) {
                    Text("Use global").tag(DelayOption.off)
                    ForEach(DelayOption.allCases.filter { $0 != .off }) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Toggle("Auto-close after relock", isOn: Binding(
                    get: { app.autoClose },
                    set: { value in
                        var next = app
                        next.autoClose = value
                        coordinator.addOrUpdateApp(next)
                    }
                ))
                .toggleStyle(.checkbox)
                .disabled(!app.isProtected)
                .help("Optional and separate from Lock. Enabling protection alone never quits the app.")

                Spacer()

                Button(role: .destructive) {
                    coordinator.removeApp(app.bundleIdentifier)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(app.displayName) from WeLock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SecurityView: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator

    var body: some View {
        ScrollView {
            SettingsPage(title: "Security", subtitle: "Control when protected apps become locked and how authentication works.") {
                SettingsCard(title: "App switching") {
                    SettingToggle(
                        title: "Lock when a protected app loses focus",
                        subtitle: "This covers Command-Tab, Dock clicks, Spaces, Mission Control and other app switches.",
                        isOn: Binding(
                            get: { coordinator.settings.lockOnAppSwitch },
                            set: { value in coordinator.updateSettings { $0.lockOnAppSwitch = value } }
                        )
                    )
                    Divider()
                    SettingPicker(
                        title: "Re-lock delay",
                        subtitle: "The protected app is locked after it is no longer the frontmost app.",
                        selection: Binding(
                            get: { coordinator.settings.appSwitchDelay },
                            set: { value in coordinator.updateSettings { $0.appSwitchDelay = value } }
                        ),
                        options: DelayOption.allCases.filter { $0 != .off }
                    )
                }

                SettingsCard(title: "Idle protection") {
                    SettingPicker(
                        title: "Lock after inactivity",
                        subtitle: "Locks protected apps after no keyboard, mouse or scroll input. It never covers unrelated apps.",
                        selection: Binding(
                            get: { coordinator.settings.idleLock },
                            set: { value in coordinator.updateSettings { $0.idleLock = value } }
                        ),
                        options: DelayOption.allCases
                    )
                }

                SettingsCard(title: "Authentication") {
                    SettingPicker(
                        title: "Authentication grace period",
                        subtitle: "After a successful authentication, avoid asking again for this period. Nothing is stored as a password.",
                        selection: Binding(
                            get: { coordinator.settings.authenticationGrace },
                            set: { value in coordinator.updateSettings { $0.authenticationGrace = value } }
                        ),
                        options: [.off, .fifteenSeconds, .thirtySeconds, .oneMinute, .fiveMinutes, .fifteenMinutes]
                    )
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: "touchid")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LocalAuthentication")
                                .font(.body.weight(.medium))
                            Text("WeLock asks macOS for Touch ID or the normal Mac authentication flow. It never receives or stores your password.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(authenticationStatus)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(coordinator.authenticationAvailability.available ? .green : .orange)
                    }
                }

                SettingsCard(title: "Accessibility permission") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: coordinator.accessibilityIsTrusted ? "checkmark.shield.fill" : "hand.raised.fill")
                            .foregroundStyle(coordinator.accessibilityIsTrusted ? .green : .orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(coordinator.accessibilityIsTrusted ? "Accessibility is enabled" : "Accessibility permission is recommended")
                                .font(.body.weight(.medium))
                            Text("WeLock uses this permission only to read protected app window geometry and keep its app-scoped shield aligned. macOS may still expose special windows or transitions that cannot be covered.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open System Settings") {
                            coordinator.requestAccessibilityPermission()
                            coordinator.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var authenticationStatus: String {
        coordinator.authenticationAvailability.available ? "Ready" : "Unavailable"
    }
}

private struct AppearanceView: View {
    @EnvironmentObject private var coordinator: ProtectionCoordinator

    var body: some View {
        ScrollView {
            SettingsPage(title: "Appearance", subtitle: "Give WeLock the look that fits your Mac.") {
                SettingsCard(title: "Colour scheme") {
                    Picker("Colour scheme", selection: Binding(
                        get: { coordinator.settings.appearance },
                        set: { value in coordinator.updateSettings { $0.appearance = value } }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SettingsCard(title: "WeLock identity") {
                    HStack(spacing: 14) {
                        WeLockMark(size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quiet protection, native to your Mac.")
                                .font(.headline)
                            Text("A dark navy surface, cyan signal and familiar macOS materials keep the security state clear without getting in your way.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            SettingsPage(title: "About", subtitle: "Private app protection, built for macOS.") {
                SettingsCard {
                    HStack(alignment: .center, spacing: 20) {
                        WeLockMark(size: 92)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("WeLock")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("by Omar Hosny")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Version 1.0.9")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.cyan.opacity(0.14), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    AboutFeature(
                        icon: "lock.shield.fill",
                        title: "App-scoped",
                        detail: "Only the protected application's visible windows are covered."
                    )
                    AboutFeature(
                        icon: "touchid",
                        title: "Native authentication",
                        detail: "Unlock with Touch ID or the Mac login password through macOS."
                    )
                    AboutFeature(
                        icon: "eye.slash.fill",
                        title: "Private by design",
                        detail: "No analytics, tracking, accounts or remote password database."
                    )
                }

                SettingsCard(title: "How WeLock protects apps") {
                    Label("Live window privacy shield", systemImage: "rectangle.inset.filled.and.person.filled")
                        .font(.body.weight(.semibold))
                    Text("When a protected app is locked and frontmost, WeLock places a native blurred shield over only that app's visible window bounds. It does not capture or store an image of the protected app. Switching to another app or Space removes that shield from view, so unrelated apps remain usable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    Label("Security boundary", systemImage: "info.circle")
                        .font(.body.weight(.semibold))
                    Text("macOS does not expose a supported public API that lets WeLock replace another app's window contents or create an OS-level security boundary inside it. The shield is therefore a best-effort privacy barrier. macOS account security and each app's own lock feature remain the stronger option for high-assurance protection.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsCard(title: "Built with") {
                    HStack(spacing: 18) {
                        Label("Swift", systemImage: "swift")
                        Label("SwiftUI", systemImage: "macwindow")
                        Label("LocalAuthentication", systemImage: "touchid")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                Text("WeLock by Omar Hosny · Made for macOS")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
    }
}

private struct AboutFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(30)
        .frame(maxWidth: 820, alignment: .leading)
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct SettingPicker: View {
    let title: String
    let subtitle: String
    @Binding var selection: DelayOption
    let options: [DelayOption]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
            .frame(width: 145)
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? .green : .secondary)
            .frame(width: 10, height: 10)
            .shadow(color: isActive ? .green.opacity(0.45) : .clear, radius: 7)
            .accessibilityLabel(isActive ? "Protection active" : "Protection inactive")
    }
}

struct WeLockMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.10, blue: 0.18), Color(red: 0.02, green: 0.03, blue: 0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "lock.shield.fill")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.cyan)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.cyan.opacity(0.35), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
