import SwiftUI

struct SettingsView: View {
    @AppStorage(EasyTODOSettings.launchAtLogin) private var launchAtLogin = false
    @AppStorage(EasyTODOSettings.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(EasyTODOSettings.showMenuBar) private var showMenuBar = true
    @AppStorage(EasyTODOSettings.hiddenDockIcon) private var hiddenDockIcon = false
    @AppStorage(EasyTODOSettings.transparency) private var transparency = 0.80
    @AppStorage(EasyTODOSettings.theme) private var theme = ThemeOption.light.rawValue

    @State private var loginItemMessage: String?
    @State private var selectedPane = 0

    static func hideMenuBarBinding(for visibility: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { !visibility.wrappedValue },
            set: { visibility.wrappedValue = !$0 }
        )
    }

    private var generalSettings: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Always on Top", isOn: $alwaysOnTop)
                Toggle("Hide Menu Bar Icon", isOn: Self.hideMenuBarBinding(for: $showMenuBar))
                Toggle("Hide Dock Icon", isOn: $hiddenDockIcon)

                if hiddenDockIcon && !showMenuBar {
                    Text("Both icons are hidden. Use the window gear for settings, or reopen this app to restore a hidden window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Quick Add: \(GlobalShortcutManager.quickAddShortcutDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transparency") {
                Picker("Window", selection: $transparency) {
                    Text("100%").tag(1.0)
                    Text("80%").tag(0.80)
                    Text("50%").tag(0.50)
                }
                .pickerStyle(.segmented)
            }

            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedPane) {
                Text("General").tag(0)
                Text("Categories").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if selectedPane == 0 {
                generalSettings
            } else {
                Form {
                    Section("Categories") { CategorySettingsView() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: launchAtLogin) { _, newValue in
            loginItemMessage = LoginItemManager.setEnabled(newValue)
        }
        .onChange(of: alwaysOnTop) { _, _ in
            WindowManager.shared.applyWindowSettings()
        }
        .onChange(of: transparency) { _, _ in
            WindowManager.shared.applyWindowSettings()
        }
        .onChange(of: showMenuBar) { _, _ in
            WindowManager.shared.applyActivationPolicy()
        }
        .onChange(of: hiddenDockIcon) { _, _ in
            WindowManager.shared.applyActivationPolicy()
        }
    }
}
