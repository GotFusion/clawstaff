#!/usr/bin/env python3
"""
SEM-003 static guard: block new coordinate execution call sites from re-entering main.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCAN_ROOTS = ("apps", "core", "scripts", "tests", ".github")
SCANNED_SUFFIXES = {
    ".bash",
    ".js",
    ".jsx",
    ".kts",
    ".kt",
    ".m",
    ".mm",
    ".py",
    ".rb",
    ".sh",
    ".swift",
    ".ts",
    ".tsx",
    ".zsh",
}
SKIPPED_DIR_NAMES = {
    ".build",
    ".git",
    ".pytest_cache",
    ".venv",
    "__pycache__",
    "node_modules",
    "venv",
}
SKIPPED_PATH_PREFIXES = (
    Path("apps/Build"),
    Path("data"),
    Path("docs"),
    Path("vendors"),
)


@dataclass(frozen=True)
class GuardRule:
    rule_id: str
    description: str
    pattern: re.Pattern[str]
    allowlisted_counts: dict[str, int]


@dataclass(frozen=True)
class Violation:
    ruleId: str
    file: str
    line: int
    column: int
    excerpt: str
    description: str


RULES = (
    GuardRule(
        rule_id="SEM003-LOWLEVEL-COORDINATE-MOUSE-EVENT",
        description="Low-level mouse event synthesis with explicit coordinates is frozen by SEM-001.",
        pattern=re.compile(r"\bmouseCursorPosition\s*:"),
        allowlisted_counts={
            "apps/macos/Sources/OpenStaffApp/OpenStaffActionExecutor.swift": 2,
            "apps/macos/Sources/OpenStaffExecutorHelper/OpenStaffExecutorHelper.swift": 2,
        },
    ),
    GuardRule(
        rule_id="SEM003-LEGACY-APP-EXECUTOR-CALL",
        description="OpenStaffActionExecutor is a frozen legacy coordinate execution bridge.",
        pattern=re.compile(r"\bOpenStaffActionExecutor\.executeAction\s*\("),
        allowlisted_counts={
            "apps/macos/Sources/OpenStaffApp/OpenStaffApp.swift": 1,
        },
    ),
    GuardRule(
        rule_id="SEM003-LEGACY-HELPER-EXECUTOR-CALL",
        description="OpenStaffExecutorXPCClient executeAction is a frozen legacy coordinate execution bridge.",
        pattern=re.compile(r"\bOpenStaffExecutorXPCClient\.shared\.executeAction\s*\("),
        allowlisted_counts={
            "apps/macos/Sources/OpenStaffApp/OpenStaffActionExecutor.swift": 1,
        },
    ),
    GuardRule(
        rule_id="SEM003-GENERIC-EXECUTE-CLICK",
        description="Generic coordinate click helpers that take explicit x/y coordinates are forbidden.",
        pattern=re.compile(r"\bexecute_click\s*\("),
        allowlisted_counts={},
    ),
    GuardRule(
        rule_id="SEM003-GENERIC-CLICK-AT",
        description="Generic click-at style coordinate helpers are forbidden.",
        pattern=re.compile(r"\bclick_at\s*\("),
        allowlisted_counts={},
    ),
    GuardRule(
        rule_id="SEM003-CGWARP-MOUSE",
        description="CGWarpMouseCursorPosition reintroduces coordinate-only execution.",
        pattern=re.compile(r"\bCGWarpMouseCursorPosition\s*\("),
        allowlisted_counts={},
    ),
    GuardRule(
        rule_id="SEM003-CGEVENT-CREATE-MOUSE",
        description="CGEventCreateMouseEvent reintroduces coordinate-only execution.",
        pattern=re.compile(r"\bCGEventCreateMouseEvent\s*\("),
        allowlisted_counts={},
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Guard the repo against new coordinate execution call sites.")
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help=f"Repository root to scan (default: {REPO_ROOT}).",
    )
    parser.add_argument(
        "--allow-dir",
        action="append",
        default=[],
        help="Relative or absolute directory to skip, useful for test fixtures.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the full report as JSON.",
    )
    return parser.parse_args()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def is_relative_to(path: Path, base: Path) -> bool:
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False


def normalize_allow_dirs(root: Path, allow_dirs: list[str | Path]) -> set[Path]:
    normalized: set[Path] = set()
    for allow_dir in allow_dirs:
        candidate = Path(allow_dir)
        if not candidate.is_absolute():
            candidate = root / candidate
        normalized.add(candidate.resolve())
    return normalized


def should_skip_dir(root: Path, directory: Path, allow_dirs: set[Path]) -> bool:
    resolved = directory.resolve()
    if any(is_relative_to(resolved, allow_dir) for allow_dir in allow_dirs):
        return True
    rel_path = resolved.relative_to(root)
    if any(part in SKIPPED_DIR_NAMES for part in rel_path.parts):
        return True
    return any(is_relative_to(rel_path, prefix) for prefix in SKIPPED_PATH_PREFIXES)


def should_scan_file(root: Path, file_path: Path, allow_dirs: set[Path]) -> bool:
    resolved = file_path.resolve()
    if any(is_relative_to(resolved, allow_dir) for allow_dir in allow_dirs):
        return False
    rel_path = resolved.relative_to(root)
    if any(part in SKIPPED_DIR_NAMES for part in rel_path.parts):
        return False
    if any(is_relative_to(rel_path, prefix) for prefix in SKIPPED_PATH_PREFIXES):
        return False
    return rel_path.suffix in SCANNED_SUFFIXES


def iter_source_files(root: Path, allow_dirs: set[Path]) -> list[Path]:
    files: list[Path] = []
    for scan_root_name in SCAN_ROOTS:
        scan_root = root / scan_root_name
        if not scan_root.exists():
            continue
        for current_dir, dirnames, filenames in os.walk(scan_root):
            current_path = Path(current_dir)
            dirnames[:] = [
                dirname
                for dirname in dirnames
                if not should_skip_dir(root, current_path / dirname, allow_dirs)
            ]
            for filename in filenames:
                file_path = current_path / filename
                if should_scan_file(root, file_path, allow_dirs):
                    files.append(file_path)
    return sorted(files)


def build_report(root: Path, *, allow_dirs: list[str | Path] | None = None) -> dict:
    resolved_root = root.resolve()
    normalized_allow_dirs = normalize_allow_dirs(resolved_root, allow_dirs or [])
    violations: list[Violation] = []
    scanned_files = iter_source_files(resolved_root, normalized_allow_dirs)

    for file_path in scanned_files:
        relative_path = file_path.resolve().relative_to(resolved_root).as_posix()
        content = file_path.read_text(encoding="utf-8", errors="ignore")
        lines = content.splitlines()

        for rule in RULES:
            matches = list(rule.pattern.finditer(content))
            allowed_count = rule.allowlisted_counts.get(relative_path, 0)
            for match in matches[allowed_count:]:
                line = content.count("\n", 0, match.start()) + 1
                line_start = content.rfind("\n", 0, match.start())
                column = match.start() - line_start
                excerpt = lines[line - 1].strip() if 0 <= line - 1 < len(lines) else match.group(0)
                violations.append(
                    Violation(
                        ruleId=rule.rule_id,
                        file=relative_path,
                        line=line,
                        column=column,
                        excerpt=excerpt,
                        description=rule.description,
                    )
                )

    report = {
        "schemaVersion": "openstaff.coordinate-execution-guard-report.v0",
        "generatedAt": utc_now_iso(),
        "root": str(resolved_root),
        "passed": len(violations) == 0,
        "scannedFileCount": len(scanned_files),
        "violationCount": len(violations),
        "allowDirs": [str(path) for path in sorted(normalized_allow_dirs)],
        "violations": [asdict(item) for item in violations],
    }
    return report


def print_human_report(report: dict) -> None:
    if report["passed"]:
        print(
            "PASS: coordinate execution guard found no new call sites "
            f"(scanned {report['scannedFileCount']} files)."
        )
        return

    print(
        "FAIL: coordinate execution guard found forbidden call sites "
        f"({report['violationCount']} violations across {report['scannedFileCount']} files)."
    )
    for violation in report["violations"]:
        print(
            f"- {violation['ruleId']} {violation['file']}:{violation['line']}:{violation['column']} "
            f"{violation['excerpt']}"
        )


def main() -> int:
    args = parse_args()
    report = build_report(args.root, allow_dirs=args.allow_dir)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_human_report(report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
