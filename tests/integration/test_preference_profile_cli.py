import json
import tempfile
from pathlib import Path
import unittest

from tests.swift_cli_test_utils import run_swift_target


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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


if __name__ == "__main__":
    unittest.main()
