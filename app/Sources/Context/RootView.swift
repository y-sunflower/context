import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            switch state.ollamaStatus {
            case .checking:
                OllamaSetupView(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    title: "Checking Ollama…",
                    message: "Looking for Ollama and your local models."
                ) {
                    ProgressView()
                        .controlSize(.small)
                }
            case .unavailable:
                OllamaSetupView(
                    icon: "externaldrive.badge.exclamationmark",
                    title: "Ollama isn’t available",
                    message:
                        "Context couldn’t connect to Ollama on this Mac. Install Ollama if you don’t have it, or open Ollama if it is already installed. Then check again."
                ) {
                    Link(
                        "Download Ollama", destination: URL(string: "https://ollama.com/download")!
                    )
                    .buttonStyle(.glassProminent)
                    retryButton
                }
            case .noModels:
                OllamaSetupView(
                    icon: "shippingbox",
                    title: "No local models found",
                    message:
                        "Ollama is running, but it doesn’t have a model yet. Choose a model from the Ollama library, run its pull command in Terminal, then check again."
                ) {
                    VStack(spacing: 6) {
                        Text("ollama pull <model-name>")
                            .font(.system(size: 15, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Example: ollama pull gemma4:26b")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Link("Browse Models", destination: URL(string: "https://ollama.com/search")!)
                        .buttonStyle(.glassProminent)
                    retryButton
                }
            case .ready:
                if state.selectedConversationID != nil {
                    ChatView()
                } else {
                    EmptyStateView()
                }
            }
        }
        .font(.system(size: 15))
        .overlay {
            if state.isMessageSearchPresented {
                MessageSearchView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: state.isMessageSearchPresented)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var retryButton: some View {
        Button("Check Again") {
            Task { await state.refreshModels() }
        }
        .buttonStyle(.glass)
    }
}

private struct OllamaSetupView<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    let actions: Actions

    init(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            actions
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("CONTEXT")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(10)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 24)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))

            Text("Local chats with your Ollama models.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)

            Button("New Chat") { state.newChat() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
