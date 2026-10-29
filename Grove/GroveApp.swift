import SwiftUI

@main
struct GroveApp: App {
    @State private var model = AppModel()

    init() {
        // The main window is suppressed at launch, so its onAppear never sets the policy.
        if AppSettings().startInMenuBar { NSApplication.shared.setActivationPolicy(.accessory) }
    }

    var body: some Scene {
        Window("Grove", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                // Menu-bar-only while the main window is closed.
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 980, height: 620)
        .defaultLaunchBehavior(model.settings.startInMenuBar ? .suppressed : .automatic)

        MenuBarExtra("Grove", image: "MenuBarIcon") {
            MenuBarView().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}
