#!/usr/bin/env python3
"""Offline contract checks for Restore Schedule State transport."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = (ROOT / "src/runtime.lua").read_text()
CONTROLS = (ROOT / "src/controls.lua").read_text()
LAYOUT = (ROOT / "src/layout.lua").read_text()


def function_body(source: str, name: str) -> str:
    marker = f"function FugSchedulerRuntime.{name}("
    start = source.index(marker)
    match = re.search(r"\nfunction FugSchedulerRuntime\.[A-Za-z0-9_]+\(", source[start + len(marker):])
    end = len(source) if match is None else start + len(marker) + match.start()
    return source[start:end]


def main() -> None:
    if 'Name = "SchedulerSlotRestoreSchedule"' not in CONTROLS or 'UserPin = true' not in CONTROLS:
        raise AssertionError("Restore Schedule must have a stable counted public input control")
    if 'Name = "InspectorRestoreSchedule"' not in CONTROLS:
        raise AssertionError("Slot Inspector must expose Restore Schedule")
    if '"SchedulerSlotRestoreSchedule"' not in LAYOUT or 'ui:button("InspectorRestoreSchedule"' not in LAYOUT:
        raise AssertionError("Restore controls must be bound into the plugin layout")

    restore = function_body(RUNTIME, "restoreSlotScheduleState")
    required = [
        "if not slot.advancedOccurrence then",
        "activeSlot.advancedOccurrence = nil",
        "positionPlanCursor(plan, now)",
        '"fireOnStartup"',
        '"schedule state restore"',
        "publishLiveRuntimeStatus()",
    ]
    for fragment in required:
        if fragment not in restore:
            raise AssertionError(f"Restore Schedule implementation is missing: {fragment}")
    if "recoverCurrentOneShots" in restore:
        raise AssertionError("Restore Schedule must not replay one-shot Actions")
    if "pauseIntent = nil" in restore or "paused = false" in restore:
        raise AssertionError("Restore Schedule must not alter pause state")

    handlers = function_body(RUNTIME, "attachHandlers")
    for control_name in ("SchedulerSlotRestoreSchedule", "InspectorRestoreSchedule"):
        if control_name not in handlers:
            raise AssertionError(f"Restore handler missing for {control_name}")

    print("SUCCESS: Restore Schedule State contract checks passed")


if __name__ == "__main__":
    main()
