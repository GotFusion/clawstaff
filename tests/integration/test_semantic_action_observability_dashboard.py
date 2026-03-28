from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts/observability/build_semantic_action_dashboard.py"

sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import (  # noqa: E402
    SemanticActionExecutionLogRecord,
    SemanticActionMigrationManager,
    SemanticActionRecord,
    SemanticActionRepository,
)


class SemanticActionObservabilityDashboardTests(unittest.TestCase):
    def build_fixture_db(self, db_path: Path) -> None:
        manager = SemanticActionMigrationManager(db_path)
        manager.migrate_up()
        repository = SemanticActionRepository(db_path)

        def add_action(
            *,
            action_id: str,
            action_type: str,
            execution_log_id: str,
            log_status: str,
            result_status: str,
            environment: str,
            error_code: str | None = None,
            matched_locator_type: str | None = None,
            selector_hit_path: list[str] | None = None,
            teacher_confirmation_status: str | None = None,
            context_guard_status: str | None = None,
            post_assertions_status: str | None = None,
        ) -> None:
            result = {
                "actionType": action_type,
                "dryRun": False,
                "environment": environment,
                "status": result_status,
                "summary": f"{action_type} {result_status}",
            }
            if error_code is not None:
                result["errorCode"] = error_code
            if matched_locator_type is not None:
                result["matchedLocatorType"] = matched_locator_type
            if teacher_confirmation_status is not None:
                result["teacherConfirmation"] = {"status": teacher_confirmation_status}
            if context_guard_status is not None:
                result["contextGuard"] = {"status": context_guard_status}
            if post_assertions_status is not None:
                result["postAssertions"] = {"status": post_assertions_status}

            repository.replace_action(
                SemanticActionRecord(
                    action_id=action_id,
                    session_id=f"session-{environment}",
                    task_id=f"task-{environment}",
                    trace_id=f"trace-{action_id}",
                    step_id=f"step-{action_id}",
                    action_type=action_type,
                    selector={
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                    },
                    args={},
                    context={},
                    confidence=0.92,
                    created_at="2026-03-28T16:00:00Z",
                    updated_at="2026-03-28T16:00:00Z",
                    preferred_locator_type="roleAndTitle",
                ),
                execution_logs=[
                    SemanticActionExecutionLogRecord(
                        execution_log_id=execution_log_id,
                        status=log_status,
                        executed_at="2026-03-28T16:01:00Z",
                        selector_hit_path=selector_hit_path or [],
                        result=result,
                        trace_id=f"trace-{action_id}",
                        component="semantic.executor.cli",
                        error_code=error_code,
                        duration_ms=25,
                    )
                ],
            )

        add_action(
            action_id="action-dev-hit-001",
            action_type="click",
            execution_log_id="log-dev-hit-001",
            log_status="STATUS_SEMANTIC_ACTION_SUCCEEDED",
            result_status="succeeded",
            environment="dev",
            matched_locator_type="roleAndTitle",
            selector_hit_path=["axPath", "roleAndTitle"],
        )
        add_action(
            action_id="action-dev-miss-001",
            action_type="click",
            execution_log_id="log-dev-miss-001",
            log_status="STATUS_SEMANTIC_ACTION_FAILED",
            result_status="failed",
            environment="dev",
            error_code="SEM201-TARGET-UNRESOLVED",
            selector_hit_path=["axPath", "roleAndTitle", "textAnchor"],
        )
        add_action(
            action_id="action-dev-context-001",
            action_type="drag",
            execution_log_id="log-dev-context-001",
            log_status="STATUS_SEMANTIC_ACTION_BLOCKED",
            result_status="blocked",
            environment="dev",
            error_code="SEM202-CONTEXT-MISMATCH",
            context_guard_status="blocked",
        )
        add_action(
            action_id="action-staging-switch-001",
            action_type="switch_app",
            execution_log_id="log-staging-switch-001",
            log_status="STATUS_SEMANTIC_ACTION_SUCCEEDED",
            result_status="succeeded",
            environment="staging",
            matched_locator_type="app_context",
            selector_hit_path=["app_context"],
        )
        add_action(
            action_id="action-staging-confirm-001",
            action_type="click",
            execution_log_id="log-staging-confirm-001",
            log_status="STATUS_SEMANTIC_ACTION_BLOCKED",
            result_status="blocked",
            environment="staging",
            error_code="SEM302-TEACHER-CONFIRMATION-REQUIRED",
            teacher_confirmation_status="required",
        )
        add_action(
            action_id="action-prod-assert-001",
            action_type="click",
            execution_log_id="log-prod-assert-001",
            log_status="STATUS_SEMANTIC_ACTION_FAILED",
            result_status="failed",
            environment="prod",
            error_code="SEM203-ASSERTION-FAILED",
            matched_locator_type="roleAndTitle",
            selector_hit_path=["roleAndTitle"],
            post_assertions_status="failed",
        )

    def write_config(
        self,
        path: Path,
        *,
        selector_minimum: float,
        replay_minimum: float,
        manual_confirmation_maximum: float,
        risk_maximum: int,
    ) -> None:
        payload = {
            "configId": "semantic-action-observability-test",
            "defaultEnvironment": "dev",
            "expectedEnvironments": ["dev", "staging", "prod"],
            "gates": {
                "selectorHitRate": {"type": "minimum", "value": selector_minimum},
                "replaySuccessRate": {"type": "minimum", "value": replay_minimum},
                "manualConfirmationRate": {
                    "type": "maximum",
                    "value": manual_confirmation_maximum,
                },
                "misTriggerRiskEventCount": {"type": "maximum", "value": risk_maximum},
            },
            "perEnvironmentGates": {
                "selectorHitRate": {"type": "minimum", "value": selector_minimum},
                "replaySuccessRate": {"type": "minimum", "value": replay_minimum},
                "manualConfirmationRate": {
                    "type": "maximum",
                    "value": manual_confirmation_maximum,
                },
                "misTriggerRiskEventCount": {"type": "maximum", "value": risk_maximum},
            },
        }
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def run_cmd(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_dashboard_aggregates_metrics_by_environment_and_writes_markdown(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            db_path = tmp_root / "semantic-actions.sqlite"
            config_path = tmp_root / "metrics.json"
            output_path = tmp_root / "metrics-summary.json"
            dashboard_path = tmp_root / "dashboard.md"

            self.build_fixture_db(db_path)
            self.write_config(
                config_path,
                selector_minimum=0.5,
                replay_minimum=0.0,
                manual_confirmation_maximum=0.5,
                risk_maximum=10,
            )

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--db-path",
                    str(db_path),
                    "--config",
                    str(config_path),
                    "--output",
                    str(output_path),
                    "--dashboard-output",
                    str(dashboard_path),
                    "--json",
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(output_path.exists())
            self.assertTrue(dashboard_path.exists())

            summary = json.loads(result.stdout)
            self.assertEqual(summary["totalExecutionLogs"], 6)
            self.assertTrue(summary["gates"]["passed"])
            self.assertEqual(summary["metrics"]["selectorHitRate"]["value"], 0.75)
            self.assertEqual(
                summary["metrics"]["fallbackLayerDistribution"]["counts"],
                {"app_context": 1, "roleAndTitle": 2},
            )
            self.assertEqual(summary["metrics"]["interceptRate"]["value"], 0.3333)
            self.assertEqual(summary["metrics"]["replaySuccessRate"]["value"], 0.3333)
            self.assertEqual(summary["metrics"]["manualConfirmationRate"]["value"], 0.1667)
            self.assertEqual(summary["metrics"]["misTriggerRiskEventCount"]["value"], 2)

            self.assertEqual(summary["environments"]["dev"]["executionLogCount"], 3)
            self.assertEqual(
                summary["environments"]["dev"]["metrics"]["selectorHitRate"]["value"],
                0.5,
            )
            self.assertEqual(
                summary["environments"]["staging"]["metrics"]["manualConfirmationRate"]["value"],
                0.5,
            )
            self.assertEqual(
                summary["environments"]["prod"]["metrics"]["misTriggerRiskEventCount"]["value"],
                1,
            )

            dashboard = dashboard_path.read_text(encoding="utf-8")
            self.assertIn("| dev | 3 | 0.5000 | roleAndTitle=1 | 0.3333 | 0.3333 | 0.0000 | 1 |", dashboard)
            self.assertIn("`dev` `contextMismatchCount`", dashboard)
            self.assertIn("`prod` `postAssertionFailureCount`", dashboard)

    def test_dashboard_check_gates_fails_when_mis_trigger_risk_exists(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            db_path = tmp_root / "semantic-actions.sqlite"
            config_path = tmp_root / "metrics-strict.json"
            output_path = tmp_root / "metrics-summary.json"
            dashboard_path = tmp_root / "dashboard.md"

            self.build_fixture_db(db_path)
            self.write_config(
                config_path,
                selector_minimum=0.75,
                replay_minimum=0.2,
                manual_confirmation_maximum=0.5,
                risk_maximum=0,
            )

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--db-path",
                    str(db_path),
                    "--config",
                    str(config_path),
                    "--output",
                    str(output_path),
                    "--dashboard-output",
                    str(dashboard_path),
                    "--check-gates",
                    "--json",
                ]
            )

            self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            self.assertFalse(summary["gates"]["passed"])
            self.assertEqual(summary["metrics"]["misTriggerRiskEventCount"]["value"], 2)
            self.assertTrue(
                any(
                    alert["metric"] == "misTriggerRiskEventCount"
                    and alert["environment"] == "overall"
                    for alert in summary["alerts"]
                )
            )


if __name__ == "__main__":
    unittest.main()
