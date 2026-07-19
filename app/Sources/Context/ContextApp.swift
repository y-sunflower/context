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
                Button("New Tab") { state.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(!state.canStartChat)
            }
            CommandGroup(after: .newItem) {
                Button("Close Tab") { state.closeCurrentTab() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(state.activeTab == nil)
                Button("Reopen Closed Tab") { state.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(state.closedTabs.isEmpty)
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

                Divider()

                Button("Previous Tab") { state.selectAdjacentTab(offset: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(state.tabs.count < 2)
                Button("Next Tab") { state.selectAdjacentTab(offset: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(state.tabs.count < 2)
            }
        }

        Settings {
            SettingsView()
                .environment(state)
                .preferredColorScheme(state.appearance.colorScheme)
        }
    }
}
