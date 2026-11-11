#!/usr/bin/env python3
"""Offline regression checks for JSON-safe one-shot receipt persistence."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "src/runtime.lua"


def function_body(source: str, name: str) -> str:
    marker = f"function FugSchedulerRuntime.{name}("
    start = source.index(marker)
    match = re.search(r"\nfunction FugSchedulerRuntime\.[A-Za-z0-9_]+\(", source[start + len(marker):])
    end = len(source) if match is None else start + len(marker) + match.start()
    return source[start:end]


def main() -> None:
    source = RUNTIME.read_text()

    occurrence_key = function_body(source, "occurrenceKey")
    receipt_key = function_body(source, "oneShotReceiptKey")
    for name, body in (("occurrenceKey", occurrence_key), ("oneShotReceiptKey", receipt_key)):
        if '"\\30"' in body or '"\\31"' in body:
            raise AssertionError(f"{name} must not place control-character separators in persisted identities")
        if '}, "|")' not in body or "stableIdentityPart" not in body:
            raise AssertionError(f"{name} must use escaped printable identity parts")

    if '}, "\\30")' in source or '}, "\\31")' in source:
        raise AssertionError("runtime identities must not use control-character separators")

    pause_expiry = function_body(source, "pauseExpiryForPoll")
    pause_refresh = function_body(source, "refreshPlanPauseTarget")
    if "occurrenceKey(target)" not in pause_expiry:
        raise AssertionError("pause expiry must compare the canonical occurrence identity")
    if "occurrenceKey(intent.target)" not in pause_refresh or "occurrenceKey(target)" not in pause_refresh:
        raise AssertionError("pause target refresh must compare canonical occurrence identities")

    normalise = function_body(source, "normaliseOneShotReceiptKey")
    if 'key:find("[\\30\\31]")' not in normalise or 'key:gmatch("[^\\30\\31]+")' not in normalise:
        raise AssertionError("legacy receipt keys must be detected and migrated")

    reload_body = function_body(source, "reloadOneShotLedger")
    if 'source:gsub("\\30", "\\\\u001E"):gsub("\\31", "\\\\u001F")' not in reload_body:
        raise AssertionError("raw legacy separators must be escaped before RapidJSON decoding")
    if "Legacy one-shot ledger receipt keys migrated to JSON-safe format" not in reload_body:
        raise AssertionError("successful physical-Core ledger migration must be logged")

    persist = function_body(source, "persistOneShotLedger")
    if 'serialized:find("[\\30\\31]")' not in persist:
        raise AssertionError("ledger persistence must reject unsafe control characters")

    legacy_key = "scheduler\x1e123\x1f2026-11-11\x1fday\x1fevent\x1f1\x1e1\x1eaction"
    malformed = json.dumps({"schemaVersion": 1, "receipts": [{
        "key": legacy_key, "executedAt": 123, "occurrenceTimestamp": 123,
    }]}).replace("\\u001e", "\x1e").replace("\\u001f", "\x1f")
    try:
        json.loads(malformed)
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError("production fixture must reproduce strict JSON failure")
    repaired = malformed.replace("\x1e", "\\u001E").replace("\x1f", "\\u001F")
    decoded_key = json.loads(repaired)["receipts"][0]["key"]
    migrated_key = "|".join(re.split("[\x1e\x1f]", decoded_key))
    if migrated_key != "scheduler|123|2026-11-11|day|event|1|1|action":
        raise AssertionError("legacy receipt migration must retain the complete identity")

    print("SUCCESS: one-shot ledger JSON-safety contract checks passed")


if __name__ == "__main__":
    main()
