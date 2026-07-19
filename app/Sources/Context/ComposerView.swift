import SwiftUI

struct ComposerView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !state.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var state = state
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Message \(state.selectedModel)…", text: $state.composerDraft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(send)
                .padding(.leading, 16)
                .padding(.vertical, 11)

                Button(action: primaryAction) {
                    Image(systemName: state.isStreaming ? "stop.fill" : "arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!state.isStreaming && !canSend)
                .padding(6)
                .help(state.isStreaming ? "Stop generating" : "Send")
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear { focused = true }
        .onChange(of: state.composerFocusRequest) { focused = true }
    }

    private func primaryAction() {
        if state.isStreaming {
            state.cancelStreaming()
        } else {
            send()
        }
    }

    private func send() {
        guard canSend, !state.isStreaming else { return }
        let text = state.composerDraft
        state.composerDraft = ""
        state.send(text)
    }
}
