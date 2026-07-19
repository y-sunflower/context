import ContextCore
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state
    @State private var highlightedMessageID: Int64?
    @State private var highlightTask: Task<Void, Never>?

    private let bottomAnchor = "bottom"

    var body: some View {
        @Bindable var state = state
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(state.messages) { message in
                        MessageBubble(
                            role: message.role,
                            content: message.content,
                            isSearchTarget: highlightedMessageID == message.id,
                            onEdit: message.role == "user" && !state.isStreaming
                                ? { state.edit(message) }
                                : nil
                        )
                        .id(message.id)
                    }
                    if state.isStreaming {
                        if let text = state.streamingText, !text.isEmpty {
                            MessageBubble(role: "assistant", content: text)
                        } else {
                            ThinkingIndicator()
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .onChange(of: state.streamingText) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onChange(of: state.messages.count) {
                if state.pendingMessageJumpID == nil {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                } else {
                    performPendingJump(using: proxy)
                }
            }
            .onChange(of: state.pendingMessageJumpID) {
                performPendingJump(using: proxy)
            }
            .onAppear {
                if state.pendingMessageJumpID == nil {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                } else {
                    performPendingJump(using: proxy)
                }
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.accentColor.opacity(0.02),
                    Color.clear,
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            ComposerView()
        }
        .navigationTitle(state.selectedConversation?.title ?? "Context")
        .navigationSubtitle(state.selectedModel)
        .toolbar {
            ToolbarItem {
                Picker("Model", selection: $state.selectedModel) {
                    ForEach(state.models, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .help("Model used for the next message")
            }
        }
    }

    private func performPendingJump(using proxy: ScrollViewProxy) {
        guard let messageID = state.pendingMessageJumpID,
            state.messages.contains(where: { $0.id == messageID })
        else { return }

        highlightTask?.cancel()
        highlightTask = Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(messageID, anchor: .center)
            }
            highlightedMessageID = messageID
            state.completeMessageJump(messageID)
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                highlightedMessageID = nil
            }
        }
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking…")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            Spacer()
        }
    }
}
