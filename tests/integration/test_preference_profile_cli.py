import json
import tempfile
from pathlib import Path
import unittest

from tests.swift_cli_test_utils import run_swift_target


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, payloads: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n" for payload in payloads)
    path.write_text(text, encoding="utf-8")


class PreferenceProfileCLITests(unittest.TestCase):
    def test_cli_rebuilds_and_persists_profile_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="openstaff-preference-profile-cli-") as tmp_dir:
            preferences_root = Path(tmp_dir) / "data/preferences"
            rules_root = preferences_root / "rules"

            write_json(
                rules_root / "rule-global-style-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-rule.v0",
                    "ruleId": "rule-global-style-001",
                    "sourceSignalIds": ["signal-global-style-001"],
                    "scope": {"level": "global"},
                    "type": "style",
                    "polarity": "reinforce",
                    "statement": "Keep review copy concise.",
                    "hint": "Keep responses concise and conclusion-first.",
                    "proposedAction": "shorten_review_copy",
                    "evidence": [
                        {
                            "signalId": "signal-global-style-001",
                            "turnId": "turn-global-style-001",
                            "traceId": "trace-global-style-001",
                            "sessionId": "session-global-style-001",
                            "taskId": "task-global-style-001",
                            "stepId": "step-global-style-001",
                            "evidenceIds": ["evidence-global-style-001"],
                            "confidence": 0.91,
                            "timestamp": "2026-03-19T09:00:00Z",
                        }
                    ],
                    "riskLevel": "low",
                    "activationStatus": "active",
                    "teacherConfirmed": True,
                    "supersededByRuleId": None,
                    "lifecycleReason": None,
                    "createdAt": "2026-03-19T09:00:00Z",
                    "updatedAt": "2026-03-19T09:00:00Z",
                },
            )
            write_json(
                rules_root / "rule-task-risk-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-rule.v0",
                    "ruleId": "rule-task-risk-001",
                    "sourceSignalIds": ["signal-task-risk-001"],
                    "scope": {"level": "taskFamily", "taskFamily": "browser.navigation"},
                    "type": "risk",
                    "polarity": "reinforce",
                    "statement": "Browser navigation should stay confirmation-gated.",
                    "hint": "Require confirmation before risky browser mutations.",
                    "proposedAction": "require_teacher_confirmation",
                    "evidence": [
                        {
                            "signalId": "signal-task-risk-001",
                            "turnId": "turn-task-risk-001",
                            "traceId": "trace-task-risk-001",
                            "sessionId": "session-task-risk-001",
                            "taskId": "task-task-risk-001",
                            "stepId": "step-task-risk-001",
                            "evidenceIds": ["evidence-task-risk-001"],
                            "confidence": 0.94,
                            "timestamp": "2026-03-19T09:10:00Z",
                        }
                    ],
                    "riskLevel": "high",
                    "activationStatus": "active",
                    "teacherConfirmed": True,
                    "supersededByRuleId": None,
                    "lifecycleReason": None,
                    "createdAt": "2026-03-19T09:10:00Z",
                    "updatedAt": "2026-03-19T09:10:00Z",
                },
            )

            result = run_swift_target(
                "OpenStaffPreferenceProfileCLI",
                [
                    "--preferences-root",
                    str(preferences_root),
                    "--rebuild",
                    "--persist",
                    "--profile-version",
                    "profile-2026-03-19-001",
                    "--timestamp",
                    "2026-03-19T10:00:00Z",
                    "--json",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = json.loads(result.stdout)

            self.assertEqual(payload["mode"], "rebuilt_and_persisted")
            self.assertEqual(payload["snapshot"]["profileVersion"], "profile-2026-03-19-001")
            self.assertEqual(
                payload["snapshot"]["profile"]["assistPreferences"][0]["ruleId"],
                "rule-task-risk-001",
            )
            self.assertEqual(
                payload["snapshot"]["profile"]["reviewPreferences"][0]["ruleId"],
                "rule-task-risk-001",
            )
            self.assertTrue((preferences_root / "profiles/profile-2026-03-19-001.json").exists())
            latest_pointer = json.loads((preferences_root / "profiles/latest.json").read_text(encoding="utf-8"))
            self.assertEqual(latest_pointer["profileVersion"], "profile-2026-03-19-001")

    def test_cli_rolls_back_profile_snapshot_with_preview_and_persist(self):
        with tempfile.TemporaryDirectory(prefix="openstaff-preference-profile-rollback-cli-") as tmp_dir:
            preferences_root = Path(tmp_dir) / "data/preferences"
            rules_root = preferences_root / "rules"
            profiles_root = preferences_root / "profiles"

            write_json(
                rules_root / "rule-old-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-rule.v0",
                    "ruleId": "rule-old-001",
                    "sourceSignalIds": ["signal-old-001"],
                    "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"},
                    "type": "style",
                    "polarity": "reinforce",
                    "statement": "Safari tasks should keep responses concise.",
                    "hint": "Keep Safari responses concise.",
                    "proposedAction": "prefer_concise_safari_copy",
                    "evidence": [
                        {
                            "signalId": "signal-old-001",
                            "turnId": "turn-old-001",
                            "traceId": "trace-old-001",
                            "sessionId": "session-old-001",
                            "taskId": "task-old-001",
                            "stepId": "step-old-001",
                            "evidenceIds": ["evidence-old-001"],
                            "confidence": 0.92,
                            "timestamp": "2026-03-19T11:00:00Z",
                        }
                    ],
                    "riskLevel": "low",
                    "activationStatus": "superseded",
                    "teacherConfirmed": True,
                    "supersededByRuleId": "rule-new-001",
                    "lifecycleReason": "Teacher temporarily preferred the detailed appendix style.",
                    "createdAt": "2026-03-19T11:00:00Z",
                    "updatedAt": "2026-03-19T11:20:00Z",
                },
            )
            write_json(
                rules_root / "rule-new-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-rule.v0",
                    "ruleId": "rule-new-001",
                    "sourceSignalIds": ["signal-new-001"],
                    "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"},
                    "type": "style",
                    "polarity": "reinforce",
                    "statement": "Safari tasks should include a detailed appendix.",
                    "hint": "Prefer detailed Safari answers with appendix.",
                    "proposedAction": "prefer_detailed_safari_copy",
                    "evidence": [
                        {
                            "signalId": "signal-new-001",
                            "turnId": "turn-new-001",
                            "traceId": "trace-new-001",
                            "sessionId": "session-new-001",
                            "taskId": "task-new-001",
                            "stepId": "step-new-001",
                            "evidenceIds": ["evidence-new-001"],
                            "confidence": 0.95,
                            "timestamp": "2026-03-19T11:10:00Z",
                        }
                    ],
                    "riskLevel": "low",
                    "activationStatus": "active",
                    "teacherConfirmed": True,
                    "supersededByRuleId": None,
                    "lifecycleReason": None,
                    "createdAt": "2026-03-19T11:10:00Z",
                    "updatedAt": "2026-03-19T11:10:00Z",
                },
            )

            write_json(
                profiles_root / "profile-old-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
                    "profileVersion": "profile-old-001",
                    "profile": {
                        "schemaVersion": "openstaff.learning.preference-profile.v0",
                        "profileVersion": "profile-old-001",
                        "activeRuleIds": ["rule-old-001"],
                        "assistPreferences": [{"ruleId": "rule-old-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should keep responses concise.", "hint": "Keep Safari responses concise.", "proposedAction": "prefer_concise_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:00:00Z"}],
                        "skillPreferences": [{"ruleId": "rule-old-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should keep responses concise.", "hint": "Keep Safari responses concise.", "proposedAction": "prefer_concise_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:00:00Z"}],
                        "repairPreferences": [],
                        "reviewPreferences": [{"ruleId": "rule-old-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should keep responses concise.", "hint": "Keep Safari responses concise.", "proposedAction": "prefer_concise_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:00:00Z"}],
                        "plannerPreferences": [],
                        "generatedAt": "2026-03-19T11:05:00Z",
                    },
                    "sourceRuleIds": ["rule-old-001"],
                    "createdAt": "2026-03-19T11:05:00Z",
                    "previousProfileVersion": None,
                    "note": "Older concise Safari profile.",
                },
            )
            write_json(
                profiles_root / "profile-current-001.json",
                {
                    "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
                    "profileVersion": "profile-current-001",
                    "profile": {
                        "schemaVersion": "openstaff.learning.preference-profile.v0",
                        "profileVersion": "profile-current-001",
                        "activeRuleIds": ["rule-new-001"],
                        "assistPreferences": [{"ruleId": "rule-new-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should include a detailed appendix.", "hint": "Prefer detailed Safari answers with appendix.", "proposedAction": "prefer_detailed_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:10:00Z"}],
                        "skillPreferences": [{"ruleId": "rule-new-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should include a detailed appendix.", "hint": "Prefer detailed Safari answers with appendix.", "proposedAction": "prefer_detailed_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:10:00Z"}],
                        "repairPreferences": [],
                        "reviewPreferences": [{"ruleId": "rule-new-001", "type": "style", "scope": {"level": "app", "appBundleId": "com.apple.Safari", "appName": "Safari"}, "statement": "Safari tasks should include a detailed appendix.", "hint": "Prefer detailed Safari answers with appendix.", "proposedAction": "prefer_detailed_safari_copy", "teacherConfirmed": True, "updatedAt": "2026-03-19T11:10:00Z"}],
                        "plannerPreferences": [],
                        "generatedAt": "2026-03-19T11:30:00Z",
                    },
                    "sourceRuleIds": ["rule-new-001"],
                    "createdAt": "2026-03-19T11:30:00Z",
                    "previousProfileVersion": "profile-old-001",
                    "note": "Current detailed Safari profile.",
                },
            )
            write_json(
                profiles_root / "latest.json",
                {
                    "schemaVersion": "openstaff.learning.preference-profile-pointer.v0",
                    "profileVersion": "profile-current-001",
                    "updatedAt": "2026-03-19T11:30:00Z",
                },
            )

            preview = run_swift_target(
                "OpenStaffPreferenceProfileCLI",
                [
                    "--preferences-root",
                    str(preferences_root),
                    "--rollback-profile-version",
                    "profile-old-001",
                    "--profile-version",
                    "preview-profile-rollback-001",
                    "--timestamp",
                    "2026-03-19T12:00:00Z",
                    "--dry-run",
                    "--json",
                ],
            )

            self.assertEqual(preview.returncode, 0, msg=preview.stderr or preview.stdout)
            preview_payload = json.loads(preview.stdout)
            self.assertEqual(preview_payload["mode"], "rollback_preview")
            self.assertEqual(preview_payload["rollbackPlan"]["targetProfileVersion"], "profile-old-001")
            self.assertEqual(preview_payload["snapshot"]["profile"]["activeRuleIds"], ["rule-old-001"])
            latest_pointer = json.loads((profiles_root / "latest.json").read_text(encoding="utf-8"))
            self.assertEqual(latest_pointer["profileVersion"], "profile-current-001")

            applied = run_swift_target(
                "OpenStaffPreferenceProfileCLI",
                [
                    "--preferences-root",
                    str(preferences_root),
                    "--rollback-profile-version",
                    "profile-old-001",
                    "--profile-version",
                    "profile-restored-001",
                    "--timestamp",
                    "2026-03-19T12:00:00Z",
                    "--persist",
                    "--json",
                ],
            )

            self.assertEqual(applied.returncode, 0, msg=applied.stderr or applied.stdout)
            applied_payload = json.loads(applied.stdout)
            self.assertEqual(applied_payload["mode"], "rollback_applied")
            self.assertEqual(applied_payload["snapshot"]["profileVersion"], "profile-restored-001")
            self.assertEqual(applied_payload["snapshot"]["profile"]["activeRuleIds"], ["rule-old-001"])

            latest_pointer = json.loads((profiles_root / "latest.json").read_text(encoding="utf-8"))
            self.assertEqual(latest_pointer["profileVersion"], "profile-restored-001")
            old_rule = json.loads((rules_root / "rule-old-001.json").read_text(encoding="utf-8"))
            new_rule = json.loads((rules_root / "rule-new-001.json").read_text(encoding="utf-8"))
            self.assertEqual(old_rule["activationStatus"], "active")
            self.assertEqual(new_rule["activationStatus"], "revoked")

            audit_lines = [
                json.loads(line)
                for line in (preferences_root / "audit/2026-03-19.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertTrue(
                any(
                    entry["action"] == "rollbackApplied"
                    and entry["profileVersion"] == "profile-restored-001"
                    and entry["relatedProfileVersion"] == "profile-old-001"
                    for entry in audit_lines
                )
            )

    def test_cli_loads_filtered_audit_entries(self):
        with tempfile.TemporaryDirectory(prefix="openstaff-preference-audit-cli-") as tmp_dir:
            preferences_root = Path(tmp_dir) / "data/preferences"
            audit_root = preferences_root / "audit"

            write_jsonl(
                audit_root / "2026-03-19.jsonl",
                [
                    {
                        "schemaVersion": "openstaff.learning.preference-audit.v0",
                        "auditId": "audit-rule-old-001",
                        "action": "ruleRolledBack",
                        "timestamp": "2026-03-19T12:00:00Z",
                        "actor": "cli",
                        "source": {"kind": "rollbackService", "referenceId": "profile-old-001", "summary": "Restore old Safari style."},
                        "signalIds": [],
                        "ruleId": "rule-old-001",
                        "affectedRuleIds": ["rule-old-001"],
                        "profileVersion": "profile-restored-001",
                        "relatedProfileVersion": "profile-old-001",
                        "previousActivationStatus": "superseded",
                        "newActivationStatus": "active",
                        "relatedRuleId": None,
                        "note": "Restore old Safari style.",
                    },
                    {
                        "schemaVersion": "openstaff.learning.preference-audit.v0",
                        "auditId": "audit-rule-other-001",
                        "action": "ruleRevoked",
                        "timestamp": "2026-03-19T12:05:00Z",
                        "actor": "cli",
                        "source": {"kind": "rollbackService", "referenceId": "rule-other-001", "summary": "Remove other rule."},
                        "signalIds": [],
                        "ruleId": "rule-other-001",
                        "affectedRuleIds": ["rule-other-001"],
                        "profileVersion": None,
                        "relatedProfileVersion": None,
                        "previousActivationStatus": "active",
                        "newActivationStatus": "revoked",
                        "relatedRuleId": None,
                        "note": "Remove other rule.",
                    },
                ],
            )

            result = run_swift_target(
                "OpenStaffPreferenceProfileCLI",
                [
                    "--preferences-root",
                    str(preferences_root),
                    "--audit",
                    "--audit-rule-id",
                    "rule-old-001",
                    "--json",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["mode"], "audit_loaded")
            self.assertEqual(len(payload["auditEntries"]), 1)
            self.assertEqual(payload["auditEntries"][0]["action"], "ruleRolledBack")
            self.assertEqual(payload["auditEntries"][0]["ruleId"], "rule-old-001")


if __name__ == "__main__":
    unittest.main()
