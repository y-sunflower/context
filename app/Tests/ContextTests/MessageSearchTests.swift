import ContextCore
import XCTest
@testable import Context

final class MessageSearchTests: XCTestCase {
    func testNormalization() {
        XCTAssertEqual(MessageSearch.normalize("  CAFÉ\nChat  "), "cafe chat")
    }

    func testExactAboveFuzzy() {
        let corpus = [
            message(id: 1, content: "conversation search"),
            message(id: 2, content: "scatter every apple rapidly, crossing hills"),
        ]
        let matches = MessageSearch.matches(query: "search", in: corpus)
        XCTAssertEqual(matches.map(\.id), [1, 2])
    }

    func testFuzzyPartial() {
        let matches = MessageSearch.matches(
            query: "msg srch",
            in: [message(id: 1, content: "message search")])
        XCTAssertEqual(matches.map(\.id), [1])
    }

    func testExcludesAndCaps() {
        let corpus = (1...12).map { message(id: Int64($0), content: "matching text \($0)") }
            + [message(id: 20, content: "unrelated")]
        let matches = MessageSearch.matches(query: "matching", in: corpus, limit: 10)
        XCTAssertEqual(matches.count, 10)
        XCTAssertFalse(matches.contains(where: { $0.id == 20 }))
    }

    func testGrouping() {
        let olderStrong = message(
            id: 1, conversationID: 1, title: "Older", updatedAt: 10,
            content: "search")
        let newerWeak = message(
            id: 2, conversationID: 2, title: "Newer", updatedAt: 20,
            content: "something else")
        let groups = MessageSearch.groups(for: [
            MessageSearchMatch(message: olderStrong, score: 100),
            MessageSearchMatch(message: newerWeak, score: 10),
        ])
        XCTAssertEqual(groups.map(\.title), ["Newer", "Older"])
    }

    private func message(
        id: Int64,
        conversationID: Int64 = 1,
        title: String = "Chat",
        updatedAt: Int64 = 1,
        content: String
    ) -> SearchableMessage {
        SearchableMessage(
            id: id,
            conversationId: conversationID,
            conversationTitle: title,
            conversationUpdatedAt: updatedAt,
            role: "user",
            content: content,
            createdAt: id)
    }
}
