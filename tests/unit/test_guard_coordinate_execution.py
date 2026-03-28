import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
GUARD_PATH = REPO_ROOT / "scripts/validation/guard_coordinate_execution.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def source_literal(*parts: str) -> str:
    return "".join(parts)


class GuardCoordinateExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.guard = load_module("guard_coordinate_execution", GUARD_PATH)

    def test_build_report_fails_when_legacy_bridge_paths_exist(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            write_file(
                root / "apps/macos/Sources/OpenStaffApp/OpenStaffActionExecutor.swift",
                "\n".join(
                    [
                        source_literal("OpenStaffExecutorXPCClient.shared.", "executeAction("),
                        source_literal("mouseCursor", "Position: coordinate"),
                        source_literal("mouseCursor", "Position: coordinate"),
                    ]
                ),
            )
            write_file(
                root / "apps/macos/Sources/OpenStaffExecutorHelper/OpenStaffExecutorHelper.swift",
                "\n".join(
                    [
                        source_literal("mouseCursor", "Position: coordinate"),
                        source_literal("mouseCursor", "Position: coordinate"),
                    ]
                ),
            )
            write_file(
                root / "apps/macos/Sources/OpenStaffApp/OpenStaffApp.swift",
                source_literal("OpenStaffAction", "Executor.executeAction(\n"),
            )

            report = self.guard.build_report(root)

            self.assertFalse(report["passed"])
            self.assertEqual(report["violationCount"], 6)
            self.assertEqual(
                {item["ruleId"] for item in report["violations"]},
                {
                    "SEM003-LOWLEVEL-COORDINATE-MOUSE-EVENT",
                    "SEM003-LEGACY-APP-EXECUTOR-CALL",
                    "SEM003-LEGACY-HELPER-EXECUTOR-CALL",
                },
            )

    def test_build_report_fails_when_new_legacy_executor_call_is_added(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            write_file(
                root / "apps/macos/Sources/Feature/NewFlow.swift",
                source_literal("let result = OpenStaffAction", "Executor.executeAction(\n"),
            )

            report = self.guard.build_report(root)

            self.assertFalse(report["passed"])
            self.assertEqual(report["violationCount"], 1)
            self.assertEqual(report["violations"][0]["ruleId"], "SEM003-LEGACY-APP-EXECUTOR-CALL")

    def test_build_report_fails_when_low_level_coordinate_mouse_event_is_added(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            write_file(
                root / "apps/macos/Sources/Feature/NewFlow.swift",
                source_literal("let down = CGEvent(mouseCursor", "Position: coordinate, mouseButton: .left)\n"),
            )

            report = self.guard.build_report(root)

            self.assertFalse(report["passed"])
            self.assertEqual(report["violationCount"], 1)
            self.assertEqual(report["violations"][0]["ruleId"], "SEM003-LOWLEVEL-COORDINATE-MOUSE-EVENT")

    def test_allow_dir_skips_fixture_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            write_file(
                root / "tests/fixtures/coordinate_guard/fixture.py",
                "execute_" "click(10, 20)\n",
            )

            blocked_report = self.guard.build_report(root)
            allowed_report = self.guard.build_report(root, allow_dirs=["tests/fixtures"])

            self.assertFalse(blocked_report["passed"])
            self.assertTrue(allowed_report["passed"])

    def test_cli_returns_nonzero_for_violation(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            write_file(
                root / "scripts/demo.py",
                "click_" "at(100, 200)\n",
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    str(GUARD_PATH),
                    "--root",
                    str(root),
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 1)
            self.assertIn("FAIL: coordinate execution guard found forbidden call sites", completed.stdout)


if __name__ == "__main__":
    unittest.main()
