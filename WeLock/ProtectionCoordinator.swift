import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class ProtectionCoordinator: ObservableObject {
    @Published private(set) var settings: WeLockSettings
    @Published private(set) var frontmostAppName = "No active app"
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastAuthenticationError: String?

    let store: SettingsStore
    let catalog: AppCatalog

    private let authenticator = Authenticator()
    private let notifications = NotificationManager()
    private let shield = WindowShieldManager()
    private var observerTokens: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var idleTimer: Timer?
    private var relockWorkItems: [String: DispatchWorkItem] = [:]
    private var lockedBundleIdentifiers: Set<String>
    private var unlockedUntil: [String: Date] = [:]
    private var currentBundleIdentifier: String?
    private var authenticationBundleIdentifier: String?
    private var lastIdleLock = Date.distantPast

    convenience init() {
        self.init(store: SettingsStore(), catalog: AppCatalog())
    }

    init(store: SettingsStore, catalog: AppCatalog) {
        self.store = store
        self.catalog = catalog
        self.settings = store.settings
        self.lockedBundleIdentifiers = Set(store.settings.protectedApps.map(\.bundleIdentifier))
        catalog.refresh()
        beginMonitoring()
    }

    deinit {
        observerTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        pollTimer?.invalidate()
        idleTimer?.invalidate()
    }

    var protectedApps: [ProtectedApp] {
        settings.protectedApps
    }

    var accessibilityIsTrusted: Bool {
        shield.isAccessibilityTrusted
    }

    var authenticationAvailability: (available: Bool, message: String?) {
        authenticator.canAuthenticate()
    }

    func appIcon(for app: ProtectedApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.path)
    }

    func icon(for installedApp: InstalledApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: installedApp.path)
    }

    func appIsLocked(_ bundleIdentifier: String) -> Bool {
        lockedBundleIdentifiers.contains(bundleIdentifier)
    }

    func updateSettings(_ mutation: (inout WeLockSettings) -> Void) {
        store.update(mutation)
        settings = store.settings
        reconcileProtectionSet()
    }

    func addOrUpdateApp(_ app: ProtectedApp) {
        store.addOrUpdate(app)
        settings = store.settings
        if app.isProtected {
            lockedBundleIdentifiers.insert(app.bundleIdentifier)
        } else {
            lockedBundleIdentifiers.remove(app.bundleIdentifier)
        }
        reconcileProtectionSet()
    }

    func removeApp(_ bundleIdentifier: String) {
        cancelRelock(for: bundleIdentifier)
        store.remove(bundleIdentifier: bundleIdentifier)
        settings = store.settings
        lockedBundleIdentifiers.remove(bundleIdentifier)
        unlockedUntil.removeValue(forKey: bundleIdentifier)
        refreshShield()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func lockAllNow() {
        settings.protectedApps.filter(\.isProtected).forEach {
            lock(bundleIdentifier: $0.bundleIdentifier, reason: "Manual lock", allowAutoClose: false)
        }
        showNotificationIfEnabled(title: "WeLock locked your apps", body: "Protected apps are locked until you authenticate.")
        refreshShield()
    }

    func authenticateCurrentApp() {
        guard let bundleIdentifier = currentBundleIdentifier,
              let app = protectedApp(bundleIdentifier: bundleIdentifier),
              app.isProtected,
              appIsLocked(bundleIdentifier),
              !isAuthenticating else { return }

        authenticationBundleIdentifier = bundleIdentifier
        isAuthenticating = true
        lastAuthenticationError = nil
        authenticator.authenticate(reason: "Unlock \(app.displayName) in WeLock") { [weak self] success, error in
            guard let self else { return }
            self.isAuthenticating = false
            defer { self.authenticationBundleIdentifier = nil }

            if success {
                self.lockedBundleIdentifiers.remove(bundleIdentifier)
                let grace = self.settings.authenticationGrace.rawValue
                if grace > 0 {
                    self.unlockedUntil[bundleIdentifier] = Date().addingTimeInterval(TimeInterval(grace))
                } else {
                    self.unlockedUntil.removeValue(forKey: bundleIdentifier)
                }
                // Successful LocalAuthentication is the only unlock path.
                // Until this point refreshShield() keeps the protected window
                // continuously obscured, even if focus/Spaces/window ordering
                // changes underneath the authentication UI.
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                    self.shield.restoreConcealedApplication(running)
                    running.activate(options: [])
                }
                self.shield.hide()
                self.showNotificationIfEnabled(title: "Unlocked", body: "\(app.displayName) is available.")
            } else {
                self.lastAuthenticationError = error ?? "Authentication was not completed."
                self.refreshShield()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            updateSettings { $0.launchAtLogin = false }
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            updateSettings { $0.launchAtLogin = enabled }
        } catch {
            updateSettings { $0.launchAtLogin = false }
        }
    }

    func setNotifications(_ enabled: Bool) {
        if enabled {
            notifications.requestPermission()
        }
        updateSettings { $0.showNotifications = enabled }
    }

    private func beginMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.handleActivation(notification)
        })
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.catalog.refresh()
            self?.pollFrontmost()
        })
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.catalog.refresh()
            self?.pollFrontmost()
        })
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.lockOnSleep else { return }
            self.lockAllNow()
        })
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.lockOnSleep else { return }
            self.lockAllNow()
        })
        observerTokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        })

        // A short watchdog interval is intentional: macOS can reorder windows
        // during Space, Mission Control, Stage Manager and split/side-by-side
        // transitions without sending a reliable activation notification.
        // While an app remains locked, continuously reassert its app-scoped
        // shield. The shield is removed only after successful authentication.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.pollFrontmost()
            self?.refreshShield()
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdleLock()
        }
        pollFrontmost()
    }

    private func handleActivation(_ notification: Notification) {
        let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        transition(to: runningApplication)
    }

    private func pollFrontmost() {
        transition(to: NSWorkspace.shared.frontmostApplication)
    }

    private func handleSpaceChange() {
        // Do not tear down the protected-app shield while LocalAuthentication
        // owns the foreground UI. Trackpad Space swipes / Mission Control can
        // briefly report the protected window as off-screen while the secure
        // authentication sheet is still active. Hiding here would expose the
        // protected app behind Apple's Touch ID/password UI. The shield is
        // removed only after successful authentication (or normal app/Space
        // transitions once authentication is no longer active).
        if isAuthenticating, authenticationBundleIdentifier != nil {
            refreshShield()
            return
        }

        guard let bundleIdentifier = currentBundleIdentifier,
              let app = protectedApp(bundleIdentifier: bundleIdentifier),
              app.isProtected,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            pollFrontmost()
            return
        }

        if !shield.hasVisibleWindows(for: running.processIdentifier) {
            if !appIsLocked(bundleIdentifier) {
                scheduleRelock(for: app)
            }
            shield.hide()
        } else {
            pollFrontmost()
        }
    }

    private func transition(to runningApplication: NSRunningApplication?) {
        let nextBundleIdentifier = runningApplication?.bundleIdentifier

        // LocalAuthentication temporarily makes Apple's authentication UI (or
        // WeLock itself) appear frontmost. That is not a real app switch from
        // the protected app. Keep the protected app as our logical foreground
        // target until authentication completes, otherwise the normal
        // transition path hides its shield and leaks its contents behind the
        // Touch ID/password sheet.
        if isAuthenticating,
           let authenticationBundleIdentifier,
           currentBundleIdentifier == authenticationBundleIdentifier,
           nextBundleIdentifier != authenticationBundleIdentifier {
            refreshShield()
            return
        }

        let previousBundleIdentifier = currentBundleIdentifier

        if let nextBundleIdentifier,
           let expiration = unlockedUntil[nextBundleIdentifier],
           expiration <= Date() {
            unlockedUntil.removeValue(forKey: nextBundleIdentifier)
            lockedBundleIdentifiers.insert(nextBundleIdentifier)
        }

        if nextBundleIdentifier == currentBundleIdentifier {
            if let name = runningApplication?.localizedName, name != frontmostAppName {
                frontmostAppName = name
            }
            refreshShield()
            authenticateIfRequired()
            return
        }

        currentBundleIdentifier = nextBundleIdentifier
        frontmostAppName = runningApplication?.localizedName ?? "No active app"

        if let previousBundleIdentifier,
           previousBundleIdentifier != nextBundleIdentifier,
           let previous = protectedApp(bundleIdentifier: previousBundleIdentifier),
           previous.isProtected,
           !appIsLocked(previousBundleIdentifier) {
            scheduleRelock(for: previous)
        }

        if let nextBundleIdentifier,
           let next = protectedApp(bundleIdentifier: nextBundleIdentifier),
           next.isProtected {
            cancelRelock(for: nextBundleIdentifier)
            if unlockedUntil[nextBundleIdentifier].map({ $0 <= Date() }) == true {
                lockedBundleIdentifiers.insert(nextBundleIdentifier)
                unlockedUntil.removeValue(forKey: nextBundleIdentifier)
            }
        }

        refreshShield()
        authenticateIfRequired()
    }

    private func authenticateIfRequired() {
        guard let bundleIdentifier = currentBundleIdentifier,
              let app = protectedApp(bundleIdentifier: bundleIdentifier),
              app.isProtected,
              appIsLocked(bundleIdentifier),
              !isAuthenticating,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first != nil else { return }
        // v1.2.2 hides the protected application while locked, so visible-window
        // presence cannot be an authentication prerequisite. An activation
        // attempt is enough to request LocalAuthentication.
        authenticateCurrentApp()
    }

    private func refreshShield() {
        // v1.2.2 fails closed by hiding the protected application itself while
        // it is locked. This avoids the fundamental cross-process Space
        // animation problem: there are no WhatsApp pixels for WindowServer to
        // slide out from behind a separate WeLock panel.
        //
        // The app-sized shield is needed only while authentication is active.
        // At all other times the protected application remains hidden, so we
        // must not leave a panel sitting above an unrelated foreground app.
        if isAuthenticating,
           let bundleIdentifier = authenticationBundleIdentifier ?? currentBundleIdentifier,
           let app = protectedApp(bundleIdentifier: bundleIdentifier),
           app.isProtected,
           appIsLocked(bundleIdentifier),
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            shield.show(for: running, appName: app.displayName) { [weak self] in
                self?.authenticateCurrentApp()
            }
            _ = shield.conceal(running)
            return
        }

        var concealedAnyLockedApp = false
        for app in settings.protectedApps where app.isProtected && appIsLocked(app.bundleIdentifier) {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first else { continue }

            // If the user/Dock/macOS has just unhidden a locked app, capture
            // its current frame before hiding it again. Authentication is
            // started by the activation path immediately afterwards.
            if !running.isHidden {
                shield.show(for: running, appName: app.displayName) { [weak self] in
                    guard let self else { return }
                    self.currentBundleIdentifier = app.bundleIdentifier
                    self.frontmostAppName = app.displayName
                    self.authenticateCurrentApp()
                }
                _ = shield.conceal(running)
                concealedAnyLockedApp = true
            } else if shield.isConcealed(running.processIdentifier) {
                concealedAnyLockedApp = true
            }
        }

        // Once the locked application is actually hidden, the privacy panel is
        // unnecessary and could otherwise cover Chrome/Spotify at the old
        // coordinates. Keep it only while LocalAuthentication is in progress.
        if !isAuthenticating || concealedAnyLockedApp {
            shield.hide()
        }
    }

    private func scheduleRelock(for app: ProtectedApp) {
        guard settings.lockOnAppSwitch else { return }
        cancelRelock(for: app.bundleIdentifier)
        let delay = app.relockDelayOverride ?? settings.appSwitchDelay
        guard delay != .off else { return }

        if delay == .immediately {
            lock(bundleIdentifier: app.bundleIdentifier, reason: "App switch", allowAutoClose: true)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentBundleIdentifier != app.bundleIdentifier,
                  !self.appIsLocked(app.bundleIdentifier) else { return }
            self.lock(bundleIdentifier: app.bundleIdentifier, reason: "App switch", allowAutoClose: true)
        }
        relockWorkItems[app.bundleIdentifier] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(delay.rawValue), execute: workItem)
    }

    private func cancelRelock(for bundleIdentifier: String) {
        relockWorkItems[bundleIdentifier]?.cancel()
        relockWorkItems.removeValue(forKey: bundleIdentifier)
    }

    private func lock(bundleIdentifier: String, reason: String, allowAutoClose: Bool) {
        lockedBundleIdentifiers.insert(bundleIdentifier)
        unlockedUntil.removeValue(forKey: bundleIdentifier)
        // A relock can happen while another app is frontmost (for example,
        // Chrome beside WhatsApp). Refresh immediately so the protected
        // window is covered without waiting for another workspace event.
        refreshShield()
        guard allowAutoClose,
              let app = protectedApp(bundleIdentifier: bundleIdentifier),
              app.autoClose,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              bundleIdentifier != currentBundleIdentifier else { return }
        running.terminate()
        showNotificationIfEnabled(title: "\(app.displayName) closed", body: "It was closed after WeLock locked it.")
        _ = reason
    }

    private func checkIdleLock() {
        guard settings.idleLock != .off,
              settings.idleLock.rawValue > 0,
              Date().timeIntervalSince(lastIdleLock) > 10 else { return }

        let idleSeconds = currentIdleSeconds()
        guard idleSeconds >= TimeInterval(settings.idleLock.rawValue) else { return }
        lastIdleLock = Date()
        lockAllNow()
    }

    private func currentIdleSeconds() -> TimeInterval {
        let state: CGEventSourceStateID = .combinedSessionState
        let events: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return events.map {
            CGEventSource.secondsSinceLastEventType(state, eventType: $0)
        }.min() ?? 0
    }

    private func reconcileProtectionSet() {
        let protectedIdentifiers = Set(settings.protectedApps.filter(\.isProtected).map(\.bundleIdentifier))
        lockedBundleIdentifiers.formIntersection(protectedIdentifiers)
        for identifier in protectedIdentifiers where !unlockedUntil.keys.contains(identifier) && !lockedBundleIdentifiers.contains(identifier) {
            lockedBundleIdentifiers.insert(identifier)
        }
        for identifier in settings.protectedApps.map(\.bundleIdentifier) where !protectedIdentifiers.contains(identifier) {
            cancelRelock(for: identifier)
            unlockedUntil.removeValue(forKey: identifier)
        }
        refreshShield()
    }

    private func protectedApp(bundleIdentifier: String) -> ProtectedApp? {
        settings.protectedApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func showNotificationIfEnabled(title: String, body: String) {
        guard settings.showNotifications else { return }
        notifications.post(title: title, body: body)
    }
}
