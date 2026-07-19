import Foundation
import Testing

@testable import Context

@Suite("Chat tabs")
struct ChatTabTests {
    @Test @MainActor
    func createsNavigatesClosesAndReopensTabs() {
        let state = makeState()
        state.ollamaStatus = .ready

        state.newTab()
        let first = state.activeTab
        state.newTab()
        let second = state.activeTab
        second?.composerDraft = "keep this draft"

        #expect(state.tabs.count == 2)
        #expect(state.activeTab?.id == second?.id)

        state.selectAdjacentTab(offset: -1)
        #expect(state.activeTab?.id == first?.id)
        state.selectAdjacentTab(offset: -1)
        #expect(state.activeTab?.id == second?.id)

        state.closeCurrentTab()
        #expect(state.tabs.count == 1)
        #expect(state.activeTab?.id == first?.id)

        state.reopenClosedTab()
        #expect(state.tabs.count == 2)
        #expect(state.activeTab?.id == second?.id)
        #expect(state.activeTab?.composerDraft == "keep this draft")
    }

    @Test @MainActor
    func openingAnOpenConversationSelectsItsExistingTab() {
        let state = makeState()
        state.conversations = [
            Conversation(id: 1, title: "One", model: "model", createdAt: 1, updatedAt: 1),
            Conversation(id: 2, title: "Two", model: "model", createdAt: 2, updatedAt: 2),
        ]

        state.openConversation(1)
        let firstTabID = state.activeTab?.id
        state.openConversation(2)
        state.openConversation(1)

        #expect(state.tabs.count == 2)
        #expect(state.activeTab?.id == firstTabID)
        #expect(state.selectedConversationID == 1)
    }

    @Test @MainActor
    func streamsInTwoTabsAtTheSameTime() async throws {
        let state = makeState()
        state.ollamaStatus = .ready

        state.newTab()
        let first = try #require(state.activeTab)
        state.send("first question")

        state.newTab()
        let second = try #require(state.activeTab)
        state.send("second question")

        #expect(first.isStreaming)
        #expect(second.isStreaming)

        try await Task.sleep(for: .milliseconds(150))

        #expect(!first.isStreaming)
        #expect(!second.isStreaming)
        #expect(first.messages.map(\.content) == ["first question", "answer"])
        #expect(second.messages.map(\.content) == ["second question", "answer"])
    }

    @MainActor
    private func makeState() -> AppState {
        let suiteName = "ChatTabTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppState(
            defaults: defaults,
            database: TabTestDatabase(),
            ollama: TabTestOllama())
    }
}

private actor TabTestDatabase: ChatDatabase {
    private var conversations: [Conversation] = []
    private var messages: [Int64: [Message]] = [:]
    private var nextConversationID: Int64 = 1
    private var nextMessageID: Int64 = 1

    func listConversations() -> [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createConversationWithMessage(model: String, content: String) -> Conversation {
        let id = nextConversationID
        nextConversationID += 1
        let conversation = Conversation(
            id: id,
            title: content,
            model: model,
            createdAt: id,
            updatedAt: id)
        conversations.append(conversation)
        messages[id] = [makeMessage(conversationID: id, role: "user", content: content)]
        return conversation
    }

    func deleteConversation(id: Int64) {
        conversations.removeAll { $0.id == id }
        messages[id] = nil
    }

    func renameConversation(id: Int64, title: String) {}

    func setConversationModel(id: Int64, model: String) {}

    func getMessages(conversationId: Int64) -> [Message] {
        messages[conversationId] ?? []
    }

    func listSearchableMessages() -> [SearchableMessage] { [] }

    func insertMessage(
        conversationId: Int64,
        role: String,
        content: String,
        thinking: String?
    ) -> Message {
        let message = makeMessage(
            conversationID: conversationId,
            role: role,
            content: content,
            thinking: thinking)
        messages[conversationId, default: []].append(message)
        return message
    }

    func replaceMessageAndTruncate(
        conversationId: Int64,
        messageId: Int64,
        content: String
    ) {}

    func maybeAutotitle(conversationId: Int64, content: String) {}

    private func makeMessage(
        conversationID: Int64,
        role: String,
        content: String,
        thinking: String? = nil
    ) -> Message {
        defer { nextMessageID += 1 }
        return Message(
            id: nextMessageID,
            conversationId: conversationID,
            role: role,
            content: content,
            thinking: thinking,
            createdAt: nextMessageID)
    }
}

private struct TabTestOllama: OllamaServing {
    func listModels() async throws -> [ModelInfo] {
        [ModelInfo(name: "model", sizeBytes: 1)]
    }

    func streamChat(
        model: String,
        history: [Message],
        options: GenerationOptions
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try await Task.sleep(for: .milliseconds(50))
                continuation.yield(.content("answer"))
                continuation.finish()
            }
        }
    }
}
