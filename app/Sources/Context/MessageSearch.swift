import ContextCore
import Foundation
import SwiftUI

struct MessageSearchMatch: Identifiable {
    let message: SearchableMessage
    let score: Int

    var id: Int64 { message.id }

    var snippet: String {
        let collapsed = message.content
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard collapsed.count > 180 else { return collapsed }
        return String(collapsed.prefix(177)) + "…"
    }
}

struct MessageSearchGroup: Identifiable {
    let conversationID: Int64
    let title: String
    let updatedAt: Int64
    let matches: [MessageSearchMatch]

    var id: Int64 { conversationID }
}

enum MessageSearch {
    static func matches(
        query: String,
        in corpus: [SearchableMessage],
        limit: Int = 10
    ) -> [MessageSearchMatch] {
        guard limit > 0 else { return [] }
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return corpus.compactMap { message -> MessageSearchMatch? in
            guard
                let score = fuzzyScore(
                    query: normalizedQuery, candidate: normalize(message.content))
            else { return nil }
            return MessageSearchMatch(message: message, score: score)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.message.createdAt != $1.message.createdAt {
                return $0.message.createdAt > $1.message.createdAt
            }
            return $0.message.id > $1.message.id
        }
        .prefix(limit)
        .map { $0 }
    }

    static func groups(for matches: [MessageSearchMatch]) -> [MessageSearchGroup] {
        let byConversation = Dictionary(grouping: matches, by: { $0.message.conversationId })
        return byConversation.compactMap { conversationID, matches in
            guard let first = matches.first else { return nil }
            return MessageSearchGroup(
                conversationID: conversationID,
                title: first.message.conversationTitle,
                updatedAt: first.message.conversationUpdatedAt,
                matches: matches.sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    if $0.message.createdAt != $1.message.createdAt {
                        return $0.message.createdAt > $1.message.createdAt
                    }
                    return $0.message.id > $1.message.id
                })
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.conversationID > $1.conversationID
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func fuzzyScore(query: String, candidate: String) -> Int? {
        guard !query.isEmpty, !candidate.isEmpty else { return nil }

        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            return 100_000 + query.count * 100 - min(offset, 5_000)
        }

        let queryCharacters = Array(query)
        let candidateCharacters = Array(candidate)
        var positions: [Int] = []
        var searchStart = 0

        for character in queryCharacters {
            guard searchStart < candidateCharacters.count,
                let position = candidateCharacters[searchStart...].firstIndex(of: character)
            else { return nil }
            positions.append(position)
            searchStart = position + 1
        }

        var score = queryCharacters.count * 20
        for index in positions.indices {
            let position = positions[index]
            if position == 0 || candidateCharacters[position - 1].isWhitespace {
                score += 14
            }
            if index > 0 {
                let gap = position - positions[index - 1] - 1
                score += gap == 0 ? 18 : -min(gap, 24)
            }
        }

        let span = positions.last! - positions.first! + 1
        score += queryCharacters.count * 100 / max(span, 1)
        score -= min(candidateCharacters.count / 40, 80)
        return score
    }
}

struct MessageSearchView: View {
    @Environment(AppState.self) private var state
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selectedMessageID: Int64?

    private var matches: [MessageSearchMatch] {
        MessageSearch.matches(query: query, in: state.searchableMessages)
    }

    private var groups: [MessageSearchGroup] {
        MessageSearch.groups(for: matches)
    }

    private var displayedMatches: [MessageSearchMatch] {
        groups.flatMap(\.matches)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { state.dismissMessageSearch() }

            VStack(spacing: 0) {
                searchField
                Divider()
                results
            }
            .frame(width: 640)
            .frame(maxHeight: 520)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
            .padding(.top, 54)
            .padding(.horizontal, 24)
        }
        .onExitCommand { state.dismissMessageSearch() }
        .task { searchFocused = true }
        .onChange(of: matches.map(\.id)) {
            if !displayedMatches.contains(where: { $0.id == selectedMessageID }) {
                selectedMessageID = displayedMatches.first?.id
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search all messages", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 21))
                .focused($searchFocused)
                .onSubmit { openSelection() }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            Text("esc")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    @ViewBuilder
    private var results: some View {
        if let error = state.messageSearchError {
            searchStatus(icon: "exclamationmark.triangle", text: error)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchStatus(icon: "text.magnifyingglass", text: "Type to search your chat history")
        } else if matches.isEmpty {
            searchStatus(icon: "magnifyingglass", text: "No matching messages")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)

                            ForEach(group.matches) { match in
                                resultButton(match)
                                    .id(match.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedMessageID) {
                    if let selectedMessageID {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedMessageID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func resultButton(_ match: MessageSearchMatch) -> some View {
        Button {
            state.jump(to: match.message)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: match.message.role == "user" ? "person.fill" : "sparkles")
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.message.role == "user" ? "You" : "Assistant")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(match.snippet)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                selectedMessageID == match.id ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedMessageID = match.id }
        }
    }

    private func searchStatus(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 25))
            Text(text)
                .font(.system(size: 15))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func moveSelection(by offset: Int) {
        let orderedMatches = displayedMatches
        guard !orderedMatches.isEmpty else { return }
        guard let selectedMessageID,
            let index = orderedMatches.firstIndex(where: { $0.id == selectedMessageID })
        else {
            self.selectedMessageID = orderedMatches.first?.id
            return
        }
        let next = (index + offset + orderedMatches.count) % orderedMatches.count
        self.selectedMessageID = orderedMatches[next].id
    }

    private func openSelection() {
        guard let selectedMessageID,
            let match = matches.first(where: { $0.id == selectedMessageID })
        else { return }
        state.jump(to: match.message)
    }
}
