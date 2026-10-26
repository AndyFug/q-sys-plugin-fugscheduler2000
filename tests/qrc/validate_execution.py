#!/usr/bin/env python3
"""Exercise guarded Scheduler startup, repeat, pause, and resume execution through QRC."""

from __future__ import annotations

import json
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"

assertions: list[str] = []


def qrc(*args: str) -> object:
    command = ["node", str(QRC), "--host", HOST, *args]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def controls(*names: str) -> dict[str, dict]:
    result = qrc("get", COMPONENT, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.15) -> None:
    qrc("set", COMPONENT, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def press(name: str) -> None:
    set_value(name, True)
    set_value(name, False)


def choice(identifier: str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def current_schedule_text() -> str:
    return controls("ScheduleData")["ScheduleData"]["String"]


def main() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active", "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")

    required = [
        "AutomaticExecutionEnabled", "ExecutionStatus", "ScheduleData", "TestDateTime", "ResolveTestTime",
        "SchedulerSelect", "SchedulerEditorEnabled", "SchedulerPaused", "EventActionEnabled", "EventActionMode",
        "EventActionFireOnStartup", "EventActionFireOnResume", "EventActionRepeatSeconds",
        "ActionSelect", "RegisteredActionCount", "GlobalSchedulerStatus", "DiagnosticLog", "Status",
        "script.status", "script.error.count",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "execution and Event Action option controls exist")
    check(initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0,
          "plugin script is OK with zero errors")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5,
          "automatic execution guard is off before testing")
    check(int(float(initial["RegisteredActionCount"]["String"])) >= 2,
          "at least two registered test Actions are available")
    action_choices = set(initial["ActionSelect"].get("Choices", []))
    check({"Callback1", "Callback2"}.issubset(action_choices),
          "Callback1 and Callback2 test Actions are registered")

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    restored = False

    try:
        set_value("TestDateTime", "")
        press("ResolveTestTime")
        live_status = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        now = datetime.strptime(live_status["resolvedFor"], "%Y-%m-%d %H:%M:%S")
        event_time = (now - timedelta(minutes=1)).strftime("%H:%M")

        model = json.loads(original_schedule)
        # Isolate ExecutionStatus from callbacks belonging to pre-existing enabled Schedulers.
        for existing_scheduler in model["schedulers"]:
            existing_scheduler["enabled"] = False
        scheduler_id = "qrc-execution-test-" + now.strftime("%Y%m%d%H%M%S")
        day_id = "qrc-execution-day"
        week_id = "qrc-execution-week"
        model["schedulers"].append({
            "id": scheduler_id,
            "label": "Execution QRC Test",
            "enabled": True,
            "paused": False,
            "defaultWeekPatternId": week_id,
            "dayPatterns": [{
                "id": day_id,
                "label": "Execution Test Day",
                "events": [{
                    "id": "qrc-current-event",
                    "label": "Current State",
                    "time": event_time,
                    "actions": [
                        {
                            "actionId": "Callback1",
                            "enabled": True,
                            "oneShot": False,
                            "fireOnStartup": True,
                            "fireOnResume": True,
                            "repeatSeconds": 2,
                        },
                        {
                            "actionId": "Callback2",
                            "enabled": True,
                            "oneShot": True,
                            "fireOnStartup": False,
                            "fireOnResume": False,
                        },
                    ],
                }],
            }],
            "weekPatterns": [{
                "id": week_id,
                "label": "Execution Test Week",
                "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
            }],
            "overrides": [],
        })
        set_value("ScheduleData", json.dumps(model, indent=2), delay=0.4)
        set_value("SchedulerSelect", choice(scheduler_id, "Execution QRC Test"))

        editor = controls(
            "EventActionEnabled", "EventActionMode", "EventActionFireOnStartup",
            "EventActionFireOnResume", "EventActionRepeatSeconds",
        )
        check(editor["EventActionEnabled"]["Value"] > 0.5,
              "selected stateful Event Action is enabled")
        check(json.loads(editor["EventActionMode"]["String"])["Id"] == "Stateful",
              "selected Event Action mode is Stateful")
        check(editor["EventActionFireOnStartup"]["Value"] > 0.5 and
              editor["EventActionFireOnResume"]["Value"] > 0.5,
              "startup and resume restoration options are visible")
        check(editor["EventActionRepeatSeconds"]["String"] == "2",
              "repeat interval is visible in the Event Action editor")

        set_value("AutomaticExecutionEnabled", True, delay=0.5)
        startup = controls("ExecutionStatus", "Status")
        check("Callback 1" in startup["ExecutionStatus"]["String"] and
              "startup" in startup["ExecutionStatus"]["String"],
              "startup restores the current stateful Action")
        check("Callback 2" not in startup["ExecutionStatus"]["String"],
              "startup does not replay the current one-shot Action")
        check("automatic execution ARMED" in startup["Status"]["String"],
              "aggregate status reports the execution guard as armed")
        startup_log = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        check('[INFO] Scheduler "Execution QRC Test"' in startup_log and
              "reason=startup | Executed successfully" in startup_log,
              "initial state restoration is logged at Info with execution context")

        time.sleep(2.4)
        repeat_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in repeat_status and "repeat" in repeat_status,
              "stateful Action repeats while its Event remains current")
        repeat_log = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        check('[DEBUG] Scheduler "Execution QRC Test"' in repeat_log and
              "reason=repeat | Executed successfully" in repeat_log,
              "subsequent repeat execution is logged at Debug with execution context")

        set_value("SchedulerPaused", True, delay=1.2)
        paused_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        time.sleep(2.4)
        check(controls("ExecutionStatus")["ExecutionStatus"]["String"] == paused_status,
              "pause blocks repeat callbacks while timeline resolution continues")

        set_value("SchedulerPaused", False, delay=1.2)
        resume_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in resume_status and "resume" in resume_status,
              "resume restores the current stateful Action")
        check("Callback 2" not in resume_status,
              "resume does not replay the current one-shot Action")

        set_value("SchedulerEditorEnabled", False, delay=1.2)
        scheduler_disabled_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        time.sleep(2.4)
        check(controls("ExecutionStatus")["ExecutionStatus"]["String"] == scheduler_disabled_status,
              "Scheduler disable blocks repeat callbacks independently of pause")

        set_value("SchedulerEditorEnabled", True, delay=1.2)
        scheduler_enabled_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in scheduler_enabled_status and "enabled" in scheduler_enabled_status,
              "Scheduler enable restores the current stateful Action")
        check("Callback 2" not in scheduler_enabled_status,
              "Scheduler enable does not replay the current one-shot Action")

        changed_model = json.loads(current_schedule_text())
        changed_scheduler = next(item for item in changed_model["schedulers"] if item["id"] == scheduler_id)
        changed_scheduler["dayPatterns"][0]["events"].append({
            "id": "qrc-current-event-b",
            "label": "Current State B",
            "time": now.strftime("%H:%M"),
            "actions": [{
                "actionId": "Callback2",
                "enabled": True,
                "oneShot": False,
                "fireOnStartup": False,
                "fireOnResume": False,
            }],
        })
        set_value("ScheduleData", json.dumps(changed_model, indent=2), delay=1.3)
        changed_to_b = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 2" in changed_to_b and "schedule change" in changed_to_b,
              "a schedule edit immediately reconciles the newly current stateful Event B")

        moved_model = json.loads(current_schedule_text())
        moved_scheduler = next(item for item in moved_model["schedulers"] if item["id"] == scheduler_id)
        event_b = next(item for item in moved_scheduler["dayPatterns"][0]["events"]
                       if item["id"] == "qrc-current-event-b")
        minute_of_day = (now.hour * 60) + now.minute
        if minute_of_day <= 1434:
            event_b["time"] = (now + timedelta(minutes=5)).strftime("%H:%M")
        else:
            event_b["time"] = "00:00"
        set_value("ScheduleData", json.dumps(moved_model, indent=2), delay=1.3)
        rolled_back_to_a = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in rolled_back_to_a and "schedule change" in rolled_back_to_a,
              "moving Event B out of the current position immediately restores stateful Event A")
        check("Callback 2" not in rolled_back_to_a,
              "schedule reconciliation does not replay Event A's one-shot Action")

        time.sleep(2.4)
        reconciled_repeat = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in reconciled_repeat and "repeat" in reconciled_repeat,
              "Event A repeats restart after immediate schedule reconciliation")

        set_value("AutomaticExecutionEnabled", False, delay=0.4)
        disabled_status = controls("ExecutionStatus", "Status")
        check("disabled" in disabled_status["ExecutionStatus"]["String"].lower() and
              "automatic execution OFF" in disabled_status["Status"]["String"],
              "master guard disables callbacks and reports OFF")
        time.sleep(2.4)
        check(controls("ExecutionStatus")["ExecutionStatus"]["String"] ==
              disabled_status["ExecutionStatus"]["String"],
              "master guard blocks repeat callbacks")

        serialized = current_schedule_text()
        check("\"_" not in serialized, "runtime-only execution state is absent from ScheduleData")
        health = controls("script.status", "script.error.count")
        check(health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0,
              "plugin remains OK with zero script errors")

    finally:
        set_value("AutomaticExecutionEnabled", False, delay=0.3)
        set_value("ScheduleData", original_schedule, delay=0.4)
        set_value("TestDateTime", original_test_time, delay=0.2)
        restored = (
            current_schedule_text() == original_schedule
            and controls("TestDateTime")["TestDateTime"]["String"] == original_test_time
            and controls("AutomaticExecutionEnabled")["AutomaticExecutionEnabled"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} persistent execution-test controls restored")
        if not restored:
            raise AssertionError("failed to restore persistent execution-test controls")

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
