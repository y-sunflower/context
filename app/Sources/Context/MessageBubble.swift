import AppKit
import MarkdownUI
import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String

    @State private var hovering = false
    @State private var copied = false

    private var isUser: Bool { role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            HStack(alignment: .bottom) {
                if isUser { Spacer(minLength: 70) }
                messageContent
                    .font(.system(size: 18))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(
                        isUser ? .regular.tint(.accentColor.opacity(0.5)) : .regular,
                        in: .rect(cornerRadius: 20, style: .continuous))
                if !isUser { Spacer(minLength: 70) }
            }
            copyButton
                .opacity(hovering || copied ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: copied)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help("Copy message")
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(content)
                .textSelection(.enabled)
        } else {
            Markdown(content)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

}
