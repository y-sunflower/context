import AppKit
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
            CommandGroup(after: .textEditing) {
                Button("Search Messages") { state.presentMessageSearch() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}
