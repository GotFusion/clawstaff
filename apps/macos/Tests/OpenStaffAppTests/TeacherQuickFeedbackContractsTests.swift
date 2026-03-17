import Foundation
import XCTest
@testable import OpenStaffApp

final class TeacherQuickFeedbackContractsTests: XCTestCase {
    func testV0QuickActionsStayFixedAndKeepUnifiedHotkeys() {
        XCTAssertEqual(
            TeacherQuickFeedbackAction.quickActions,
            [
                .approved,
                .rejected,
                .fixLocator,
                .reteach,
                .tooDangerous,
                .wrongOrder,
                .wrongStyle
            ]
        )
        XCTAssertFalse(TeacherQuickFeedbackAction.quickActions.contains(.needsRevision))
        XCTAssertEqual(
            TeacherQuickFeedbackAction.quickActions.map { $0.shortcut.displayLabel },
            ["Cmd+1", "Cmd+2", "Cmd+3", "Cmd+4", "Cmd+5", "Cmd+6", "Cmd+7"]
        )
    }

    func testTeacherFeedbackWriteEntryEmbedsStandardizedTeacherReviewEvidence() throws {
        let entry = TeacherFeedbackWriteEntry(
            feedbackId: "feedback-001",
            timestamp: "2026-03-17T10:00:00Z",
            decision: .wrongOrder,
            note: "先点错了按钮，再切回目标窗口。",
            sessionId: "session-001",
            taskId: "task-001",
            logEntryId: "/tmp/openstaff.log#L3",
            logStatus: "EXECUTION_FAILED",
            logMessage: "步骤顺序错误",
            component: "student.review"
        )

        XCTAssertEqual(entry.schemaVersion, "teacher.feedback.v2")
        XCTAssertEqual(entry.teacherReview.source, "teacherReview")
        XCTAssertEqual(entry.teacherReview.action, .wrongOrder)
        XCTAssertEqual(entry.teacherReview.evidenceType, .evaluative)
        XCTAssertEqual(entry.teacherReview.category, .executionOrder)
        XCTAssertEqual(entry.teacherReview.polarity, .negative)
        XCTAssertEqual(entry.teacherReview.summary, "老师指出本次执行的步骤顺序不对。")
        XCTAssertEqual(entry.teacherReview.shortcut.displayLabel, "Cmd+6")
        XCTAssertEqual(entry.teacherReview.shortcutId, "teacher.quick-feedback.wrongOrder")
        XCTAssertEqual(entry.teacherReview.note, "先点错了按钮，再切回目标窗口。")

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TeacherFeedbackWriteEntry.self, from: data)
        XCTAssertEqual(decoded.teacherReview, entry.teacherReview)
    }

    func testFixLocatorEvidenceCarriesDirectiveRepairHint() {
        let evidence = TeacherQuickFeedbackAction.fixLocator.makeTeacherReviewEvidence(
            note: "确认按钮标题变化了。",
            repairActionType: "updateSkillLocator"
        )

        XCTAssertEqual(evidence.evidenceType, .directive)
        XCTAssertEqual(evidence.category, .locatorRepair)
        XCTAssertEqual(evidence.repairActionType, "updateSkillLocator")
        XCTAssertEqual(evidence.shortcut.displayLabel, "Cmd+3")
    }
}
