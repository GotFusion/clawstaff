#!/usr/bin/env python3
"""Export learning artifacts into a portable learning bundle."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import learning_bundle_common as bundle_common


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export OpenStaff learning artifacts into a bundle.")
    parser.add_argument(
        "--learning-root",
        type=Path,
        default=Path("data/learning"),
        help="Learning root directory. Default: data/learning",
    )
    parser.add_argument(
        "--preferences-root",
        type=Path,
        default=Path("data/preferences"),
        help="Preferences root directory. Default: data/preferences",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output bundle directory.",
    )
    parser.add_argument(
        "--bundle-id",
        help="Optional explicit bundle identifier.",
    )
    parser.add_argument(
        "--session-id",
        action="append",
        default=[],
        help="Optional session filter. May be specified multiple times.",
    )
    parser.add_argument(
        "--task-id",
        action="append",
        default=[],
        help="Optional task filter. May be specified multiple times.",
    )
    parser.add_argument(
        "--turn-id",
        action="append",
        default=[],
        help="Optional turn filter. May be specified multiple times.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite an existing output directory.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit structured JSON output.",
    )
    return parser.parse_args()


def print_summary(result: dict) -> None:
    print(f"bundlePath={result['bundlePath']}")
    print(f"bundleId={result['bundleId']}")
    for category, values in result["counts"].items():
        print(f"{category}: files={values['files']} records={values['records']}")
    print(f"verificationPassed={result['passed']}")


def main() -> int:
    args = parse_args()

    try:
        dataset = bundle_common.load_source_dataset(
            learning_root=args.learning_root.resolve(),
            preferences_root=args.preferences_root.resolve(),
        )
        result = bundle_common.export_bundle(
            dataset,
            args.output.resolve(),
            learning_root=args.learning_root.resolve(),
            preferences_root=args.preferences_root.resolve(),
            session_ids=args.session_id,
            task_ids=args.task_id,
            turn_ids=args.turn_id,
            bundle_id=args.bundle_id,
            overwrite=args.overwrite,
        )
    except Exception as exc:  # pragma: no cover - handled by integration tests
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
            print(f"Learning bundle export failed: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_summary(result)

    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
