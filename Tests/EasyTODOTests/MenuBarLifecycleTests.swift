import XCTest
@testable import EasyTODO

final class MenuBarLifecycleTests: XCTestCase {
    @MainActor
    func testEnabledStatusItemWaitsForApplicationLaunch() {
        var installations = 0
        let lifecycle = MenuBarLifecycle(
            onInstall: { installations += 1 },
            onRemove: {}
        )

        lifecycle.setEnabled(true)

        XCTAssertEqual(installations, 0, "Enabling the menu bar before launch must not access AppKit status items.")

        lifecycle.applicationDidFinishLaunching()

        XCTAssertEqual(installations, 1)
    }

    @MainActor
    func testRepeatedConfigurationAndLaunchDoNotInstallDuplicates() {
        var installations = 0
        let lifecycle = MenuBarLifecycle(
            onInstall: { installations += 1 },
            onRemove: {}
        )

        lifecycle.setEnabled(true)
        lifecycle.applicationDidFinishLaunching()
        lifecycle.setEnabled(true)
        lifecycle.applicationDidFinishLaunching()

        XCTAssertEqual(installations, 1)
    }

    @MainActor
    func testDisabledMenuBarDoesNotInstallAfterLaunch() {
        var installations = 0
        let lifecycle = MenuBarLifecycle(
            onInstall: { installations += 1 },
            onRemove: {}
        )

        lifecycle.setEnabled(false)
        lifecycle.applicationDidFinishLaunching()

        XCTAssertEqual(installations, 0)
    }

    @MainActor
    func testPreferenceCanBeDisabledAgainBeforeLaunch() {
        var installations = 0
        var removals = 0
        let lifecycle = MenuBarLifecycle(
            onInstall: { installations += 1 },
            onRemove: { removals += 1 }
        )

        lifecycle.setEnabled(true)
        lifecycle.setEnabled(false)
        lifecycle.applicationDidFinishLaunching()

        XCTAssertEqual(installations, 0)
        XCTAssertEqual(removals, 0)
    }

    @MainActor
    func testDisablingAndReenablingAfterLaunchUpdatesTheStatusItemOnce() {
        var installations = 0
        var removals = 0
        let lifecycle = MenuBarLifecycle(
            onInstall: { installations += 1 },
            onRemove: { removals += 1 }
        )

        lifecycle.applicationDidFinishLaunching()
        lifecycle.setEnabled(true)
        lifecycle.setEnabled(false)
        lifecycle.setEnabled(false)
        lifecycle.setEnabled(true)
        lifecycle.setEnabled(true)

        XCTAssertEqual(installations, 2)
        XCTAssertEqual(removals, 1)
    }
}
