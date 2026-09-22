import XCTest
@testable import WeLock

final class WeLockTests: XCTestCase {
    func testDelayLabelsAndRawValues() {
        XCTAssertEqual(DelayOption.immediately.rawValue, 0)
        XCTAssertEqual(DelayOption.fifteenSeconds.title, "15 seconds")
        XCTAssertEqual(DelayOption.fiveMinutes.shortTitle, "5m")
        XCTAssertEqual(DelayOption.off.title, "Never")
    }

    func testProtectedAppRoundTrip() throws {
        let app = ProtectedApp(
            bundleIdentifier: "com.example.WhatsApp",
            displayName: "WhatsApp",
            path: "/Applications/WhatsApp.app",
            isProtected: true,
            autoClose: false,
            relockDelayOverride: .thirtySeconds
        )

        let data = try JSONEncoder().encode(app)
        let decoded = try JSONDecoder().decode(ProtectedApp.self, from: data)
        XCTAssertEqual(decoded, app)
    }

    func testNewSettingsAreSafeByDefault() {
        let settings = WeLockSettings()
        XCTAssertTrue(settings.lockOnSleep)
        XCTAssertTrue(settings.lockOnAppSwitch)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.protectedApps.isEmpty)
    }

    func testProtectionIsSeparateFromAutoClose() {
        let app = ProtectedApp(
            bundleIdentifier: "com.example.Test",
            displayName: "Test",
            path: "/Applications/Test.app",
            isProtected: true,
            autoClose: false
        )
        XCTAssertTrue(app.isProtected)
        XCTAssertFalse(app.autoClose)
    }
}

