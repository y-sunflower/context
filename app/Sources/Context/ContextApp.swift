import SwiftUI

@main
struct ContextApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { state.newChat() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!state.canStartChat)
            }
        }
    }
}
