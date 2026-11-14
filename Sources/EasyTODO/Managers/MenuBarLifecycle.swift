/// Keeps status-item operations behind AppKit's launch boundary.
@MainActor
final class MenuBarLifecycle {
    private var hasFinishedLaunching = false
    private var isEnabled = false
    private var isInstalled = false
    private let onInstall: () -> Void
    private let onRemove: () -> Void

    init(onInstall: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.onInstall = onInstall
        self.onRemove = onRemove
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        updateInstallation()
    }

    func applicationDidFinishLaunching() {
        hasFinishedLaunching = true
        updateInstallation()
    }

    private func updateInstallation() {
        let shouldInstall = hasFinishedLaunching && isEnabled
        guard shouldInstall != isInstalled else { return }

        isInstalled = shouldInstall
        if shouldInstall {
            onInstall()
        } else {
            onRemove()
        }
    }
}
