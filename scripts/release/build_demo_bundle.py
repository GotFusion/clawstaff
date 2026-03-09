#!/usr/bin/env python3
"""
Build a release demo bundle from repository fixtures (TODO 6.3).
"""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = Path("/tmp/openstaff-release-demo")

FILE_MAPPINGS = [
    ("core/capture/examples/raw-events.sample.jsonl", "samples/capture/raw-events.sample.jsonl"),
    ("core/capture/examples/normalized-events.sample.jsonl", "samples/capture/normalized-events.sample.jsonl"),
    ("core/knowledge/examples/knowledge-item.sample.json", "samples/knowledge/knowledge-item.sample.json"),
    ("scripts/llm/examples/knowledge-parse-output.sample.json", "samples/llm/knowledge-parse-output.sample.json"),
    ("scripts/skills/examples/knowledge-item.sample.finder.json", "samples/skills/knowledge-item.sample.finder.json"),
    ("scripts/skills/examples/knowledge-item.sample.terminal.json", "samples/skills/knowledge-item.sample.terminal.json"),
    ("scripts/skills/examples/llm-output.sample.finder.json", "samples/skills/llm-output.sample.finder.json"),
    ("scripts/skills/examples/llm-output.sample.terminal-invalid.txt", "samples/skills/llm-output.sample.terminal-invalid.txt"),
]

DIR_MAPPINGS = [
    ("scripts/skills/examples/generated", "samples/skills/generated"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build OpenStaff release demo bundle.")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUT_DIR}).",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite output directory if it already exists.",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def copy_file(src_rel: str, dst_rel: str, out_dir: Path) -> str:
    src = REPO_ROOT / src_rel
    dst = out_dir / dst_rel
    if not src.exists() or not src.is_file():
        raise FileNotFoundError(f"Missing fixture file: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst_rel


def copy_directory(src_rel: str, dst_rel: str, out_dir: Path) -> str:
    src = REPO_ROOT / src_rel
    dst = out_dir / dst_rel
    if not src.exists() or not src.is_dir():
        raise FileNotFoundError(f"Missing fixture directory: {src}")
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst)
    return dst_rel


def build_readme(out_dir: Path) -> None:
    content = """# OpenStaff Release Demo Bundle

本目录由 `scripts/release/build_demo_bundle.py` 生成，用于发布前演示与回归基线。

## 内容
- `samples/capture/`: 采集阶段样例（raw/normalized）。
- `samples/knowledge/`: KnowledgeItem 样例。
- `samples/llm/`: LLM 结构化输出样例。
- `samples/skills/`: skill 输入样例与已生成 skill 样例。
- `manifest.json`: 生成时间、来源与清单摘要。

## 推荐配合命令
1. `python3 scripts/release/run_regression.py --suite all`
2. `make release-preflight`
"""
    (out_dir / "README.md").write_text(content, encoding="utf-8")


def main() -> int:
    args = parse_args()
    out_dir: Path = args.out_dir.resolve()

    if out_dir.exists():
        if not args.overwrite:
            raise SystemExit(
                f"Output directory already exists: {out_dir} (use --overwrite to replace)."
            )
        shutil.rmtree(out_dir)

    out_dir.mkdir(parents=True, exist_ok=True)

    copied_files: list[str] = []
    copied_dirs: list[str] = []

    for src_rel, dst_rel in FILE_MAPPINGS:
        copied_files.append(copy_file(src_rel, dst_rel, out_dir))

    for src_rel, dst_rel in DIR_MAPPINGS:
        copied_dirs.append(copy_directory(src_rel, dst_rel, out_dir))

    build_readme(out_dir)

    manifest = {
        "schemaVersion": "openstaff.release-demo-bundle.v0",
        "generatedAt": now_iso(),
        "sourceRepoRoot": str(REPO_ROOT),
        "outputDirectory": str(out_dir),
        "files": copied_files,
        "directories": copied_dirs,
        "fileCount": len(copied_files),
        "directoryCount": len(copied_dirs),
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"SUCCESS: release demo bundle created at {out_dir}")
    print(f"Manifest: {manifest_path}")
    print(f"Included files={len(copied_files)} directories={len(copied_dirs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
