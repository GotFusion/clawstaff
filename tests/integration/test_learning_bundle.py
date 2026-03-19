import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tests.swift_cli_test_utils import run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]
EXPORT_SCRIPT = REPO_ROOT / "scripts/learning/export_learning_bundle.py"
VERIFY_SCRIPT = REPO_ROOT / "scripts/learning/verify_learning_bundle.py"


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, payloads: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n" for payload in payloads)
    path.write_text(text, encoding="utf-8")


def run_python(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def make_profile_snapshot(profile_version: str, rule_id: str, updated_at: str, note: str) -> dict:
    directive = {
        "ruleId": rule_id,
        "type": "style",
        "scope": {"level": "global"},
        "statement": "Keep answers concise.",
        "hint": "Lead with the result and trim extra commentary.",
        "proposedAction": "prefer_concise_copy",
        "teacherConfirmed": True,
        "updatedAt": updated_at,
    }
    return {
        "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
        "profileVersion": profile_version,
        "profile": {
            "schemaVersion": "openstaff.learning.preference-profile.v0",
            "profileVersion": profile_version,
            "activeRuleIds": [rule_id],
            "assistPreferences": [directive],
            "skillPreferences": [directive],
            "repairPreferences": [],
            "reviewPreferences": [directive],
            "plannerPreferences": [],
            "generatedAt": updated_at,
        },
        "sourceRuleIds": [rule_id],
        "createdAt": updated_at,
        "previousProfileVersion": None,
        "note": note,
    }


def seed_workspace(workspace_root: Path) -> dict[str, Path]:
    learning_root = workspace_root / "data/learning"
    preferences_root = workspace_root / "data/preferences"

    turns_root = learning_root / "turns"
    evidence_root = learning_root / "evidence"
    signals_root = preferences_root / "signals"
    rules_root = preferences_root / "rules"
    profiles_root = preferences_root / "profiles"
    audit_root = preferences_root / "audit"

    write_json(
        turns_root / "2026-03-19/session-001/turn-001.json",
        {
            "schemaVersion": "openstaff.learning.interaction-turn.v0",
            "turnId": "turn-001",
            "traceId": "trace-001",
            "sessionId": "session-001",
            "taskId": "task-001",
            "stepId": "step-001",
            "mode": "teaching",
            "turnKind": "taskProgression",
            "stepIndex": 1,
            "intentSummary": "Teach the assistant how to summarize a page.",
            "actionSummary": "Teacher demonstrated the preferred summary style.",
            "actionKind": "guiAction",
            "status": "succeeded",
            "learningState": "reviewed",
            "privacyTags": [],
            "riskLevel": "low",
            "appContext": {
                "appName": "Safari",
                "appBundleId": "com.apple.Safari",
                "windowTitle": "OpenStaff Docs",
                "windowId": "window-001",
                "windowSignature": "signature-001",
            },
            "observationRef": {
                "sourceRecordPath": "data/source-records/session-001.json",
                "rawEventLogPath": "data/raw-events/session-001.jsonl",
                "taskChunkPath": "data/task-chunks/session-001.json",
                "eventIds": ["event-001"],
                "screenshotRefs": [],
                "axRefs": [],
                "ocrRefs": [],
                "appContext": {
                    "appName": "Safari",
                    "appBundleId": "com.apple.Safari",
                    "windowTitle": "OpenStaff Docs",
                    "windowId": "window-001",
                    "windowSignature": "signature-001",
                },
                "note": "test fixture",
            },
            "semanticTargetSetRef": None,
            "stepReference": {
                "stepId": "step-001",
                "stepIndex": 1,
                "instruction": "Summarize the current page.",
                "knowledgeItemId": "knowledge-001",
                "knowledgeStepId": "knowledge-step-001",
                "skillStepId": "skill-step-001",
                "planStepId": None,
                "sourceEventIds": ["event-001"],
            },
            "execution": None,
            "review": {
                "reviewId": "review-001",
                "source": "teacherReview",
                "decision": "accepted",
                "summary": "This is the preferred concise style.",
                "note": None,
                "reviewedAt": "2026-03-19T08:10:00Z",
                "rawRef": "data/reviews/review-001.json",
            },
            "sourceRefs": [],
            "startedAt": "2026-03-19T08:00:00Z",
            "endedAt": "2026-03-19T08:01:00Z",
        },
    )
    write_json(
        turns_root / "2026-03-19/session-002/turn-ignored.json",
        {
            "schemaVersion": "openstaff.learning.interaction-turn.v0",
            "turnId": "turn-ignored",
            "traceId": "trace-ignored",
            "sessionId": "session-002",
            "taskId": "task-ignored",
            "stepId": "step-ignored",
            "mode": "teaching",
            "turnKind": "taskProgression",
            "stepIndex": 1,
            "intentSummary": "Ignored turn.",
            "actionSummary": "Ignored action.",
            "actionKind": "guiAction",
            "status": "succeeded",
            "learningState": "reviewed",
            "privacyTags": [],
            "riskLevel": "low",
            "appContext": {
                "appName": "Finder",
                "appBundleId": "com.apple.finder",
                "windowTitle": "Ignored",
                "windowId": "window-ignored",
                "windowSignature": "signature-ignored",
            },
            "observationRef": {
                "sourceRecordPath": None,
                "rawEventLogPath": None,
                "taskChunkPath": None,
                "eventIds": [],
                "screenshotRefs": [],
                "axRefs": [],
                "ocrRefs": [],
                "appContext": {
                    "appName": "Finder",
                    "appBundleId": "com.apple.finder",
                    "windowTitle": "Ignored",
                    "windowId": "window-ignored",
                    "windowSignature": "signature-ignored",
                },
                "note": "ignored",
            },
            "semanticTargetSetRef": None,
            "stepReference": {
                "stepId": "step-ignored",
                "stepIndex": 1,
                "instruction": "Ignore this.",
                "knowledgeItemId": "knowledge-ignored",
                "knowledgeStepId": "knowledge-step-ignored",
                "skillStepId": "skill-step-ignored",
                "planStepId": None,
                "sourceEventIds": [],
            },
            "execution": None,
            "review": None,
            "sourceRefs": [],
            "startedAt": "2026-03-19T09:00:00Z",
            "endedAt": "2026-03-19T09:01:00Z",
        },
    )

    write_jsonl(
        evidence_root / "2026-03-19/session-001/turn-001.jsonl",
        [
            {
                "schemaVersion": "openstaff.learning.next-state-evidence.v0",
                "evidenceId": "evidence-001",
                "turnId": "turn-001",
                "traceId": "trace-001",
                "sessionId": "session-001",
                "taskId": "task-001",
                "stepId": "step-001",
                "source": "teacherReview",
                "summary": "Teacher asked for a shorter answer.",
                "rawRefs": [],
                "timestamp": "2026-03-19T08:02:00Z",
                "confidence": 1.0,
                "severity": "warning",
                "role": "directive",
                "guiFailureBucket": None,
                "evaluativeCandidate": {"decision": "fail", "polarity": "negative", "rationale": "Too verbose."},
                "directiveCandidate": {"action": "rewrite_summary", "hint": "Keep it short.", "repairActionType": None},
            },
            {
                "schemaVersion": "openstaff.learning.next-state-evidence.v0",
                "evidenceId": "evidence-002",
                "turnId": "turn-001",
                "traceId": "trace-001",
                "sessionId": "session-001",
                "taskId": "task-001",
                "stepId": "step-001",
                "source": "benchmarkResult",
                "summary": "Benchmark preferred the concise answer.",
                "rawRefs": [],
                "timestamp": "2026-03-19T08:03:00Z",
                "confidence": 0.96,
                "severity": "info",
                "role": "evaluative",
                "guiFailureBucket": None,
                "evaluativeCandidate": {"decision": "pass", "polarity": "positive", "rationale": "Matches preference."},
                "directiveCandidate": None,
            },
        ],
    )
    write_jsonl(
        evidence_root / "2026-03-19/session-002/turn-ignored.jsonl",
        [
            {
                "schemaVersion": "openstaff.learning.next-state-evidence.v0",
                "evidenceId": "evidence-ignored",
                "turnId": "turn-ignored",
                "traceId": "trace-ignored",
                "sessionId": "session-002",
                "taskId": "task-ignored",
                "stepId": "step-ignored",
                "source": "teacherReview",
                "summary": "Ignored evidence.",
                "rawRefs": [],
                "timestamp": "2026-03-19T09:02:00Z",
                "confidence": 0.8,
                "severity": "info",
                "role": "evaluative",
                "guiFailureBucket": None,
                "evaluativeCandidate": {"decision": "neutral", "polarity": "neutral", "rationale": None},
                "directiveCandidate": None,
            }
        ],
    )

    write_json(
        signals_root / "2026-03-19/session-001/turn-001.json",
        [
            {
                "schemaVersion": "openstaff.learning.preference-signal.v0",
                "signalId": "signal-001",
                "turnId": "turn-001",
                "traceId": "trace-001",
                "sessionId": "session-001",
                "taskId": "task-001",
                "stepId": "step-001",
                "type": "style",
                "evaluativeDecision": "fail",
                "polarity": "reinforce",
                "scope": {"level": "global"},
                "hint": "Lead with the conclusion and keep the wording compact.",
                "confidence": 0.91,
                "evidenceIds": ["evidence-001"],
                "proposedAction": "prefer_concise_copy",
                "promotionStatus": "confirmed",
                "timestamp": "2026-03-19T08:04:00Z",
            },
            {
                "schemaVersion": "openstaff.learning.preference-signal.v0",
                "signalId": "signal-002",
                "turnId": "turn-001",
                "traceId": "trace-001",
                "sessionId": "session-001",
                "taskId": "task-001",
                "stepId": "step-001",
                "type": "style",
                "evaluativeDecision": "pass",
                "polarity": "reinforce",
                "scope": {"level": "global"},
                "hint": "Keep the concise style stable.",
                "confidence": 0.95,
                "evidenceIds": ["evidence-002"],
                "proposedAction": "prefer_concise_copy",
                "promotionStatus": "confirmed",
                "timestamp": "2026-03-19T08:05:00Z",
            },
        ],
    )
    write_json(
        signals_root / "2026-03-19/session-002/turn-ignored.json",
        [
            {
                "schemaVersion": "openstaff.learning.preference-signal.v0",
                "signalId": "signal-ignored",
                "turnId": "turn-ignored",
                "traceId": "trace-ignored",
                "sessionId": "session-002",
                "taskId": "task-ignored",
                "stepId": "step-ignored",
                "type": "style",
                "evaluativeDecision": "neutral",
                "polarity": "neutral",
                "scope": {"level": "global"},
                "hint": "Ignore this signal.",
                "confidence": 0.7,
                "evidenceIds": ["evidence-ignored"],
                "proposedAction": "ignore_signal",
                "promotionStatus": "candidate",
                "timestamp": "2026-03-19T09:03:00Z",
            }
        ],
    )

    write_json(
        rules_root / "rule-001.json",
        {
            "schemaVersion": "openstaff.learning.preference-rule.v0",
            "ruleId": "rule-001",
            "sourceSignalIds": ["signal-001", "signal-002"],
            "scope": {"level": "global"},
            "type": "style",
            "polarity": "reinforce",
            "statement": "Keep answers concise and conclusion-first.",
            "hint": "Lead with the result and trim extra commentary.",
            "proposedAction": "prefer_concise_copy",
            "evidence": [
                {
                    "signalId": "signal-001",
                    "turnId": "turn-001",
                    "traceId": "trace-001",
                    "sessionId": "session-001",
                    "taskId": "task-001",
                    "stepId": "step-001",
                    "evidenceIds": ["evidence-001"],
                    "confidence": 0.91,
                    "timestamp": "2026-03-19T08:04:00Z",
                },
                {
                    "signalId": "signal-002",
                    "turnId": "turn-001",
                    "traceId": "trace-001",
                    "sessionId": "session-001",
                    "taskId": "task-001",
                    "stepId": "step-001",
                    "evidenceIds": ["evidence-002"],
                    "confidence": 0.95,
                    "timestamp": "2026-03-19T08:05:00Z",
                },
            ],
            "riskLevel": "low",
            "governance": None,
            "activationStatus": "active",
            "teacherConfirmed": True,
            "supersededByRuleId": None,
            "lifecycleReason": None,
            "createdAt": "2026-03-19T08:06:00Z",
            "updatedAt": "2026-03-19T08:06:00Z",
        },
    )
    write_json(
        rules_root / "rule-ignored.json",
        {
            "schemaVersion": "openstaff.learning.preference-rule.v0",
            "ruleId": "rule-ignored",
            "sourceSignalIds": ["signal-ignored"],
            "scope": {"level": "global"},
            "type": "style",
            "polarity": "reinforce",
            "statement": "Ignored rule.",
            "hint": "Ignore this.",
            "proposedAction": "ignore_rule",
            "evidence": [
                {
                    "signalId": "signal-ignored",
                    "turnId": "turn-ignored",
                    "traceId": "trace-ignored",
                    "sessionId": "session-002",
                    "taskId": "task-ignored",
                    "stepId": "step-ignored",
                    "evidenceIds": ["evidence-ignored"],
                    "confidence": 0.7,
                    "timestamp": "2026-03-19T09:04:00Z",
                }
            ],
            "riskLevel": "low",
            "governance": None,
            "activationStatus": "active",
            "teacherConfirmed": True,
            "supersededByRuleId": None,
            "lifecycleReason": None,
            "createdAt": "2026-03-19T09:04:00Z",
            "updatedAt": "2026-03-19T09:04:00Z",
        },
    )

    write_json(
        profiles_root / "profile-001.json",
        make_profile_snapshot(
            profile_version="profile-001",
            rule_id="rule-001",
            updated_at="2026-03-19T08:07:00Z",
            note="Relevant concise profile.",
        ),
    )
    write_json(
        profiles_root / "profile-ignored.json",
        make_profile_snapshot(
            profile_version="profile-ignored",
            rule_id="rule-ignored",
            updated_at="2026-03-19T09:05:00Z",
            note="Ignored profile.",
        ),
    )
    write_json(
        profiles_root / "latest.json",
        {
            "schemaVersion": "openstaff.learning.preference-profile-pointer.v0",
            "profileVersion": "profile-001",
            "updatedAt": "2026-03-19T08:07:00Z",
        },
    )

    write_jsonl(
        audit_root / "2026-03-19.jsonl",
        [
            {
                "schemaVersion": "openstaff.learning.preference-audit.v0",
                "auditId": "audit-signal-001",
                "action": "signalStored",
                "timestamp": "2026-03-19T08:04:30Z",
                "actor": "system",
                "source": {"kind": "signalIngestion", "referenceId": "signal-001", "summary": "Stored signal."},
                "signalIds": ["signal-001", "signal-002"],
                "ruleId": None,
                "affectedRuleIds": [],
                "profileVersion": None,
                "relatedProfileVersion": None,
                "previousActivationStatus": None,
                "newActivationStatus": None,
                "relatedRuleId": None,
                "note": "Stored relevant signals.",
            },
            {
                "schemaVersion": "openstaff.learning.preference-audit.v0",
                "auditId": "audit-rule-001",
                "action": "rulePromoted",
                "timestamp": "2026-03-19T08:06:30Z",
                "actor": "system",
                "source": {"kind": "rulePromotion", "referenceId": "rule-001", "summary": "Promoted relevant rule."},
                "signalIds": ["signal-001", "signal-002"],
                "ruleId": "rule-001",
                "affectedRuleIds": ["rule-001"],
                "profileVersion": None,
                "relatedProfileVersion": None,
                "previousActivationStatus": None,
                "newActivationStatus": "active",
                "relatedRuleId": None,
                "note": "Promoted relevant rule.",
            },
            {
                "schemaVersion": "openstaff.learning.preference-audit.v0",
                "auditId": "audit-profile-001",
                "action": "profileSnapshotStored",
                "timestamp": "2026-03-19T08:07:30Z",
                "actor": "system",
                "source": {"kind": "profileBuilder", "referenceId": "profile-001", "summary": "Stored relevant profile."},
                "signalIds": [],
                "ruleId": None,
                "affectedRuleIds": [],
                "profileVersion": "profile-001",
                "relatedProfileVersion": None,
                "previousActivationStatus": None,
                "newActivationStatus": None,
                "relatedRuleId": None,
                "note": "Stored relevant profile.",
            },
            {
                "schemaVersion": "openstaff.learning.preference-audit.v0",
                "auditId": "audit-ignored",
                "action": "rulePromoted",
                "timestamp": "2026-03-19T09:05:30Z",
                "actor": "system",
                "source": {"kind": "rulePromotion", "referenceId": "rule-ignored", "summary": "Ignored rule."},
                "signalIds": ["signal-ignored"],
                "ruleId": "rule-ignored",
                "affectedRuleIds": ["rule-ignored"],
                "profileVersion": "profile-ignored",
                "relatedProfileVersion": None,
                "previousActivationStatus": None,
                "newActivationStatus": "active",
                "relatedRuleId": None,
                "note": "Ignored audit entry.",
            },
        ],
    )

    return {
        "learning_root": learning_root,
        "preferences_root": preferences_root,
    }


class LearningBundleIntegrationTests(unittest.TestCase):
    def test_export_verify_restore_roundtrip_and_rebuild_profile(self):
        with tempfile.TemporaryDirectory(prefix="openstaff-learning-bundle-") as tmp_dir:
            workspace_root = Path(tmp_dir) / "source"
            restore_root = Path(tmp_dir) / "restored"
            bundle_root = Path(tmp_dir) / "bundle"
            seeded = seed_workspace(workspace_root)

            export_result = run_python(
                [
                    str(EXPORT_SCRIPT),
                    "--learning-root",
                    str(seeded["learning_root"]),
                    "--preferences-root",
                    str(seeded["preferences_root"]),
                    "--output",
                    str(bundle_root),
                    "--session-id",
                    "session-001",
                    "--json",
                ]
            )

            self.assertEqual(export_result.returncode, 0, msg=export_result.stderr or export_result.stdout)
            export_payload = json.loads(export_result.stdout)
            self.assertTrue(export_payload["passed"])
            self.assertEqual(export_payload["counts"]["turns"]["records"], 1)
            self.assertEqual(export_payload["counts"]["evidence"]["records"], 2)
            self.assertEqual(export_payload["counts"]["signals"]["records"], 2)
            self.assertEqual(export_payload["counts"]["rules"]["records"], 1)
            self.assertEqual(export_payload["counts"]["profiles"]["records"], 1)
            self.assertEqual(export_payload["counts"]["audit"]["records"], 3)

            verify_result = run_python(
                [
                    str(VERIFY_SCRIPT),
                    "--bundle",
                    str(bundle_root),
                    "--json",
                ]
            )

            self.assertEqual(verify_result.returncode, 0, msg=verify_result.stderr or verify_result.stdout)
            verify_payload = json.loads(verify_result.stdout)
            self.assertTrue(verify_payload["passed"])
            self.assertEqual(verify_payload["verification"]["counts"]["rules"]["records"], 1)

            preview_result = run_python(
                [
                    str(VERIFY_SCRIPT),
                    "--bundle",
                    str(bundle_root),
                    "--restore-workspace-root",
                    str(restore_root),
                    "--json",
                ]
            )

            self.assertEqual(preview_result.returncode, 0, msg=preview_result.stderr or preview_result.stdout)
            preview_payload = json.loads(preview_result.stdout)
            self.assertTrue(preview_payload["restorePreview"]["restoreReady"])
            self.assertEqual(len(preview_payload["restorePreview"]["plannedWrites"]), 6)
            self.assertFalse((restore_root / "data/preferences/rules/rule-001.json").exists())

            restore_result = run_python(
                [
                    str(VERIFY_SCRIPT),
                    "--bundle",
                    str(bundle_root),
                    "--restore-workspace-root",
                    str(restore_root),
                    "--apply",
                    "--json",
                ]
            )

            self.assertEqual(restore_result.returncode, 0, msg=restore_result.stderr or restore_result.stdout)
            restore_payload = json.loads(restore_result.stdout)
            self.assertTrue(restore_payload["restoreResult"]["applied"])
            self.assertTrue((restore_root / "data/learning/turns/2026-03-19/session-001/turn-001.json").exists())
            self.assertTrue((restore_root / "data/preferences/rules/rule-001.json").exists())
            self.assertFalse((restore_root / "data/preferences/rules/rule-ignored.json").exists())

            latest_pointer = json.loads(
                (restore_root / "data/preferences/profiles/latest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(latest_pointer["profileVersion"], "profile-001")

            rebuild_result = run_swift_target(
                "OpenStaffPreferenceProfileCLI",
                [
                    "--preferences-root",
                    str(restore_root / "data/preferences"),
                    "--rebuild",
                    "--profile-version",
                    "profile-rebuilt-001",
                    "--timestamp",
                    "2026-03-19T12:00:00Z",
                    "--json",
                ],
            )

            self.assertEqual(rebuild_result.returncode, 0, msg=rebuild_result.stderr or rebuild_result.stdout)
            rebuild_payload = json.loads(rebuild_result.stdout)
            self.assertEqual(rebuild_payload["snapshot"]["profileVersion"], "profile-rebuilt-001")
            self.assertEqual(rebuild_payload["snapshot"]["profile"]["activeRuleIds"], ["rule-001"])
            self.assertEqual(
                rebuild_payload["snapshot"]["profile"]["assistPreferences"][0]["ruleId"],
                "rule-001",
            )

    def test_restore_preview_reports_conflicts_without_applying(self):
        with tempfile.TemporaryDirectory(prefix="openstaff-learning-bundle-conflict-") as tmp_dir:
            workspace_root = Path(tmp_dir) / "source"
            restore_root = Path(tmp_dir) / "restore"
            bundle_root = Path(tmp_dir) / "bundle"
            seeded = seed_workspace(workspace_root)

            export_result = run_python(
                [
                    str(EXPORT_SCRIPT),
                    "--learning-root",
                    str(seeded["learning_root"]),
                    "--preferences-root",
                    str(seeded["preferences_root"]),
                    "--output",
                    str(bundle_root),
                    "--session-id",
                    "session-001",
                    "--json",
                ]
            )
            self.assertEqual(export_result.returncode, 0, msg=export_result.stderr or export_result.stdout)

            conflicting_path = restore_root / "data/preferences/rules/rule-001.json"
            write_json(conflicting_path, {"existing": True})

            preview_result = run_python(
                [
                    str(VERIFY_SCRIPT),
                    "--bundle",
                    str(bundle_root),
                    "--restore-workspace-root",
                    str(restore_root),
                    "--json",
                ]
            )

            self.assertEqual(preview_result.returncode, 0, msg=preview_result.stderr or preview_result.stdout)
            preview_payload = json.loads(preview_result.stdout)
            self.assertFalse(preview_payload["restorePreview"]["restoreReady"])
            self.assertEqual(preview_payload["restorePreview"]["conflictCount"], 1)
            current_content = json.loads(conflicting_path.read_text(encoding="utf-8"))
            self.assertEqual(current_content, {"existing": True})


if __name__ == "__main__":
    unittest.main()
