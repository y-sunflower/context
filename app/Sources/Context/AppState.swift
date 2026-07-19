import ContextCore
import Foundation
import Observation

extension Conversation: Identifiable {}
extension Message: Identifiable {}

@Observable @MainActor
final class AppState {
    static let defaultModel = "gemma4:26b"

    enum OllamaStatus: Equatable {
        case checking
        case unavailable
        case noModels
        case ready
    }

    @ObservationIgnored private var core: ContextCore?

    var conversations: [Conversation] = []
    var selectedConversationID: Int64? {
        didSet { conversationSelectionChanged() }
    }
    var messages: [Message] = []
    /// Assistant text accumulated so far for the in-flight response.
    var streamingText: String?
    var isStreaming = false
    var models: [ModelInfo] = []
    var selectedModel = AppState.defaultModel
    var ollamaStatus = OllamaStatus.checking
    var errorMessage: String?
    var composerDraft = ""
    var composerFocusRequest = 0

    var canStartChat: Bool { ollamaStatus == .ready }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("Context", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let core = try ContextCore(dbPath: dir.appendingPathComponent("context.db").path)
            self.core = core
            conversations = try core.listConversations()
            selectedConversationID = conversations.first?.id
            conversationSelectionChanged()
        } catch {
            errorMessage = "Failed to open the local database: \(error)"
        }
        Task { await refreshModels() }
    }

    // MARK: - Conversations

    func newChat() {
        guard let core, canStartChat else { return }
        do {
            let conversation = try core.createConversation(model: selectedModel)
            conversations = try core.listConversations()
            selectedConversationID = conversation.id
        } catch {
            report(error)
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        guard let core else { return }
        do {
            core.cancel(conversationId: conversation.id)
            try core.deleteConversation(conversationId: conversation.id)
            conversations = try core.listConversations()
            if selectedConversationID == conversation.id {
                selectedConversationID = conversations.first?.id
            }
        } catch {
            report(error)
        }
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        guard let core else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try core.renameConversation(conversationId: conversation.id, title: trimmed)
            conversations = try core.listConversations()
        } catch {
            report(error)
        }
    }

    private func conversationSelectionChanged() {
        guard let core, let id = selectedConversationID else {
            messages = []
            return
        }
        do {
            messages = try core.getMessages(conversationId: id)
            if let model = selectedConversation?.model, !model.isEmpty {
                selectedModel = model
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Chat

    func branch(from message: Message) {
        guard let core, !isStreaming, message.role == "user" else { return }
        do {
            let conversation = try core.branchConversation(
                conversationId: message.conversationId,
                beforeMessageId: message.id)
            conversations = try core.listConversations()
            selectedConversationID = conversation.id
            composerDraft = message.content
            composerFocusRequest += 1
        } catch {
            report(error)
        }
    }

    func send(_ text: String) {
        guard let core, !isStreaming else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        do {
            if selectedConversationID == nil {
                let conversation = try core.createConversation(model: selectedModel)
                conversations = try core.listConversations()
                selectedConversationID = conversation.id
            }
            guard let id = selectedConversationID else { return }
            isStreaming = true
            streamingText = ""
            try core.sendMessage(
                conversationId: id,
                content: content,
                model: selectedModel,
                listener: StreamListener(state: self, conversationID: id))
            // The user message is persisted synchronously by sendMessage.
            messages = try core.getMessages(conversationId: id)
            conversations = try core.listConversations()
        } catch {
            isStreaming = false
            streamingText = nil
            report(error)
        }
    }

    func cancelStreaming() {
        guard let core, let id = selectedConversationID else { return }
        core.cancel(conversationId: id)
    }

    func refreshModels() async {
        guard let core else { return }
        ollamaStatus = .checking
        do {
            models = try await core.listModels()
            guard !models.isEmpty else {
                ollamaStatus = .noModels
                return
            }
            if !models.contains(where: { $0.name == selectedModel }),
                let first = models.first
            {
                selectedModel = first.name
            }
            ollamaStatus = .ready
        } catch {
            models = []
            ollamaStatus = .unavailable
        }
    }

    // MARK: - Stream callbacks (hopped to MainActor by StreamListener)

    func handleToken(conversationID: Int64, token: String) {
        guard conversationID == selectedConversationID else { return }
        streamingText = (streamingText ?? "") + token
    }

    func handleComplete(conversationID: Int64, message: Message) {
        isStreaming = false
        streamingText = nil
        if conversationID == selectedConversationID {
            messages.append(message)
        }
        if let core {
            conversations = (try? core.listConversations()) ?? conversations
        }
    }

    func handleError(conversationID: Int64, error: String) {
        isStreaming = false
        streamingText = nil
        errorMessage = error
    }

    private func report(_ error: Error) {
        errorMessage = String(describing: error)
    }
}

/// Bridges UniFFI's `ChatListener` callbacks (invoked on a tokio worker
/// thread) onto the MainActor.
final class StreamListener: ChatListener, @unchecked Sendable {
    private weak var state: AppState?
    private let conversationID: Int64

    init(state: AppState, conversationID: Int64) {
        self.state = state
        self.conversationID = conversationID
    }

    func onToken(token: String) {
        Task { @MainActor in
            self.state?.handleToken(conversationID: self.conversationID, token: token)
        }
    }

    func onComplete(message: Message) {
        Task { @MainActor in
            self.state?.handleComplete(conversationID: self.conversationID, message: message)
        }
    }

    func onError(error: String) {
        Task { @MainActor in
            self.state?.handleError(conversationID: self.conversationID, error: error)
        }
    }
}
