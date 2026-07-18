import ContextCore
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state

    private let bottomAnchor = "bottom"

    var body: some View {
        @Bindable var state = state
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(state.messages) { message in
                        MessageBubble(role: message.role, content: message.content)
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
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.accentColor.opacity(0.02),
                    Color.clear,
                ],
                startPoint: .top, endPoint: .bottom)
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
