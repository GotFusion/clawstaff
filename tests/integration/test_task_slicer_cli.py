import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import run_swift_target


class TaskSlicerCLITests(unittest.TestCase):
    def write_raw_events(
        self,
        raw_root: Path,
        date_key: str,
        session_id: str,
    ) -> None:
        date_dir = raw_root / date_key
        date_dir.mkdir(parents=True, exist_ok=True)
        raw_file = date_dir / f"{session_id}.jsonl"

        events = [
            self.raw_event(
                event_id="11111111-1111-4111-8111-111111111111",
                session_id=session_id,
                timestamp="2026-03-09T10:00:00+08:00",
                app_name="Safari",
                app_bundle_id="com.apple.Safari",
                window_id="1001",
                x=200,
                y=300,
            ),
            self.raw_event(
                event_id="22222222-2222-4222-8222-222222222222",
                session_id=session_id,
                timestamp="2026-03-09T10:00:02+08:00",
                app_name="Safari",
                app_bundle_id="com.apple.Safari",
                window_id="1001",
                x=220,
                y=320,
            ),
            self.raw_event(
                event_id="33333333-3333-4333-8333-333333333333",
                session_id=session_id,
                timestamp="2026-03-09T10:00:45+08:00",
                app_name="Safari",
                app_bundle_id="com.apple.Safari",
                window_id="1001",
                x=240,
                y=340,
            ),
            self.raw_event(
                event_id="44444444-4444-4444-8444-444444444444",
                session_id=session_id,
                timestamp="2026-03-09T10:00:47+08:00",
                app_name="Finder",
                app_bundle_id="com.apple.finder",
                window_id="2001",
                x=260,
                y=360,
            ),
        ]

        with raw_file.open("w", encoding="utf-8") as f:
            for event in events:
                f.write(json.dumps(event, ensure_ascii=False))
                f.write("\n")

    def raw_event(
        self,
        event_id: str,
        session_id: str,
        timestamp: str,
        app_name: str,
        app_bundle_id: str,
        window_id: str,
        x: int,
        y: int,
    ) -> dict:
        return {
            "schemaVersion": "capture.raw.v0",
            "eventId": event_id,
            "sessionId": session_id,
            "timestamp": timestamp,
            "source": "mouse",
            "action": "leftClick",
            "pointer": {"x": x, "y": y, "coordinateSpace": "screen"},
            "contextSnapshot": {
                "appName": app_name,
                "appBundleId": app_bundle_id,
                "windowTitle": f"{app_name} Window",
                "windowId": window_id,
                "isFrontmost": True,
            },
            "modifiers": [],
        }

    def run_slicer(
        self,
        raw_root: Path,
        task_chunk_root: Path,
        date_key: str,
        session_id: str,
        disable_context_switch_split: bool = False,
    ) -> tuple[list[dict], str]:
        args = [
            "--session-id",
            session_id,
            "--date",
            date_key,
            "--raw-root",
            str(raw_root),
            "--task-chunk-root",
            str(task_chunk_root),
            "--idle-gap-seconds",
            "20",
            "--json",
        ]
        if disable_context_switch_split:
            args.append("--disable-context-switch-split")

        result = run_swift_target("OpenStaffTaskSlicerCLI", args)
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

        chunks: list[dict] = []
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line.startswith("{") or not line.endswith("}"):
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if payload.get("schemaVersion") == "knowledge.task-chunk.v0":
                chunks.append(payload)

        return chunks, result.stdout

    def test_slice_splits_by_idle_gap_and_context_switch(self):
        session_id = "session-20260309-t1"
        date_key = "2026-03-09"
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            raw_root = root / "raw-events"
            task_chunk_root = root / "task-chunks"
            self.write_raw_events(raw_root, date_key, session_id)

            chunks, _ = self.run_slicer(
                raw_root=raw_root,
                task_chunk_root=task_chunk_root,
                date_key=date_key,
                session_id=session_id,
            )

            self.assertEqual(len(chunks), 3)
            self.assertEqual([c["boundaryReason"] for c in chunks], ["idleGap", "contextSwitch", "sessionEnd"])
            self.assertEqual([c["eventCount"] for c in chunks], [2, 1, 1])

            output_dir = task_chunk_root / date_key
            self.assertTrue((output_dir / f"task-{session_id}-001.json").exists())
            self.assertTrue((output_dir / f"task-{session_id}-002.json").exists())
            self.assertTrue((output_dir / f"task-{session_id}-003.json").exists())

    def test_slice_can_disable_context_switch_split(self):
        session_id = "session-20260309-t2"
        date_key = "2026-03-09"
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            raw_root = root / "raw-events"
            task_chunk_root = root / "task-chunks"
            self.write_raw_events(raw_root, date_key, session_id)

            chunks, _ = self.run_slicer(
                raw_root=raw_root,
                task_chunk_root=task_chunk_root,
                date_key=date_key,
                session_id=session_id,
                disable_context_switch_split=True,
            )

            self.assertEqual(len(chunks), 2)
            self.assertEqual([c["boundaryReason"] for c in chunks], ["idleGap", "sessionEnd"])
            self.assertEqual([c["eventCount"] for c in chunks], [2, 2])


if __name__ == "__main__":
    unittest.main()
