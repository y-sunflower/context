import AppKit
import MarkdownUI
import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String
    var isSearchTarget = false
    var onEdit: (() -> Void)?

    @State private var hovering = false
    @State private var hoveringActions = false
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
                        in: .rect(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: isSearchTarget ? 3 : 0)
                            .shadow(
                                color: Color.accentColor.opacity(isSearchTarget ? 0.45 : 0),
                                radius: 8)
                    }
                if !isUser { Spacer(minLength: 70) }
            }
            actionButtons
                .opacity(hovering || hoveringActions || copied ? 1 : 0.45)
                .onHover { hoveringActions = $0 }
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: copied)
        .animation(.easeInOut(duration: 0.2), value: isSearchTarget)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if let onEdit {
                actionButton(
                    systemImage: "pencil",
                    help: "Edit message",
                    action: onEdit)
            }
            actionButton(
                systemImage: copied ? "checkmark" : "doc.on.doc",
                help: copied ? "Copied" : "Copy message",
                action: copy)
        }
    }

    private func actionButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: Circle())
        .help(help)
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
