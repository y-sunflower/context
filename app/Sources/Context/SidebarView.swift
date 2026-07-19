import ContextCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selectedConversationID) {
            ForEach(state.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Rename…") {
                            renameText = conversation.title
                            renameTarget = conversation
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            state.deleteConversation(conversation)
                        }
                    }
            }
        }
        .focused($listFocused)
        .onChange(of: state.sidebarFocusRequest) {
            Task { @MainActor in
                await Task.yield()
                listFocused = true
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem {
                Button("New Chat", systemImage: "square.and.pencil") {
                    state.newChat()
                }
                .buttonStyle(.glass)
                .disabled(!state.canStartChat)
                .help("New Chat (⌘O)")
            }
        }
        .overlay {
            if state.conversations.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        }
        .alert(
            "Rename Chat",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    state.renameConversation(target, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
            Text(conversation.model)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
