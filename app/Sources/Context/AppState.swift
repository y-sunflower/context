import Foundation
import Observation

@Observable @MainActor
final class AppState {
    static let defaultModel = "gemma4:26b"
    private static let appearanceKey = "appearance"
    private static let defaultModelKey = "defaultModel"
    private static let generationOptionsKey = "generationOptions"

    enum OllamaStatus: Equatable {
        case checking
        case unavailable
        case noModels
        case ready
    }

    @ObservationIgnored private var database: (any ChatDatabase)?
    @ObservationIgnored private let ollama: any OllamaServing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var selectionTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generationTasks: [UUID: Task<Void, Never>] = [:]

    var conversations: [Conversation] = []
    var tabs: [ChatTab] = []
    var selectedTabID: UUID?
    private(set) var closedTabs: [ChatTab] = []
    var models: [ModelInfo] = []
    var generationOptions = GenerationOptions.modelDefaults {
        didSet { persistGenerationOptions() }
    }
    var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: AppState.defaultModelKey) }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: AppState.appearanceKey) }
    }
    var ollamaStatus = OllamaStatus.checking
    var errorMessage: String?
    var sidebarFocusRequest = 0
    var isMessageSearchPresented = false
    var searchableMessages: [SearchableMessage] = []
    var messageSearchError: String?

    var canStartChat: Bool { ollamaStatus == .ready }

    var activeTab: ChatTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var selectedConversationID: Int64? {
        get { activeTab?.conversationID }
        set {
            guard let newValue else { return }
            openConversation(newValue)
        }
    }

    var selectedConversation: Conversation? {
        guard let id = activeTab?.conversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    var messages: [Message] { activeTab?.messages ?? [] }
    var isDraftChat: Bool { activeTab != nil && activeTab?.conversationID == nil }
    var isStreaming: Bool { activeTab?.isStreaming ?? false }
    var streamingText: String? { activeTab?.streamingText }
    var streamingThinkingText: String? { activeTab?.streamingThinkingText }
    var isStreamingSelectedConversation: Bool { activeTab?.isStreaming ?? false }

    var selectedModel: String {
        get { activeTab?.selectedModel ?? defaultModel }
        set { activeTab?.selectedModel = newValue }
    }

    var composerDraft: String {
        get { activeTab?.composerDraft ?? "" }
        set { activeTab?.composerDraft = newValue }
    }

    var composerFocusRequest: Int { activeTab?.composerFocusRequest ?? 0 }
    var editingMessageID: Int64? { activeTab?.editingMessageID }
    var pendingMessageJumpID: Int64? { activeTab?.pendingMessageJumpID }

    init(
        defaults: UserDefaults = .standard,
        database injectedDatabase: (any ChatDatabase)? = nil,
        ollama: any OllamaServing = OllamaClient()
    ) {
        self.defaults = defaults
        self.ollama = ollama
        if let data = defaults.data(forKey: AppState.generationOptionsKey),
            let options = try? JSONDecoder().decode(GenerationOptions.self, from: data)
        {
            generationOptions = options
        }
        let savedDefaultModel =
            defaults.string(forKey: AppState.defaultModelKey)
            ?? AppState.defaultModel
        defaultModel = savedDefaultModel
        appearance =
            AppAppearance(
                rawValue: defaults.string(forKey: AppState.appearanceKey) ?? "") ?? .system

        if let injectedDatabase {
            database = injectedDatabase
        } else {
            do {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true)
                let directory = support.appendingPathComponent("Context", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                database = try Database(
                    path: directory.appendingPathComponent("context.db").path)
            } catch {
                errorMessage = "Failed to open the local database: \(error.localizedDescription)"
            }
        }

        Task { await bootstrap() }
    }

    // MARK: - Tabs

    func newChat() {
        newTab()
    }

    func newTab() {
        guard canStartChat else { return }
        let tab = ChatTab(selectedModel: defaultModel)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.composerFocusRequest += 1
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func selectAdjacentTab(offset: Int) {
        guard !tabs.isEmpty else { return }
        guard let selectedTabID,
            let index = tabs.firstIndex(where: { $0.id == selectedTabID })
        else {
            self.selectedTabID = tabs.first?.id
            return
        }
        let nextIndex = (index + offset % tabs.count + tabs.count) % tabs.count
        self.selectedTabID = tabs[nextIndex].id
    }

    func closeCurrentTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        selectionTasks.removeValue(forKey: id)?.cancel()
        generationTasks[id]?.cancel()
        closedTabs.append(tab)

        guard selectedTabID == id else { return }
        selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    func reopenClosedTab() {
        guard let tab = closedTabs.popLast() else { return }
        if let conversationID = tab.conversationID,
            let openTab = tabs.first(where: { $0.conversationID == conversationID })
        {
            selectedTabID = openTab.id
            return
        }
        tabs.append(tab)
        selectedTabID = tab.id
        tab.composerFocusRequest += 1
    }

    func tabTitle(_ tab: ChatTab) -> String {
        guard let conversationID = tab.conversationID else { return "New Chat" }
        return conversations.first(where: { $0.id == conversationID })?.title ?? "Chat"
    }

    // MARK: - Conversations

    func openConversation(_ conversationID: Int64) {
        if let tab = tabs.first(where: { $0.conversationID == conversationID }) {
            selectedTabID = tab.id
            return
        }
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return
        }
        let tab = ChatTab(
            conversationID: conversationID,
            selectedModel: conversation.model.isEmpty ? defaultModel : conversation.model)
        tabs.append(tab)
        selectedTabID = tab.id
        loadMessages(for: tab)
    }

    func deleteConversation(_ conversation: Conversation) {
        guard let database else { return }
        Task {
            let matchingTabs = (tabs + closedTabs).filter {
                $0.conversationID == conversation.id
            }
            let matchingTasks = matchingTabs.compactMap { generationTasks[$0.id] }
            for tab in matchingTabs {
                generationTasks[tab.id]?.cancel()
            }
            for task in matchingTasks {
                await task.value
            }
            do {
                try await database.deleteConversation(id: conversation.id)
                conversations = try await database.listConversations()
                removeTabs(for: conversation.id)
            } catch {
                report(error)
            }
        }
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        guard let database else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await database.renameConversation(id: conversation.id, title: trimmed)
                conversations = try await database.listConversations()
            } catch {
                report(error)
            }
        }
    }

    private func bootstrap() async {
        if let database {
            do {
                conversations = try await database.listConversations()
            } catch {
                report(error)
            }
        }
        await refreshModels()
    }

    private func loadMessages(for tab: ChatTab) {
        guard let database, let conversationID = tab.conversationID else { return }
        selectionTasks[tab.id]?.cancel()
        selectionTasks[tab.id] = Task {
            do {
                let loaded = try await database.getMessages(conversationId: conversationID)
                try Task.checkCancellation()
                guard tabs.contains(where: { $0.id == tab.id }) else { return }
                tab.messages = loaded
                selectionTasks[tab.id] = nil
            } catch is CancellationError {
                return
            } catch {
                selectionTasks[tab.id] = nil
                report(error)
            }
        }
    }

    private func removeTabs(for conversationID: Int64) {
        let matchingIDs = Set(
            tabs.filter { $0.conversationID == conversationID }.map(\.id))
        tabs.removeAll { matchingIDs.contains($0.id) }
        closedTabs.removeAll { $0.conversationID == conversationID }
        for id in matchingIDs {
            selectionTasks.removeValue(forKey: id)?.cancel()
            generationTasks.removeValue(forKey: id)?.cancel()
        }
        if let selectedTabID, matchingIDs.contains(selectedTabID) {
            self.selectedTabID = tabs.first?.id
        }
    }

    // MARK: - Message search

    func presentMessageSearch() {
        isMessageSearchPresented = true
        messageSearchError = nil
        guard let database else {
            searchableMessages = []
            messageSearchError = "Chat history is unavailable."
            return
        }
        Task {
            do {
                searchableMessages = try await database.listSearchableMessages()
            } catch {
                searchableMessages = []
                messageSearchError = "Couldn’t load chat history."
            }
        }
    }

    func dismissMessageSearch() {
        isMessageSearchPresented = false
        messageSearchError = nil
    }

    func jump(to result: SearchableMessage) {
        isMessageSearchPresented = false
        messageSearchError = nil
        openConversation(result.conversationId)
        activeTab?.pendingMessageJumpID = result.id
    }

    func completeMessageJump(_ messageID: Int64) {
        guard activeTab?.pendingMessageJumpID == messageID else { return }
        activeTab?.pendingMessageJumpID = nil
    }

    // MARK: - Chat

    func edit(_ message: Message) {
        guard let tab = activeTab, !tab.isStreaming, message.role == "user" else { return }
        guard message.conversationId == tab.conversationID else { return }
        tab.editingMessageID = message.id
        tab.composerDraft = message.content
        tab.composerFocusRequest += 1
    }

    func send(_ text: String) {
        guard let database, let tab = activeTab, !tab.isStreaming else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        selectionTasks.removeValue(forKey: tab.id)?.cancel()

        let originalConversationID = tab.conversationID
        let editingID = tab.editingMessageID
        let model = tab.selectedModel
        let options = generationOptions
        tab.isStreaming = true
        tab.streamingText = ""
        tab.streamingThinkingText = ""

        generationTasks[tab.id] = Task {
            var conversationID = originalConversationID
            var answer = ""
            var thinking = ""
            do {
                if conversationID == nil {
                    let conversation = try await database.createConversationWithMessage(
                        model: model, content: content)
                    conversationID = conversation.id
                    tab.conversationID = conversation.id
                    conversations = try await database.listConversations()
                } else if let conversationID, let editingID {
                    try await database.setConversationModel(id: conversationID, model: model)
                    try await database.replaceMessageAndTruncate(
                        conversationId: conversationID,
                        messageId: editingID,
                        content: content)
                    tab.editingMessageID = nil
                } else if let conversationID {
                    try await database.setConversationModel(id: conversationID, model: model)
                    _ = try await database.insertMessage(
                        conversationId: conversationID,
                        role: "user",
                        content: content,
                        thinking: nil)
                    try await database.maybeAutotitle(
                        conversationId: conversationID, content: content)
                }

                guard let conversationID else { return }
                let history = try await database.getMessages(conversationId: conversationID)
                tab.messages = history
                conversations = try await database.listConversations()

                for try await event in ollama.streamChat(
                    model: model, history: history, options: options)
                {
                    switch event {
                    case .thinking(let token):
                        thinking += token
                        tab.streamingThinkingText = thinking
                    case .content(let token):
                        answer += token
                        tab.streamingText = answer
                    }
                }

                try await completeGeneration(
                    database: database,
                    tab: tab,
                    conversationID: conversationID,
                    answer: answer,
                    thinking: thinking)
            } catch {
                guard let conversationID else {
                    handleGenerationError(error, tab: tab)
                    return
                }
                if Task.isCancelled || isCancellation(error) {
                    do {
                        try await completeGeneration(
                            database: database,
                            tab: tab,
                            conversationID: conversationID,
                            answer: answer,
                            thinking: thinking)
                    } catch {
                        handleGenerationError(error, tab: tab)
                    }
                } else {
                    handleGenerationError(error, tab: tab)
                }
            }
        }
    }

    func cancelStreaming() {
        guard let tab = activeTab else { return }
        generationTasks[tab.id]?.cancel()
    }

    private func completeGeneration(
        database: any ChatDatabase,
        tab: ChatTab,
        conversationID: Int64,
        answer: String,
        thinking: String
    ) async throws {
        let message = try await database.insertMessage(
            conversationId: conversationID,
            role: "assistant",
            content: answer,
            thinking: thinking.isEmpty ? nil : thinking)
        tab.isStreaming = false
        tab.streamingText = nil
        tab.streamingThinkingText = nil
        tab.messages.append(message)
        generationTasks[tab.id] = nil
        conversations = try await database.listConversations()
    }

    private func handleGenerationError(_ error: Error, tab: ChatTab) {
        tab.isStreaming = false
        tab.streamingText = nil
        tab.streamingThinkingText = nil
        generationTasks[tab.id] = nil
        report(error)
    }

    func refreshModels() async {
        ollamaStatus = .checking
        do {
            models = try await ollama.listModels()
            guard !models.isEmpty else {
                ollamaStatus = .noModels
                return
            }
            if !models.contains(where: { $0.name == defaultModel }), let first = models.first {
                defaultModel = first.name
            }
            for tab in tabs where !models.contains(where: { $0.name == tab.selectedModel }) {
                tab.selectedModel = defaultModel
            }
            ollamaStatus = .ready
        } catch {
            models = []
            ollamaStatus = .unavailable
        }
    }

    private func persistGenerationOptions() {
        if let data = try? JSONEncoder().encode(generationOptions) {
            defaults.set(data, forKey: AppState.generationOptionsKey)
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
}
