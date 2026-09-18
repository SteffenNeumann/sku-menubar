import XCTest
@testable import myClaude

/// Der Store ersetzt die fehlende Agent-Info im CLI-Transcript — ohne ihn verlor jeder
/// wieder geöffnete Chat sein Agent-Badge.
final class SessionAgentStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SessionAgentStoreTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRememberAndLookup() {
        let store = SessionAgentStore(defaults: defaults)
        store.remember(sessionId: "s1", agentId: "project-manager", agentName: "project-manager")
        XCTAssertEqual(store.entry(for: "s1")?.agentId, "project-manager")
        XCTAssertNil(store.entry(for: "unbekannt"))
    }

    func testLastAgentWins() {
        let store = SessionAgentStore(defaults: defaults)
        store.remember(sessionId: "s1", agentId: "a", agentName: "A")
        store.remember(sessionId: "s1", agentId: "b", agentName: "B")
        XCTAssertEqual(store.entry(for: "s1")?.agentName, "B")
    }

    func testSurvivesNewInstance() {
        SessionAgentStore(defaults: defaults).remember(sessionId: "s1", agentId: "a", agentName: "A")
        XCTAssertEqual(SessionAgentStore(defaults: defaults).entry(for: "s1")?.agentId, "a")
    }

    func testForgetRemovesEntry() {
        let store = SessionAgentStore(defaults: defaults)
        store.remember(sessionId: "s1", agentId: "a", agentName: "A")
        store.forget(sessionId: "s1")
        XCTAssertNil(store.entry(for: "s1"))
    }

    func testEmptyIdsIgnored() {
        let store = SessionAgentStore(defaults: defaults)
        store.remember(sessionId: "", agentId: "a", agentName: "A")
        store.remember(sessionId: "s1", agentId: "", agentName: "A")
        XCTAssertNil(store.entry(for: ""))
        XCTAssertNil(store.entry(for: "s1"))
    }

    func testOldestEntriesPrunedAtCap() {
        let store = SessionAgentStore(defaults: defaults)
        let base = Date(timeIntervalSince1970: 0)
        for i in 0...SessionAgentStore.maxEntries {
            store.remember(sessionId: "s\(i)", agentId: "a", agentName: "A",
                           at: base.addingTimeInterval(Double(i)))
        }
        XCTAssertNil(store.entry(for: "s0"), "ältester Eintrag muss weichen")
        XCTAssertNotNil(store.entry(for: "s\(SessionAgentStore.maxEntries)"))
    }
}
