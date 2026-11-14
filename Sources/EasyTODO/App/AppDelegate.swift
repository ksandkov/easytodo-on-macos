import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EasyTODOSettings.registerDefaults()
        MenuBarManager.shared.applicationDidFinishLaunching()
        AppLogo.applyApplicationIcon()
        GlobalShortcutManager.shared.registerQuickAddShortcut()
        WindowManager.shared.applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcutManager.shared.unregisterQuickAddShortcut()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
