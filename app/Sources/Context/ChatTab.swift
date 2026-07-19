import Foundation
import Observation

@Observable @MainActor
final class ChatTab: Identifiable {
    let id: UUID
    var conversationID: Int64?
    var messages: [Message]
    var selectedModel: String
    var composerDraft: String
    var composerFocusRequest = 0
    var editingMessageID: Int64?
    var pendingMessageJumpID: Int64?
    var streamingText: String?
    var streamingThinkingText: String?
    var isStreaming = false

    init(
        id: UUID = UUID(),
        conversationID: Int64? = nil,
        messages: [Message] = [],
        selectedModel: String,
        composerDraft: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.messages = messages
        self.selectedModel = selectedModel
        self.composerDraft = composerDraft
    }
}
