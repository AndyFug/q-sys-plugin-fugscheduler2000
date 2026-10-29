#!/usr/bin/env python3
"""Validate persistent Scheduler Slot pause modes, re-arming, and target updates."""

from __future__ import annotations

import json
import subprocess
import time
from copy import deepcopy
from datetime import datetime, timedelta
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
ACTION_PROVIDER = "ActionProvider"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
assertions: list[str] = []


def qrc(*args: str) -> object:
    result = subprocess.run(["node", str(QRC), "--host", HOST, *args], cwd=ROOT,
                            text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.65) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def choice(identifier: object, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")


def fixture_scheduler(first_time: str, second_time: str) -> dict:
    return {
        "id": "pause-mode-test",
        "label": "Pause Mode Test",
        "defaultWeekPatternId": "pause-week",
        "dayPatterns": [{
            "id": "pause-day",
            "label": "Pause Day",
            "events": [
                {"id": "pause-event-a", "label": "Pause Event A", "time": first_time, "actions": []},
                {"id": "pause-event-b", "label": "Pause Event B", "time": second_time, "actions": []},
            ],
        }],
        "weekPatterns": [{
            "id": "pause-week",
            "label": "Pause Week",
            "days": {day: "pause-day" for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": [],
    }


def schedule() -> dict:
    return json.loads(controls("ScheduleData")["ScheduleData"]["String"])


def slot() -> dict:
    return schedule()["schedulerSlots"][0]


def main() -> None:
    ensure_design()
    required = [
        "ScheduleData", "AutomaticExecutionEnabled", "InspectorSlotSelect", "InspectorSlotPaused",
        "InspectorPauseMode", "InspectorPauseDurationMinutes", "InspectorPauseUntilTime",
        "InspectorPauseStatus", "InspectorPauseRequested", "InspectorPauseTarget", "InspectorPauseRemaining",
        "SchedulerSlotPaused 1", "SchedulerSlotPauseMode 1", "SchedulerSlotPauseDurationMinutes 1",
        "SchedulerSlotPauseUntilTime 1", "SchedulerSlotPauseStatus 1", "GlobalSchedulerSlotStatus",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "all Inspector and stable per-Slot pause controls exist")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable is off before pause testing")
    original_schedule = initial["ScheduleData"]["String"]

    now = datetime.now()
    first = now + timedelta(minutes=3)
    second = now + timedelta(minutes=6)
    moved_first = now + timedelta(minutes=8)
    fixture = {
        "schemaVersion": 2,
        "revision": 1,
        "schedulerSlots": [{
            "slot": 1, "schedulerId": "pause-mode-test", "enabled": False, "paused": False,
            "pauseMode": "Manual", "pauseDurationMinutes": 60, "pauseUntilTime": "",
        }, *[{
            "slot": index, "enabled": False, "paused": False,
            "pauseMode": "Manual", "pauseDurationMinutes": 60, "pauseUntilTime": "",
        } for index in range(2, 9)]],
        "schedulers": [fixture_scheduler(first.strftime("%H:%M"), second.strftime("%H:%M"))],
    }

    try:
        set_value("ScheduleData", json.dumps(fixture, separators=(",", ":")), 1.4)
        set_value("InspectorSlotSelect", choice(1, "Slot 1 — Pause Mode Test"))

        set_value("InspectorPauseMode", choice("Manual", "Manual"))
        set_value("InspectorSlotPaused", True)
        manual = slot()
        check(manual["paused"] is True and manual["pauseIntent"]["mode"] == "Manual",
              "Manual mode persists an active manual intent")
        set_value("InspectorSlotPaused", False)
        check(slot()["paused"] is False and "pauseIntent" not in slot(), "clearing Pause removes the active intent")

        expiry_fixture = schedule()
        expiry_slot = expiry_fixture["schedulerSlots"][0]
        expiry_requested = int(time.time())
        expiry_slot.update({
            "paused": True,
            "pauseMode": "Duration",
            "pauseDurationMinutes": 1,
            "pauseIntent": {"mode": "Duration", "requestedAt": expiry_requested, "expiresAt": expiry_requested + 2},
        })
        expiry_fixture["revision"] += 1
        set_value("ScheduleData", json.dumps(expiry_fixture, separators=(",", ":")), 3.8)
        check(slot()["paused"] is False and "pauseIntent" not in slot(),
              "automatic expiry clears persisted pause state without requiring Master Enable")

        set_value("InspectorPauseMode", choice("Duration", "Duration"))
        set_value("InspectorPauseDurationMinutes", "2")
        set_value("InspectorSlotPaused", True)
        duration = slot()
        first_requested = duration["pauseIntent"]["requestedAt"]
        check(duration["pauseIntent"]["expiresAt"] - first_requested == 120,
              "Duration mode stores an absolute two-minute expiry")
        set_value("InspectorPauseDurationMinutes", "3")
        rearmed = slot()
        check(rearmed["pauseIntent"]["requestedAt"] >= first_requested and
              rearmed["pauseIntent"]["expiresAt"] - rearmed["pauseIntent"]["requestedAt"] == 180,
              "editing an active Duration pause immediately re-arms it")

        until_value = (datetime.now() + timedelta(minutes=10)).strftime("%Y-%m-%d %H:%M")
        set_value("InspectorPauseUntilTime", until_value)
        set_value("InspectorPauseMode", choice("UntilTime", "Until Time"))
        until_pause = slot()
        check(until_pause["pauseIntent"]["mode"] == "UntilTime" and
              until_pause["pauseIntent"]["expiresAt"] > int(time.time()),
              "Until Time mode re-arms the active pause with a future absolute expiry")

        set_value("InspectorPauseMode", choice("NextEvent", "Next Event"), 1.0)
        next_event = slot()
        target = next_event["pauseIntent"]["target"]
        check(target["timestamp"] > int(time.time()) and target["eventId"] in {"pause-event-a", "pause-event-b"},
              "Next Event mode persists a future occurrence target")

        changed = schedule()
        definition = changed["schedulers"][0]
        definition["dayPatterns"][0]["events"][0]["time"] = moved_first.strftime("%H:%M")
        changed["revision"] += 1
        set_value("ScheduleData", json.dumps(changed, separators=(",", ":")), 1.4)
        updated = slot()["pauseIntent"]["target"]
        check(updated["eventId"] == "pause-event-b",
              "an active Next Event pause retargets when schedule edits change the next occurrence")

        set_value("InspectorPauseMode", choice("ThroughDay", "Through Day"), 1.0)
        through_day = slot()
        tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
        check(through_day["pauseIntent"]["notBeforeDate"] == tomorrow and
              through_day["pauseIntent"]["target"]["date"] >= tomorrow,
              "Through Day targets the first Event on or after the next calendar date")

        persisted_bytes = controls("ScheduleData")["ScheduleData"]["String"]
        set_value("ScheduleData", persisted_bytes, 1.2)
        reloaded = slot()
        check(reloaded["paused"] is True and reloaded["pauseIntent"]["mode"] == "ThroughDay",
              "reloading persisted ScheduleData preserves the active pause intent")

        status = json.loads(controls("GlobalSchedulerSlotStatus")["GlobalSchedulerSlotStatus"]["String"])["slots"][0]
        check(status["pause"]["active"] is True and status["pause"]["mode"] == "ThroughDay",
              "aggregate Slot status publishes configured and active pause state")
        set_value("SchedulerSlotPaused 1", False)
        check(slot()["paused"] is False, "stable per-Slot Pause control clears the active intent")
    finally:
        set_value("ScheduleData", original_schedule, 1.4)
        final = controls("ScheduleData", "AutomaticExecutionEnabled")
        restored = final["ScheduleData"]["String"] == original_schedule
        idle = final["AutomaticExecutionEnabled"]["Value"] < 0.5
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} pause fixture restored byte-for-byte")
        if not restored or not idle:
            raise AssertionError("failed to restore pause fixture or leave Master Enable off")

    health = controls("script.status", "script.error.count")
    runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    action = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0 and
          runtime["script.status"]["String"] == "OK" and runtime["script.error.count"]["Value"] == 0 and
          action["script.status"]["String"] == "OK" and action["script.error.count"]["Value"] == 0,
          "plugin, runtime provider, and Action provider finish healthy")
    print(f"SUCCESS: {len(assertions)} pause-mode assertions passed")


if __name__ == "__main__":
    main()
