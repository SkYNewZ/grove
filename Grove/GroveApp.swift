import SwiftUI

@main
struct GroveApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Grove", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 980, height: 620)

        MenuBarExtra("Grove", image: "MenuBarIcon") {
            MenuBarView().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}
