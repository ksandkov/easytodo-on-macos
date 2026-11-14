import SwiftData
import SwiftUI

@main
@MainActor
struct EasyTODOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        EasyTODOSettings.registerDefaults()
        do {
            let modelContainer = try PersistenceController.modelContainer()
            MenuBarManager.shared.configure(modelContainer: modelContainer)
            QuickAddPanelManager.shared.configure(modelContainer: modelContainer)
            WindowManager.shared.configure(modelContainer: modelContainer)
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        // AppKit owns both windows; the scene supplies the standard application menus.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        SettingsWindowManager.shared.showSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }

                CommandGroup(after: .undoRedo) {
                    Button("Undo Delete") {
                        NotificationCenter.default.post(name: .easyTODOUndoDeleteTask, object: nil)
                    }
                    .keyboardShortcut("z", modifiers: [.control])
                }

                CommandGroup(replacing: .newItem) {
                    Button("New Task") {
                        NotificationCenter.default.post(name: .easyTODOFocusNewTask, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
    }
}

struct ThemedContent<Content: View>: View {
    var content: Content
    @AppStorage(EasyTODOSettings.theme) private var theme = ThemeOption.light.rawValue

    var body: some View {
        content.preferredColorScheme(
            ThemeOption(rawValue: theme) == .dark ? .dark : .light
        )
    }
}
