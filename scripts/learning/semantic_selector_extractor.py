#!/usr/bin/env python3
"""Extract stable selector chains from raw event accessibility context."""

from __future__ import annotations

import json
from pathlib import Path
import re
from typing import Any
from urllib.parse import urlparse


SELECTOR_EXTRACTOR_VERSION = "sem-102-accessibility-selector-v1"
URL_KEYS = (
    "url",
    "pageUrl",
    "pageURL",
    "currentUrl",
    "currentURL",
    "browserUrl",
    "browserURL",
)
URL_CONTEXT_KEYS = ("browserContext", "pageContext", "navigationContext")


def exact_window_title_pattern(window_title: str | None) -> str | None:
    if not isinstance(window_title, str) or not window_title.strip():
        return None
    return f"^{re.escape(window_title.strip())}$"


def normalize_text(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def event_context(event: dict[str, Any]) -> dict[str, Any]:
    context = event.get("contextSnapshot")
    return context if isinstance(context, dict) else {}


def focused_element(event: dict[str, Any]) -> dict[str, Any] | None:
    focused = event_context(event).get("focusedElement")
    return focused if isinstance(focused, dict) else None


def event_pointer(event: dict[str, Any]) -> dict[str, Any] | None:
    pointer = event.get("pointer")
    if not isinstance(pointer, dict):
        return None
    if not isinstance(pointer.get("x"), (int, float)) or not isinstance(pointer.get("y"), (int, float)):
        return None
    return {
        "x": float(pointer["x"]),
        "y": float(pointer["y"]),
        "width": 1.0,
        "height": 1.0,
        "coordinateSpace": pointer.get("coordinateSpace") or "screen",
    }


def bounding_rect(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    numeric_keys = ("x", "y", "width", "height")
    if any(not isinstance(value.get(key), (int, float)) for key in numeric_keys):
        return None
    return {
        "x": float(value["x"]),
        "y": float(value["y"]),
        "width": float(value["width"]),
        "height": float(value["height"]),
        "coordinateSpace": value.get("coordinateSpace") or "screen",
    }


def best_element_text(focused: dict[str, Any]) -> str | None:
    for key in ("title", "descriptionText", "helpText", "valuePreview", "placeholderValue"):
        normalized = normalize_text(focused.get(key))
        if normalized:
            return normalized
    return None


def element_identifier(focused: dict[str, Any]) -> str | None:
    for key in ("automationId", "automation_id", "identifier"):
        normalized = normalize_text(focused.get(key))
        if normalized:
            return normalized
    attributes = focused.get("attributes")
    if isinstance(attributes, dict):
        for key in ("automationId", "automation_id", "identifier"):
            normalized = normalize_text(attributes.get(key))
            if normalized:
                return normalized
    return None


def first_url_like(value: Any) -> str | None:
    normalized = normalize_text(value)
    if normalized and "://" in normalized:
        return normalized
    return None


def context_url(context: dict[str, Any]) -> str | None:
    for key in URL_KEYS:
        candidate = first_url_like(context.get(key))
        if candidate:
            return candidate

    for key in URL_CONTEXT_KEYS:
        nested = context.get(key)
        if not isinstance(nested, dict):
            continue
        for nested_key in URL_KEYS:
            candidate = first_url_like(nested.get(nested_key))
            if candidate:
                return candidate
    return None


def context_url_host(context: dict[str, Any]) -> str | None:
    explicit = normalize_text(context.get("urlHost"))
    if explicit:
        return explicit
    url = context_url(context)
    if not url:
        return None
    return normalize_text(urlparse(url).hostname)


def window_bounds(context: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("windowBounds", "windowFrame", "screenBounds", "screenFrame"):
        rect = bounding_rect(context.get(key))
        if rect is not None and rect["width"] > 0 and rect["height"] > 0:
            return rect
    return None


def bounds_norm(rect: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    bounds = window_bounds(context)
    if bounds is not None:
        return {
            "normalizedTo": "window",
            "coordinateSpace": rect.get("coordinateSpace") or bounds.get("coordinateSpace") or "screen",
            "x": round((rect["x"] - bounds["x"]) / bounds["width"], 4),
            "y": round((rect["y"] - bounds["y"]) / bounds["height"], 4),
            "width": round(rect["width"] / bounds["width"], 4),
            "height": round(rect["height"] / bounds["height"], 4),
        }
    return {
        "normalizedTo": "screen-quantized",
        "coordinateSpace": rect.get("coordinateSpace") or "screen",
        "x": round(rect["x"], 1),
        "y": round(rect["y"], 1),
        "width": round(rect["width"], 1),
        "height": round(rect["height"], 1),
    }


def explicit_ancestry_path(focused: dict[str, Any], context: dict[str, Any]) -> str | None:
    for raw_value in (
        focused.get("ancestryPath"),
        focused.get("axPath"),
        focused.get("path"),
        context.get("focusedElementPath"),
    ):
        if isinstance(raw_value, str):
            normalized = normalize_text(raw_value)
            if normalized:
                return normalized
        if isinstance(raw_value, list):
            segments = [normalize_text(item) for item in raw_value if normalize_text(item)]
            if segments:
                return "/".join(segments)
    return None


def derived_ancestry_path(focused: dict[str, Any], context: dict[str, Any]) -> str | None:
    explicit = explicit_ancestry_path(focused, context)
    if explicit:
        return explicit

    window_signature = context.get("windowSignature")
    segments: list[str] = []
    if isinstance(window_signature, dict):
        for key in ("role", "subrole"):
            normalized = normalize_text(window_signature.get(key))
            if normalized and normalized not in segments:
                segments.append(normalized)

    for key in ("role", "subrole"):
        normalized = normalize_text(focused.get(key))
        if normalized and normalized not in segments:
            segments.append(normalized)

    if len(segments) < 2:
        return None
    return "/".join(segments)


def selector_context_fields(context: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "appBundleId": context.get("appBundleId"),
        "appName": context.get("appName"),
        "windowTitlePattern": exact_window_title_pattern(context.get("windowTitle")),
        "windowSignature": context.get("windowSignature"),
    }
    url = context_url(context)
    url_host = context_url_host(context)
    if url:
        payload["url"] = url
    if url_host:
        payload["urlHost"] = url_host
    return payload


def selector_strategy_confidence(strategy: str) -> float:
    mapping = {
        "automation_id": 0.96,
        "role_and_name": 0.88,
        "role_and_ancestry_path": 0.74,
        "bounds_norm": 0.62,
        "absolute_coordinate": 0.24,
        "app_context": 0.82,
        "window_context": 0.82,
    }
    return mapping.get(strategy, 0.45)


def selector_signature(selector: dict[str, Any]) -> str:
    return json.dumps(
        {
            "locatorType": selector.get("locatorType"),
            "selectorStrategy": selector.get("selectorStrategy"),
            "appBundleId": selector.get("appBundleId"),
            "windowTitlePattern": selector.get("windowTitlePattern"),
            "windowSignature": selector.get("windowSignature"),
            "urlHost": selector.get("urlHost"),
            "elementRole": selector.get("elementRole"),
            "elementTitle": selector.get("elementTitle"),
            "elementIdentifier": selector.get("elementIdentifier"),
            "axPath": selector.get("axPath"),
            "boundsNorm": selector.get("boundsNorm"),
            "boundingRect": selector.get("boundingRect"),
        },
        ensure_ascii=False,
        sort_keys=True,
    )


def annotate_selector_chain(selectors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: list[dict[str, Any]] = []
    seen_signatures: set[str] = set()
    for selector in selectors:
        signature = selector_signature(selector)
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        deduped.append(selector)

    size = len(deduped)
    annotated: list[dict[str, Any]] = []
    for index, selector in enumerate(deduped, start=1):
        item = dict(selector)
        item["selectorChainOrdinal"] = index
        item["selectorChainSize"] = size
        item["fallbackLocatorTypes"] = [
            candidate.get("locatorType") for candidate in deduped[index:] if candidate.get("locatorType")
        ]
        item["fallbackSelectorStrategies"] = [
            candidate.get("selectorStrategy")
            for candidate in deduped[index:]
            if candidate.get("selectorStrategy")
        ]
        annotated.append(item)
    return annotated


def build_accessibility_selector_chain(event: dict[str, Any]) -> list[dict[str, Any]]:
    context = event_context(event)
    focused = focused_element(event)
    pointer = event_pointer(event)
    if focused is None:
        return annotate_selector_chain(
            [
                {
                    **selector_context_fields(context),
                    "locatorType": "coordinateFallback",
                    "selectorKind": "coordinateFallback",
                    "selectorStrategy": "absolute_coordinate",
                    "boundingRect": pointer,
                    "confidence": selector_strategy_confidence("absolute_coordinate"),
                    "source": "raw-event-pointer",
                    "selectorExtractorVersion": SELECTOR_EXTRACTOR_VERSION,
                }
            ]
            if pointer is not None
            else []
        )

    selectors: list[dict[str, Any]] = []
    base = {
        **selector_context_fields(context),
        "selectorKind": "uiElement",
        "elementRole": normalize_text(focused.get("role")) or normalize_text(focused.get("subrole")),
        "elementSubrole": normalize_text(focused.get("subrole")),
        "descriptionText": normalize_text(focused.get("descriptionText")),
        "helpText": normalize_text(focused.get("helpText")),
        "boundingRect": bounding_rect(focused.get("boundingRect")),
        "source": "sem102-selector-extractor",
        "selectorExtractorVersion": SELECTOR_EXTRACTOR_VERSION,
    }
    identifier = element_identifier(focused)
    title = best_element_text(focused)
    ancestry_path = derived_ancestry_path(focused, context)
    rect = base.get("boundingRect")

    if identifier:
        selectors.append(
            {
                **base,
                "locatorType": "roleAndTitle",
                "selectorStrategy": "automation_id",
                "elementIdentifier": identifier,
                "elementTitle": title,
                "confidence": selector_strategy_confidence("automation_id"),
            }
        )

    if base.get("elementRole") and title:
        selectors.append(
            {
                **base,
                "locatorType": "roleAndTitle",
                "selectorStrategy": "role_and_name",
                "elementTitle": title,
                "textAnchor": title,
                "confidence": selector_strategy_confidence("role_and_name"),
            }
        )

    if base.get("elementRole") and ancestry_path:
        selectors.append(
            {
                **base,
                "locatorType": "axPath",
                "selectorStrategy": "role_and_ancestry_path",
                "axPath": ancestry_path,
                "ancestryPath": ancestry_path,
                "elementTitle": title,
                "elementIdentifier": identifier,
                "confidence": selector_strategy_confidence("role_and_ancestry_path"),
            }
        )

    if rect is not None:
        selectors.append(
            {
                **base,
                "locatorType": "coordinateFallback",
                "selectorKind": "boundsNorm",
                "selectorStrategy": "bounds_norm",
                "boundsNorm": bounds_norm(rect, context),
                "confidence": selector_strategy_confidence("bounds_norm"),
            }
        )

    if pointer is not None:
        selectors.append(
            {
                **selector_context_fields(context),
                "locatorType": "coordinateFallback",
                "selectorKind": "coordinateFallback",
                "selectorStrategy": "absolute_coordinate",
                "boundingRect": pointer,
                "confidence": selector_strategy_confidence("absolute_coordinate"),
                "source": "raw-event-pointer",
                "selectorExtractorVersion": SELECTOR_EXTRACTOR_VERSION,
            }
        )

    return annotate_selector_chain(selectors)


def selector_chain_summary(selectors: list[dict[str, Any]]) -> dict[str, Any]:
    if not selectors:
        return {"candidateCount": 0, "locatorTypes": [], "selectorStrategies": []}
    primary = selectors[0]
    return {
        "candidateCount": len(selectors),
        "locatorTypes": [selector.get("locatorType") for selector in selectors if selector.get("locatorType")],
        "selectorStrategies": [
            selector.get("selectorStrategy") for selector in selectors if selector.get("selectorStrategy")
        ],
        "preferredLocatorType": primary.get("locatorType"),
        "preferredSelectorStrategy": primary.get("selectorStrategy"),
    }


def selector_manual_review_required(selector: dict[str, Any]) -> bool:
    strategy = selector.get("selectorStrategy")
    return strategy in {"bounds_norm", "absolute_coordinate", None}

