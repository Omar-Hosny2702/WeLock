import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class WindowShieldManager {
    private var panels: [ShieldPanel] = []

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func hasVisibleWindows(for pid: pid_t) -> Bool {
        !windowFrames(for: pid).filter { $0.width > 80 && $0.height > 60 }.isEmpty
    }

    /// True only when Core Graphics reports a real on-screen layer-0 window
    /// for this process in the current Space. Unlike the Accessibility
    /// fallback, this deliberately does not treat off-Space windows as visible.
    func hasOnScreenWindows(for pid: pid_t) -> Bool {
        !coreGraphicsWindowFrames(for: pid).isEmpty
    }

    func show(
        for runningApplication: NSRunningApplication,
        appName: String,
        onUnlock: @escaping () -> Void
    ) {
        let frames = windowFrames(for: runningApplication.processIdentifier)
        let usableFrames = frames.filter { $0.width > 80 && $0.height > 60 }
        // Never fall back to covering the display. If macOS does not expose a
        // protected app window in the current Space, showing nothing is safer
        // than accidentally shielding an unrelated application.
        guard !usableFrames.isEmpty else {
            // Window visibility can momentarily disappear from Core Graphics
            // during Space/Mission Control transitions. Keep the last known
            // app-scoped shield in place rather than flashing protected
            // content. The coordinator explicitly hides the shield when a
            // genuine app/Space transition requires it.
            return
        }
        let targetFrames = usableFrames

        while panels.count < targetFrames.count {
            panels.append(ShieldPanel())
        }
        while panels.count > targetFrames.count {
            panels.removeLast().orderOut(nil)
        }

        for (index, frame) in targetFrames.enumerated() {
            let panel = panels[index]
            panel.updateContent(appName: appName, onUnlock: onUnlock)
            panel.setFrame(frame, display: true)
            // Reassert the shield above normal application windows on every
            // coordinator tick. macOS can reorder another app's window after
            // a Space/Stage Manager/side-by-side transition even though the
            // shield itself never changed lock state. A locked app must remain
            // visually covered until authentication succeeds.
            panel.orderFrontRegardless()
        }
    }

    /// Fail closed at the application level. Unlike a separate NSPanel, a
    /// hidden NSRunningApplication has no ordinary app windows for Mission
    /// Control or an interactive Space swipe to expose. We remember whether
    /// WeLock performed the hide so successful authentication only restores
    /// applications hidden by WeLock itself.
    private(set) var concealedApplicationPIDs: Set<pid_t> = []

    @discardableResult
    func conceal(_ runningApplication: NSRunningApplication) -> Bool {
        let pid = runningApplication.processIdentifier
        guard !runningApplication.isHidden else {
            return concealedApplicationPIDs.contains(pid)
        }

        let didHide = runningApplication.hide()
        if didHide {
            concealedApplicationPIDs.insert(pid)
        }
        return didHide
    }

    func isConcealed(_ pid: pid_t) -> Bool {
        concealedApplicationPIDs.contains(pid)
    }

    /// Restore only an application that WeLock hid itself.
    func restoreConcealedApplication(_ runningApplication: NSRunningApplication) {
        let pid = runningApplication.processIdentifier
        guard concealedApplicationPIDs.remove(pid) != nil else { return }
        runningApplication.unhide()
    }

    /// Forget state for an app that terminated while locked.
    func forgetConcealedApplication(pid: pid_t) {
        concealedApplicationPIDs.remove(pid)
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    private func windowFrames(for pid: pid_t) -> [NSRect] {
        let quartzFrames = coreGraphicsWindowFrames(for: pid)
        if !quartzFrames.isEmpty {
            return quartzFrames
        }

        // Accessibility is a fallback for apps whose windows are not listed
        // by Core Graphics. It is intentionally not preferred, because the
        // on-screen Core Graphics list is the safer source across Spaces.
        return accessibilityWindowFrames(for: pid)
    }


    private func coreGraphicsWindowFrames(for pid: pid_t) -> [NSRect] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return windowInfo.compactMap { item -> NSRect? in
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == Int(pid),
                  let layer = item[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width > 80,
                  cgRect.height > 60 else { return nil }
            return nsRect(fromQuartzRect: cgRect)
        }
    }

    private func accessibilityWindowFrames(for pid: pid_t) -> [NSRect] {
        guard AXIsProcessTrusted() else { return [] }

        let appElement = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            guard let positionRef = copyAttribute(window, kAXPositionAttribute as CFString),
                  let sizeRef = copyAttribute(window, kAXSizeAttribute as CFString) else { return nil }

            let positionValue = unsafeBitCast(positionRef, to: AXValue.self)
            let sizeValue = unsafeBitCast(sizeRef, to: AXValue.self)

            var point = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue, .cgPoint, &point),
                  AXValueGetValue(sizeValue, .cgSize, &size),
                  size.width > 80,
                  size.height > 60 else { return nil }

            return nsRect(fromQuartzRect: CGRect(origin: point, size: size))
        }
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func nsRect(fromQuartzRect rect: CGRect) -> NSRect {
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

}

private final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The shield is intentionally opaque. A separate macOS window cannot
        // reliably blur pixels belonging to another application, and a
        // translucent panel would leak protected content underneath it.
        isOpaque = true
        backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1.0)
        hasShadow = false
        // Keep the privacy shield above ordinary application windows while
        // leaving Apple's secure authentication UI free to appear above it.
        level = .statusBar
        becomesKeyOnlyIfNeeded = true
        // Keep the shield in the Space where it was created. The protected
        // process is concealed while locked, so the shield can participate as
        // a normal window in that Space instead of chasing another process's
        // animated coordinates during an interactive trackpad Space gesture.
        // Do NOT use .canJoinAllSpaces or .moveToActiveSpace: either can put an
        // app-scoped privacy panel onto an unrelated Space.
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    func updateContent(appName: String, onUnlock: @escaping () -> Void) {
        let hostingView = NSHostingView(
            rootView: LockShieldView(appName: appName, onUnlock: onUnlock)
        )
        hostingView.frame = contentRect(forFrameRect: frame)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }
}

private struct LockShieldView: View {
    let appName: String
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            // Frosted-lock appearance. The privacy layer stays opaque so
            // protected app pixels cannot leak through, while the material and
            // highlights restore the blurred/glass WeLock look.
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color(nsColor: NSColor(calibratedWhite: 0.035, alpha: 0.96)),
                    Color(nsColor: NSColor(calibratedRed: 0.02, green: 0.09, blue: 0.13, alpha: 0.94)),
                    Color(nsColor: NSColor(calibratedWhite: 0.025, alpha: 0.97))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -170, y: -130)

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 190, y: 150)

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 82, height: 82)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.cyan.opacity(0.32), lineWidth: 1)
                        }

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.cyan)
                }

                Text("\(appName) is locked")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Protected by WeLock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                Button("Unlock", action: onUnlock)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Unlock \(appName) with Touch ID or Mac password")
                    .padding(.top, 4)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
