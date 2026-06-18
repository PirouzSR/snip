import SwiftUI

@main
struct SnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The Settings scene satisfies the App scene requirement and provides the standard
        // ⌘, menu item; we replace its action so every entry point (menu item, toolbar
        // overflow, menu-bar popover) opens the same AppDelegate-owned settings window.
        Settings {
            SettingsView()
                .environment(delegate.appState)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppDelegate.shared?.openSettingsWindow() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
