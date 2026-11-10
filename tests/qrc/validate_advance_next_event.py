#!/usr/bin/env python3
"""Validate manual Advance to Next Event, pause clearing, and scheduled-edge suppression."""

from __future__ import annotations

import json
import subprocess
import time
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


def set_value(name: str, value: object, delay: float = 0.7, component: str = COMPONENT) -> None:
    qrc("set", component, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def press(name: str, delay: float = 0.7) -> None:
    set_value(name, True, 0.15)
    set_value(name, False, delay)


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")


def provider_source() -> str:
    return """-- Temporary safe Advance to Next Event acceptance provider.
function GetFugSchedulerActions()
  return {
    {id = "AdvanceCurrent", label = "Advance Current", callback = function() print("Advance current callback") end},
    {id = "AdvanceTarget", label = "Advance Target", callback = function() print("Advance target callback") end},
    {id = "AdvanceFollowing", label = "Advance Following", callback = function() print("Advance following callback") end}
  }
end
"""


def main() -> None:
    ensure_design()
    required = [
        "ScheduleData", "AutomaticExecutionEnabled", "InspectorSlotSelect", "InspectorSlotPaused",
        "InspectorAdvanceNextEvent", "InspectorAdvanceStatus", "SchedulerSlotAdvance 1",
        "CurrentEvent", "NextEvent", "ExecutionStatus", "DiagnosticLog", "GlobalSchedulerSlotStatus",
        "ActionSource", "OneShotLateToleranceSeconds", "OneShotExecutionLedger",
        "ExecutionTestClockOffsetSeconds", "script.status", "script.error.count",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "Inspector and stable per-Slot advance controls exist")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable is off before advance testing")
    check(initial["ExecutionTestClockOffsetSeconds"]["Value"] == 0, "execution test clock is zero before testing")
    provider_initial = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
    original_schedule = initial["ScheduleData"]["String"]
    original_provider = provider_initial["code"]["String"]
    original_action_source = initial["ActionSource"]["String"]
    original_tolerance = initial["OneShotLateToleranceSeconds"]["Value"]
    original_ledger = initial["OneShotExecutionLedger"]["String"]

    global_status = json.loads(initial["GlobalSchedulerSlotStatus"]["String"])
    now = datetime.strptime(global_status["resolvedFor"], "%Y-%m-%d %H:%M:%S")
    target = (now + timedelta(minutes=2)).replace(second=0, microsecond=0)
    current = target - timedelta(minutes=3)
    following = target + timedelta(minutes=2)
    fixture = {
        "schemaVersion": 2,
        "revision": 1,
        "schedulerSlots": [{
            "slot": 1, "schedulerId": "advance-test", "enabled": True, "paused": True,
            "pauseMode": "Manual", "pauseDurationMinutes": 60, "pauseUntilTime": "",
            "pauseIntent": {"mode": "Manual", "requestedAt": int(time.time())},
        }, *[{
            "slot": index, "enabled": False, "paused": False,
            "pauseMode": "Manual", "pauseDurationMinutes": 60, "pauseUntilTime": "",
        } for index in range(2, 9)]],
        "schedulers": [{
            "id": "advance-test", "label": "Advance Test", "defaultWeekPatternId": "advance-week",
            "dayPatterns": [{
                "id": "advance-day", "label": "Advance Day", "events": [
                    {"id": "advance-current", "label": "Current State", "time": current.strftime("%H:%M"),
                     "actions": [{"actionId": "AdvanceCurrent", "enabled": True, "oneShot": False}]},
                    {"id": "advance-target", "label": "Advanced State", "time": target.strftime("%H:%M"),
                     "actions": [{"actionId": "AdvanceTarget", "enabled": True, "oneShot": True}]},
                    {"id": "advance-following", "label": "Following State", "time": following.strftime("%H:%M"),
                     "actions": [{"actionId": "AdvanceFollowing", "enabled": True, "oneShot": False}]},
                ],
            }],
            "weekPatterns": [{
                "id": "advance-week", "label": "Advance Week",
                "days": {day: "advance-day" for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
            }],
            "overrides": [],
        }],
    }

    try:
        set_value("OneShotLateToleranceSeconds", 0)
        set_value("ExecutionTestClockOffsetSeconds", 0)
        set_value("code", provider_source(), 1.0, component=ACTION_PROVIDER)
        set_value("ScheduleData", json.dumps(fixture, separators=(",", ":")), 1.4)
        set_value("InspectorSlotSelect", json.dumps({"Text": "Slot 1 — Advance Test", "Id": 1}, separators=(",", ":")))
        set_value("AutomaticExecutionEnabled", True, 1.2)
        before_log = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        press("InspectorAdvanceNextEvent", 1.2)

        state = controls("ScheduleData", "CurrentEvent", "NextEvent", "ExecutionStatus", "InspectorAdvanceStatus",
                         "SchedulerSlotPaused 1", "GlobalSchedulerSlotStatus")
        model = json.loads(state["ScheduleData"]["String"])
        slot = model["schedulerSlots"][0]
        check(slot["paused"] is False and "pauseIntent" not in slot,
              "manual advance clears an active pause")
        target_stamp = int(slot["advancedOccurrence"]["timestamp"])
        check(slot["advancedOccurrence"]["eventId"] == "advance-target" and
              target_stamp > int(time.time()),
              "manual advance persists the future consumed occurrence identity")
        check("Advanced State" in state["CurrentEvent"]["String"] and
              "Following State" in state["NextEvent"]["String"],
              "advanced Event becomes Current and the following Event becomes Next")
        check("manual advance" in state["ExecutionStatus"]["String"].lower(),
              "manual advance executes the target Event Actions with an explicit reason")
        after_log = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        manual_count = after_log.count('Action "Advance Target"')
        check(manual_count == before_log.count('Action "Advance Target"') + 1,
              "the target one-shot executes exactly once at manual advance")

        wait_seconds = max(0, target_stamp - int(time.time()) + 3)
        print(f"Waiting {wait_seconds}s through the original scheduled edge...")
        time.sleep(wait_seconds)
        after_edge = controls("ScheduleData", "DiagnosticLog", "CurrentEvent", "NextEvent")
        edge_model = json.loads(after_edge["ScheduleData"]["String"])
        check("advancedOccurrence" not in edge_model["schedulerSlots"][0],
              "the persisted advance marker clears after the original scheduled time")
        check(after_edge["DiagnosticLog"]["String"].count('Action "Advance Target"') == manual_count,
              "the original scheduled edge does not replay the advanced one-shot")
        check("Advanced State" in after_edge["CurrentEvent"]["String"] and
              "Following State" in after_edge["NextEvent"]["String"],
              "the cursor remains correctly positioned after the suppressed edge")

        # Exercise the stable external transport pin as well as the Inspector button.
        press("SchedulerSlotAdvance 1", 1.2)
        pin_state = controls("CurrentEvent", "ExecutionStatus")
        check("Following State" in pin_state["CurrentEvent"]["String"] and
              "manual advance" in pin_state["ExecutionStatus"]["String"].lower(),
              "stable per-Slot Advance pin performs the same transition")
    finally:
        set_value("AutomaticExecutionEnabled", False, 0.3)
        set_value("ScheduleData", original_schedule, 1.2)
        set_value("OneShotExecutionLedger", original_ledger, 0.3)
        set_value("OneShotLateToleranceSeconds", original_tolerance, 0.2)
        set_value("ExecutionTestClockOffsetSeconds", 0, 0.2)
        set_value("code", original_provider, 1.0, component=ACTION_PROVIDER)
        set_value("ActionSource", original_action_source, 0.8)
        for control in ["InspectorAdvanceNextEvent", "SchedulerSlotAdvance 1"]:
            set_value(control, False, 0.1)
        final = controls(
            "ScheduleData", "AutomaticExecutionEnabled", "OneShotExecutionLedger",
            "OneShotLateToleranceSeconds", "ExecutionTestClockOffsetSeconds",
        )
        restored = (
            final["ScheduleData"]["String"] == original_schedule
            and final["OneShotExecutionLedger"]["String"] == original_ledger
            and final["OneShotLateToleranceSeconds"]["Value"] == original_tolerance
            and final["ExecutionTestClockOffsetSeconds"]["Value"] == 0
            and final["AutomaticExecutionEnabled"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} advance fixture restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore Advance to Next Event fixture")

    plugin_health = controls("script.status", "script.error.count")
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    provider_health = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(all(item["script.status"]["String"] == "OK" and item["script.error.count"]["Value"] == 0
              for item in [plugin_health, runtime_health, provider_health]),
          "plugin, runtime provider, and Action provider finish healthy")
    print(f"SUCCESS: {len(assertions)} Advance to Next Event assertions passed")


if __name__ == "__main__":
    main()
