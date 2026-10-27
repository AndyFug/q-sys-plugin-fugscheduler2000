#!/usr/bin/env python3
"""Validate the banked Overview, Inspector selection, and live/test-time controls."""

from __future__ import annotations

import json
import subprocess
import time
from datetime import datetime
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


def ensure_design(label: str) -> None:
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


def press(name: str, delay: float = 0.4) -> None:
    set_value(name, True, 0.1)
    set_value(name, False, delay)


def scheduler(index: int) -> dict:
    scheduler_id = f"qrc-overview-{index:02d}"
    day_id = scheduler_id + "-day"
    return {
        "id": scheduler_id,
        "label": f"Overview Scheduler {index:02d}",
        "enabled": False,
        "paused": index == 2,
        "defaultWeekPatternId": scheduler_id + "-week",
        "dayPatterns": [{
            "id": day_id,
            "label": f"Overview Day {index:02d}",
            "events": [{
                "id": scheduler_id + "-event",
                "label": f"Event {index:02d}",
                "time": "09:00",
                "actions": [{
                    "actionId": "Callback1", "enabled": True, "oneShot": False,
                    "fireOnStartup": False, "fireOnResume": False,
                }],
            }],
        }],
        "weekPatterns": [{
            "id": scheduler_id + "-week",
            "label": f"Overview Week {index:02d}",
            "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": [],
    }


def main() -> None:
    ensure_design("preflight")
    required = [
        "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "OverviewPreviousBank",
        "OverviewNextBank", "OverviewBankStatus", "OverviewSchedulerLabel 1",
        "OverviewSchedulerEnabled 1", "OverviewSchedulerPaused 1", "OverviewCurrentPattern 1", "OverviewCurrentEvent 1",
        "OverviewNextEvent 1", "OverviewNextTime 1", "UseLiveTime", "ResolveTestTime",
        "SchedulerSelect", "CurrentEvent", "NextEvent", "GlobalSchedulerStatus",
        "script.status", "script.error.count",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "Overview, Inspector, and live-time controls exist")
    runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    provider = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Execution is off before Overview testing")
    check(initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0
          and runtime["script.status"]["String"] == "OK" and runtime["script.error.count"]["Value"] == 0
          and provider["script.status"]["String"] == "OK" and provider["script.error.count"]["Value"] == 0,
          "all three scripts start healthy")

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    original_model = json.loads(original_schedule)
    try:
        model = {
            "schemaVersion": 1,
            "revision": int(original_model.get("revision", 0)) + 1,
            "schedulers": [scheduler(index) for index in range(1, 13)],
        }
        ensure_design("fixture mutation")
        set_value("TestDateTime", "", 0.2)
        set_value("ScheduleData", json.dumps(model, separators=(",", ":")), 1.0)
        time.sleep(3.5)

        first = controls(
            "OverviewBankStatus", "OverviewPreviousBank", "OverviewNextBank",
            "OverviewSchedulerLabel 1", "OverviewSchedulerLabel 2", "OverviewSchedulerLabel 10",
            "OverviewSchedulerEnabled 1", "OverviewSchedulerPaused 2", "OverviewCurrentPattern 1",
            "OverviewCurrentEvent 1", "OverviewNextEvent 1", "OverviewNextTime 1",
        )
        check(first["OverviewBankStatus"]["String"] == "Page 1 of 2 (Total 12 schedulers)", "first bank reports page 1 of 2 and total Scheduler count")
        check(first["OverviewPreviousBank"].get("Disabled") is True, "Previous Bank is disabled at the first bank")
        check(first["OverviewNextBank"].get("Disabled") is False, "Next Bank is enabled when another bank exists")
        check(first["OverviewSchedulerLabel 1"]["String"].endswith("Overview Scheduler 01"), "first row displays Scheduler 01")
        check(first["OverviewSchedulerLabel 10"]["String"].endswith("Overview Scheduler 10"), "tenth row displays Scheduler 10")
        check(first["OverviewSchedulerEnabled 1"]["Value"] < 0.5, "Enabled column reflects the persisted disabled state")
        check(first["OverviewSchedulerPaused 2"]["Value"] > 0.5, "Paused column reflects the persisted paused state")
        check("Overview Week 01 / Overview Day 01" in first["OverviewCurrentPattern 1"]["String"], "Current Pattern displays source and Day Pattern")
        check(first["OverviewCurrentEvent 1"]["String"].startswith("Event 01 (") and "09:00)" in first["OverviewCurrentEvent 1"]["String"], "Current column displays Event occurrence date and time")
        check(first["OverviewNextEvent 1"]["String"].startswith("Event 01 (") and "09:00)" in first["OverviewNextEvent 1"]["String"], "Next column displays next occurrence date and time")
        check(first["OverviewNextTime 1"]["String"] != "", "Next-time column publishes a compact timestamp")

        base_revision = model["revision"]
        set_value("OverviewSchedulerEnabled 1", True, 1.0)
        enabled_state = controls("ScheduleData", "OverviewSchedulerEnabled 1")
        enabled_model = json.loads(enabled_state["ScheduleData"]["String"])
        check(enabled_model["revision"] == base_revision + 1
              and enabled_model["schedulers"][0]["enabled"] is True,
              "Overview Enable commits the represented Scheduler through ScheduleData")
        check(enabled_state["OverviewSchedulerEnabled 1"]["Value"] > 0.5,
              "Overview Enable reflects the committed state")

        set_value("OverviewSchedulerPaused 1", True, 1.0)
        paused_state = controls("ScheduleData", "OverviewSchedulerPaused 1")
        paused_model = json.loads(paused_state["ScheduleData"]["String"])
        check(paused_model["revision"] == base_revision + 2
              and paused_model["schedulers"][0]["paused"] is True,
              "Overview Pause commits the represented Scheduler through ScheduleData")
        check(paused_state["OverviewSchedulerPaused 1"]["Value"] > 0.5,
              "Overview Pause reflects the committed state")

        set_value("OverviewSchedulerEnabled 1", False, 0.8)
        set_value("OverviewSchedulerPaused 1", False, 0.8)
        reverted_model = json.loads(controls("ScheduleData")["ScheduleData"]["String"])
        check(reverted_model["revision"] == base_revision + 4
              and reverted_model["schedulers"][0]["enabled"] is False
              and reverted_model["schedulers"][0]["paused"] is False,
              "Overview toggles can restore the original Scheduler state")

        press("OverviewNextBank")
        second = controls(
            "OverviewBankStatus", "OverviewPreviousBank", "OverviewNextBank",
            "OverviewSchedulerLabel 1", "OverviewSchedulerLabel 2", "OverviewSchedulerLabel 3",
            "OverviewSchedulerEnabled 3", "OverviewSchedulerPaused 3",
        )
        check(second["OverviewBankStatus"]["String"] == "Page 2 of 2 (Total 12 schedulers)", "second bank reports page 2 of 2 and total Scheduler count")
        check(second["OverviewPreviousBank"].get("Disabled") is False, "Previous Bank is enabled on the second bank")
        check(second["OverviewNextBank"].get("Disabled") is True, "Next Bank is disabled at the final bank")
        check(second["OverviewSchedulerLabel 1"]["String"].endswith("Overview Scheduler 11"), "second-bank row 1 displays Scheduler 11")
        check(second["OverviewSchedulerLabel 2"]["String"].endswith("Overview Scheduler 12"), "second-bank row 2 displays Scheduler 12")
        check(second["OverviewSchedulerLabel 3"]["String"] == "", "unused bank rows are blank")
        check(second["OverviewSchedulerEnabled 3"].get("Invisible") is True
              and second["OverviewSchedulerPaused 3"].get("Invisible") is True,
              "unused Enable and Pause indicators are hidden")

        press("OverviewPreviousBank")
        set_value("TestDateTime", "2030-01-02 12:00", 0.1)
        press("ResolveTestTime")
        pinned = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        check(pinned["resolvedFor"] == "2030-01-02 12:00:00", "Diagnostics preview pins aggregate status to Test Date/Time")
        press("UseLiveTime")
        live = controls("TestDateTime", "GlobalSchedulerStatus")
        live_status = json.loads(live["GlobalSchedulerStatus"]["String"])
        check(live["TestDateTime"]["String"] == "", "Use Live Time clears the diagnostic test value")
        check(live_status["resolvedFor"][:10] == datetime.now().strftime("%Y-%m-%d"), "Use Live Time republishes current-date status")

        set_value("AutomaticExecutionEnabled", True, 0.5)
        check(controls("AutomaticExecutionEnabled")["AutomaticExecutionEnabled"]["Value"] > 0.5,
              "Master Execution can be armed with all fixture Schedulers disabled")
        set_value("AutomaticExecutionEnabled", False, 0.5)
        check(controls("AutomaticExecutionEnabled")["AutomaticExecutionEnabled"]["Value"] < 0.5,
              "Master Execution returns to the safe off state")
        check('\"_' not in controls("ScheduleData")["ScheduleData"]["String"], "Overview bank state is absent from ScheduleData")
    finally:
        ensure_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ScheduleData", original_schedule, 0.8)
        set_value("TestDateTime", original_test_time, 0.3)
        final = controls(
            "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime", "UseLiveTime",
            "OverviewPreviousBank", "OverviewNextBank",
            "script.status", "script.error.count",
        )
        final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        final_provider = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
        restored = (final["ScheduleData"]["String"] == original_schedule
                    and final["TestDateTime"]["String"] == original_test_time
                    and final["AutomaticExecutionEnabled"]["Value"] < 0.5
                    and final["ResolveTestTime"]["Value"] < 0.5
                    and final["UseLiveTime"]["Value"] < 0.5
                    and final["OverviewPreviousBank"]["Value"] < 0.5
                    and final["OverviewNextBank"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} Overview fixtures restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore Overview fixtures")
        check(final["script.status"]["String"] == "OK" and final["script.error.count"]["Value"] == 0
              and final_runtime["script.status"]["String"] == "OK" and final_runtime["script.error.count"]["Value"] == 0
              and final_provider["script.status"]["String"] == "OK" and final_provider["script.error.count"]["Value"] == 0,
              "all three scripts finish healthy after Overview testing")

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
