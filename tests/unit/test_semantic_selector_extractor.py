from __future__ import annotations

from pathlib import Path
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_selector_extractor import build_accessibility_selector_chain  # noqa: E402


def raw_event(*, pointer=(0, 0), context_snapshot: dict | None = None) -> dict:
    return {
        "schemaVersion": "capture.raw.v0",
        "eventId": "event-001",
        "sessionId": "session-001",
        "timestamp": "2026-04-07T10:00:00Z",
        "source": "mouse",
        "action": "leftClick",
        "pointer": {
            "x": pointer[0],
            "y": pointer[1],
            "coordinateSpace": "screen",
        },
        "contextSnapshot": context_snapshot or {},
        "modifiers": [],
    }


class SemanticSelectorExtractorTests(unittest.TestCase):
    def test_extractor_prefers_identifier_title_path_then_bounds(self):
        event = raw_event(
            pointer=(842, 516),
            context_snapshot={
                "appBundleId": "com.apple.Safari",
                "appName": "Safari",
                "windowTitle": "OpenStaff - GitHub",
                "windowSignature": {
                    "signature": "window-github-001",
                    "signatureVersion": "window-v1",
                    "role": "AXWindow",
                    "subrole": "AXStandardWindow",
                },
                "windowFrame": {
                    "x": 200,
                    "y": 100,
                    "width": 1200,
                    "height": 800,
                    "coordinateSpace": "screen",
                },
                "url": "https://github.com/GotFusion/clawstaff/pulls",
                "focusedElement": {
                    "role": "AXButton",
                    "title": "Pull requests",
                    "identifier": "unified-tab-bar.pull-requests",
                    "ancestryPath": ["AXWindow", "AXToolbar", "AXButton"],
                    "boundingRect": {
                        "x": 820,
                        "y": 498,
                        "width": 110,
                        "height": 36,
                        "coordinateSpace": "screen",
                    },
                    "valueRedacted": False,
                },
            },
        )

        selectors = build_accessibility_selector_chain(event)

        self.assertEqual(
            [selector["selectorStrategy"] for selector in selectors],
            [
                "automation_id",
                "role_and_name",
                "role_and_ancestry_path",
                "bounds_norm",
                "absolute_coordinate",
            ],
        )
        self.assertEqual(selectors[0]["locatorType"], "roleAndTitle")
        self.assertEqual(selectors[0]["elementIdentifier"], "unified-tab-bar.pull-requests")
        self.assertEqual(selectors[0]["urlHost"], "github.com")
        self.assertEqual(selectors[2]["locatorType"], "axPath")
        self.assertEqual(selectors[2]["axPath"], "AXWindow/AXToolbar/AXButton")
        self.assertEqual(selectors[3]["boundsNorm"]["normalizedTo"], "window")
        self.assertAlmostEqual(selectors[3]["boundsNorm"]["x"], 0.5167, places=4)
        self.assertEqual(
            selectors[0]["fallbackSelectorStrategies"],
            ["role_and_name", "role_and_ancestry_path", "bounds_norm", "absolute_coordinate"],
        )

    def test_repeated_events_keep_same_primary_selector_chain(self):
        base_context = {
            "appBundleId": "com.apple.Safari",
            "appName": "Safari",
            "windowTitle": "Results",
            "windowSignature": {
                "signature": "window-results-001",
                "signatureVersion": "window-v1",
                "role": "AXWindow",
                "subrole": "AXStandardWindow",
            },
            "focusedElement": {
                "role": "AXTextField",
                "title": "Search",
                "identifier": "address-bar",
                "boundingRect": {
                    "x": 150,
                    "y": 80,
                    "width": 640,
                    "height": 32,
                    "coordinateSpace": "screen",
                },
                "valueRedacted": False,
            },
        }

        selectors_a = build_accessibility_selector_chain(raw_event(pointer=(200, 96), context_snapshot=base_context))
        selectors_b = build_accessibility_selector_chain(raw_event(pointer=(240, 96), context_snapshot=base_context))

        self.assertEqual(
            [selector["selectorStrategy"] for selector in selectors_a[:-1]],
            [selector["selectorStrategy"] for selector in selectors_b[:-1]],
        )
        self.assertEqual(selectors_a[0]["elementIdentifier"], selectors_b[0]["elementIdentifier"])
        self.assertEqual(selectors_a[3]["boundsNorm"], selectors_b[3]["boundsNorm"])
        self.assertNotEqual(selectors_a[-1]["boundingRect"], selectors_b[-1]["boundingRect"])


if __name__ == "__main__":
    unittest.main()
