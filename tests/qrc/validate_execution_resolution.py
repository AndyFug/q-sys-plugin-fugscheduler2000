#!/usr/bin/env python3
"""Validate cursor resolution across midnight, Overrides, and long empty ranges."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
assertions: list[str] = []


def qrc(*args: str) -> object:
    result = subprocess.run(
        ["node", str(QRC), "--host", HOST, *args], cwd=ROOT,
        text=True, capture_output=True, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def ensure_expected_design(label: str) -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          f"{label}: expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", f"{label}: expected design is active")


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.2) -> None:
    qrc("set", COMPONENT, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def press(name: str) -> None:
    set_value(name, True, 0.1)
    set_value(name, False, 0.3)


def event(event_id: str, label: str, time_text: str) -> dict:
    return {
        "id": event_id,
        "label": label,
        "time": time_text,
        "actions": [{
            "actionId": "Callback1", "enabled": True, "oneShot": False,
            "fireOnStartup": False, "fireOnResume": False,
        }],
    }


def scheduler(scheduler_id: str, label: str, day_patterns: list[dict], default_day_id: str, overrides: list[dict]) -> dict:
    week_id = scheduler_id + "-week"
    return {
        "id": scheduler_id,
        "label": label,
        "enabled": False,
        "paused": False,
        "defaultWeekPatternId": week_id,
        "dayPatterns": day_patterns,
        "weekPatterns": [{
            "id": week_id,
            "label": label + " Week",
            "days": {day: default_day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": overrides,
    }


def resolve(test_time: str) -> dict:
    set_value("TestDateTime", test_time, 0.1)
    press("ResolveTestTime")
    return json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])


def main() -> None:
    ensure_expected_design("preflight")
    initial = controls(
        "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
        "GlobalSchedulerStatus", "script.status", "script.error.count",
    )
    runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution is off before resolver testing")
    check(
        initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0
        and runtime["script.status"]["String"] == "OK" and runtime["script.error.count"]["Value"] == 0,
        "plugin and runtime provider are healthy before resolver testing",
    )

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    try:
        midnight = scheduler(
            "cursor-midnight", "Cursor Midnight",
            [{"id": "midnight-day", "label": "Midnight Day", "events": [
                event("midnight-early", "Early", "00:05"),
                event("midnight-late", "Late", "23:55"),
            ]}],
            "midnight-day", [],
        )
        gap = scheduler(
            "cursor-gap", "Cursor Gap",
            [
                {"id": "active-day", "label": "Active Day", "events": [event("gap-noon", "Noon", "12:00")]},
                {"id": "empty-day", "label": "Empty Day", "events": []},
            ],
            "active-day",
            [{
                "id": "long-empty-override", "label": "Long Empty Override", "enabled": True,
                "type": "DayPattern", "startDate": "2026-12-01", "endDate": "2027-03-31",
                "patternId": "empty-day",
            }],
        )
        model = {"schemaVersion": 1, "revision": 1, "schedulers": [midnight, gap]}
        ensure_expected_design("fixture mutation")
        set_value("ScheduleData", json.dumps(model, separators=(",", ":")), 1.0)

        status = resolve("2026-12-25 00:00")
        entries = {item["id"]: item for item in status["schedulers"]}
        midnight_status = entries["cursor-midnight"]
        check(midnight_status["currentEvent"]["id"] == "midnight-late", "Current crosses midnight from the previous date")
        check(midnight_status["currentEvent"]["date"] == "2026-12-24", "cross-midnight Current retains its occurrence date")
        check(midnight_status["previousEvent"]["id"] == "midnight-early", "Previous is immediately before cross-midnight Current")
        check(midnight_status["nextEvent"]["id"] == "midnight-early", "Next resolves the upcoming Event after midnight")
        check(midnight_status["nextEvent"]["date"] == "2026-12-25", "Next retains today's occurrence date")

        gap_status = entries["cursor-gap"]
        check(gap_status["resolution"]["sourceType"] == "DayPatternOverride", "enabled Day Pattern Override wins at the test date")
        check(gap_status["resolution"]["dayPatternId"] == "empty-day", "Override resolves the empty Day Pattern")
        check(gap_status["currentEvent"]["date"] == "2026-11-30", "incremental resolver finds Current before a long empty range")
        check(gap_status["nextEvent"]["date"] == "2027-04-01", "incremental resolver finds Next after a long empty range")

        before_boundary = resolve("2026-11-30 13:00")
        before_gap = {item["id"]: item for item in before_boundary["schedulers"]}["cursor-gap"]
        check(before_gap["resolution"]["sourceType"] == "DefaultWeekPattern", "date before Override uses the Default Week Pattern")
        at_boundary = resolve("2026-12-01 00:00")
        boundary_gap = {item["id"]: item for item in at_boundary["schedulers"]}["cursor-gap"]
        check(boundary_gap["resolution"]["sourceType"] == "DayPatternOverride", "Override is inclusive at its start boundary")
        check('\"_' not in controls("ScheduleData")["ScheduleData"]["String"], "runtime cursor/cache state is absent from ScheduleData")
    finally:
        ensure_expected_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ScheduleData", original_schedule, 0.8)
        set_value("TestDateTime", original_test_time, 0.2)
        final = controls(
            "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
            "script.status", "script.error.count",
        )
        final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        restored = (
            final["ScheduleData"]["String"] == original_schedule
            and final["TestDateTime"]["String"] == original_test_time
            and final["AutomaticExecutionEnabled"]["Value"] < 0.5
            and final["ResolveTestTime"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} resolver fixtures restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore resolver fixtures")
        check(
            final["script.status"]["String"] == "OK" and final["script.error.count"]["Value"] == 0
            and final_runtime["script.status"]["String"] == "OK" and final_runtime["script.error.count"]["Value"] == 0,
            "plugin and runtime provider finish healthy after resolver testing",
        )

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
