#!/usr/bin/env python3
"""Verify and restore OpenStaff learning bundles."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import learning_bundle_common as bundle_common


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify or restore an OpenStaff learning bundle.")
    parser.add_argument(
        "--bundle",
        type=Path,
        required=True,
        help="Bundle directory to verify.",
    )
    parser.add_argument(
        "--restore-workspace-root",
        type=Path,
        help="Optional workspace root to preview or apply restore into.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply the restore after successful verification and preview.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow restore to overwrite existing target files.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit structured JSON output.",
    )
    return parser.parse_args()


def print_summary(result: dict) -> None:
    print(f"bundlePath={result['verification']['bundlePath']}")
    print(f"verificationPassed={result['verification']['passed']}")
    for category, values in result["verification"]["counts"].items():
        print(f"{category}: files={values['files']} records={values['records']}")

    restore_preview = result.get("restorePreview")
    if restore_preview:
        print(f"restoreWorkspaceRoot={restore_preview['workspaceRoot']}")
        print(f"restoreReady={restore_preview['restoreReady']}")
        print(f"restoreConflicts={restore_preview['conflictCount']}")

    restore_result = result.get("restoreResult")
    if restore_result:
        print(f"restoreApplied={restore_result['applied']}")
        print(f"writtenFileCount={restore_result['writtenFileCount']}")


def main() -> int:
    args = parse_args()

    try:
        verification = bundle_common.verify_bundle(args.bundle.resolve())
    except Exception as exc:  # pragma: no cover - exercised by integration tests
        if args.json:
            print(
                json.dumps(
                    {
                        "passed": False,
                        "error": str(exc),
                    },
                    ensure_ascii=False,
                    indent=2,
                    sort_keys=True,
                )
            )
        else:
            print(f"Learning bundle verification failed: {exc}", file=sys.stderr)
        return 1

    result: dict[str, object] = {
        "passed": verification["passed"],
        "verification": verification,
    }

    exit_code = 0 if verification["passed"] else 1

    if args.restore_workspace_root is not None:
        try:
            preview = bundle_common.preview_restore(
                args.bundle.resolve(),
                args.restore_workspace_root.resolve(),
                overwrite=args.overwrite,
            )
        except Exception as exc:  # pragma: no cover - exercised by integration tests
            result["restorePreview"] = {
                "restoreReady": False,
                "error": str(exc),
            }
            exit_code = 1
        else:
            result["restorePreview"] = preview
            if args.apply:
                if not verification["passed"] or not preview["restoreReady"]:
                    exit_code = 1
                else:
                    try:
                        restore_result = bundle_common.apply_restore(
                            args.bundle.resolve(),
                            args.restore_workspace_root.resolve(),
                            overwrite=args.overwrite,
                        )
                    except Exception as exc:  # pragma: no cover - exercised by integration tests
                        result["restoreError"] = str(exc)
                        exit_code = 1
                    else:
                        result["restoreResult"] = restore_result
            elif not preview["restoreReady"]:
                result["restorePreview"]["blocked"] = True

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_summary(result)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
