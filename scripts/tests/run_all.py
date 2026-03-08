#!/usr/bin/env python3
"""
Unified test runner for TODO 6.2.
"""

from __future__ import annotations

import argparse
import unittest
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TEST_GROUPS = {
    "unit": REPO_ROOT / "tests/unit",
    "integration": REPO_ROOT / "tests/integration",
    "e2e": REPO_ROOT / "tests/e2e",
}


@dataclass
class SuiteResult:
    name: str
    tests_run: int
    failures: int
    errors: int
    skipped: int

    @property
    def passed(self) -> bool:
        return self.failures == 0 and self.errors == 0


def discover_suite(path: Path) -> unittest.TestSuite:
    return unittest.defaultTestLoader.discover(
        start_dir=str(path),
        pattern="test_*.py",
        top_level_dir=str(REPO_ROOT),
    )


def run_suite(name: str, path: Path, verbosity: int) -> SuiteResult:
    suite = discover_suite(path)
    runner = unittest.TextTestRunner(verbosity=verbosity)
    result = runner.run(suite)

    return SuiteResult(
        name=name,
        tests_run=result.testsRun,
        failures=len(result.failures),
        errors=len(result.errors),
        skipped=len(result.skipped),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run OpenStaff unit/integration/e2e tests.")
    parser.add_argument(
        "--suite",
        choices=["all", "unit", "integration", "e2e"],
        default="all",
        help="Which suite to run.",
    )
    parser.add_argument("--verbosity", type=int, default=2, help="unittest verbosity (default: 2).")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    groups = [args.suite] if args.suite != "all" else ["unit", "integration", "e2e"]

    summary: list[SuiteResult] = []
    for group in groups:
        summary.append(run_suite(group, TEST_GROUPS[group], args.verbosity))

    total_run = sum(item.tests_run for item in summary)
    total_failures = sum(item.failures for item in summary)
    total_errors = sum(item.errors for item in summary)
    total_skipped = sum(item.skipped for item in summary)

    print("\n=== OpenStaff Test Summary ===")
    for item in summary:
        status = "PASS" if item.passed else "FAIL"
        print(
            f"[{status}] {item.name}: run={item.tests_run} "
            f"failures={item.failures} errors={item.errors} skipped={item.skipped}"
        )

    print(
        "TOTAL: "
        f"run={total_run} failures={total_failures} errors={total_errors} skipped={total_skipped}"
    )

    return 0 if (total_failures == 0 and total_errors == 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
