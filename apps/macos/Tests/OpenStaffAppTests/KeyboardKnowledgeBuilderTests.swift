import Foundation
import XCTest
@testable import OpenStaffApp

final class KeyboardKnowledgeBuilderTests: XCTestCase {
    func testBuildCombinesInputAndReturnIntoSingleKnowledgeStep() {
        let chunk = makeChunk(eventIds: ["k1", "k2", "k3", "m1"], eventCount: 4)
        let rawEventIndex: [String: RawEvent] = [
            "k1": makeKeyDownEvent(eventId: "k1", keyCode: 4, characters: "h", charactersIgnoringModifiers: "h"),
            "k2": makeKeyDownEvent(eventId: "k2", keyCode: 34, characters: "i", charactersIgnoringModifiers: "i"),
            "k3": makeKeyDownEvent(eventId: "k3", keyCode: 36, characters: "\r", charactersIgnoringModifiers: "\r"),
            "m1": makeMouseClickEvent(eventId: "m1", x: 320, y: 240)
        ]

        let builder = KnowledgeItemBuilder()
        let item = builder.build(from: chunk, rawEventIndex: rawEventIndex)

        XCTAssertEqual(item.steps.count, 2)
        XCTAssertTrue(item.steps[0].instruction.contains("输入\"hi\"并按回车"))
        XCTAssertEqual(item.steps[0].sourceEventIds, ["k1", "k2", "k3"])
        XCTAssertTrue(item.steps[1].instruction.contains("点击"))
        XCTAssertEqual(item.steps[1].sourceEventIds, ["m1"])
    }

    func testBuildCreatesShortcutStepFromModifierKeyDown() {
        let chunk = makeChunk(eventIds: ["k1"], eventCount: 1)
        let rawEventIndex: [String: RawEvent] = [
            "k1": makeKeyDownEvent(
                eventId: "k1",
                keyCode: 8,
                characters: "c",
                charactersIgnoringModifiers: "c",
                modifiers: [.command]
            )
        ]

        let builder = KnowledgeItemBuilder()
        let item = builder.build(from: chunk, rawEventIndex: rawEventIndex)

        XCTAssertEqual(item.steps.count, 1)
        XCTAssertTrue(item.steps[0].instruction.contains("快捷键 command+c"))
        XCTAssertEqual(item.steps[0].sourceEventIds, ["k1"])
    }

    private func makeChunk(eventIds: [String], eventCount: Int) -> TaskChunk {
        TaskChunk(
            taskId: "task-session-test-001",
            sessionId: "session-test",
            startTimestamp: "2026-03-10T10:00:00Z",
            endTimestamp: "2026-03-10T10:00:10Z",
            eventIds: eventIds,
            eventCount: eventCount,
            primaryContext: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            ),
            boundaryReason: .sessionEnd
        )
    }

    private func makeKeyDownEvent(
        eventId: String,
        keyCode: Int,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: [KeyboardModifier] = []
    ) -> RawEvent {
        RawEvent(
            eventId: eventId,
            sessionId: "session-test",
            timestamp: "2026-03-10T10:00:00Z",
            source: .keyboard,
            action: .keyDown,
            pointer: PointerLocation(x: 100, y: 100),
            contextSnapshot: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            ),
            modifiers: modifiers,
            keyboard: KeyboardEventPayload(
                keyCode: keyCode,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isRepeat: false
            )
        )
    }

    private func makeMouseClickEvent(eventId: String, x: Int, y: Int) -> RawEvent {
        RawEvent(
            eventId: eventId,
            sessionId: "session-test",
            timestamp: "2026-03-10T10:00:00Z",
            source: .mouse,
            action: .leftClick,
            pointer: PointerLocation(x: x, y: y),
            contextSnapshot: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            )
        )
    }
}
