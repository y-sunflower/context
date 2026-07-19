import SwiftUI

struct ChatTabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(state.tabs) { tab in
                    ChatTabButton(
                        title: state.tabTitle(tab),
                        isSelected: tab.id == state.selectedTabID,
                        isStreaming: tab.isStreaming,
                        select: { state.selectTab(tab.id) },
                        close: { state.closeTab(tab.id) }
                    )
                }

                Button {
                    state.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .disabled(!state.canStartChat)
                .help("New Tab (⌘T)")
                .padding(.leading, 2)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
        }
        .scrollIndicators(.hidden)
        .frame(height: 43)
        .background(.bar)
    }
}

private struct ChatTabButton: View {
    let title: String
    let isSelected: Bool
    let isStreaming: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            }

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(width: 190, height: 34)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.separator.opacity(0.7), lineWidth: 0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
