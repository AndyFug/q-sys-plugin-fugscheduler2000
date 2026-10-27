#!/usr/bin/env python3
"""Validate Scheduler plan creation, polling, deletion, and unaffected-plan preservation."""

from __future__ import annotations

import json
import subprocess
import time
from copy import deepcopy
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
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


def press(name: str) -> None:
    set_value(name, True, 0.1)
    set_value(name, False, 0.4)


def status() -> dict:
    press("ResolveTestTime")
    return json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])


def entries(result: dict) -> dict[str, dict]:
    return {item["id"]: item for item in result["schedulers"]}


def temporary_scheduler() -> dict:
    day_id = "qrc-plan-delete-day"
    return {
        "id": "qrc-plan-delete-scheduler",
        "label": "Plan Deletion QRC Test",
        "enabled": False,
        "paused": False,
        "defaultWeekPatternId": "qrc-plan-delete-week",
        "dayPatterns": [{
            "id": day_id,
            "label": "Plan Deletion Day",
            "events": [{
                "id": "qrc-plan-delete-event",
                "label": "Plan Deletion Event",
                "time": "12:00",
                "actions": [{
                    "actionId": "Callback1", "enabled": True, "oneShot": False,
                    "fireOnStartup": False, "fireOnResume": False,
                }],
            }],
        }],
        "weekPatterns": [{
            "id": "qrc-plan-delete-week",
            "label": "Plan Deletion Week",
            "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": [],
    }


def main() -> None:
    ensure_design("preflight")
    initial = controls(
        "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
        "GlobalSchedulerStatus", "script.status", "script.error.count",
    )
    provider = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution is off before plan lifecycle testing")
    check(initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0
          and provider["script.status"]["String"] == "OK" and provider["script.error.count"]["Value"] == 0,
          "plugin and runtime provider start healthy")

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    original_model = json.loads(original_schedule)
    if not original_model.get("schedulers"):
        raise AssertionError("plan lifecycle test requires at least one existing Scheduler")
    preserved_id = original_model["schedulers"][0]["id"]
    temporary_id = "qrc-plan-delete-scheduler"

    try:
        set_value("TestDateTime", "", 0.3)
        time.sleep(1.3)
        before = status()
        before_entries = entries(before)
        preserved_before = before_entries[preserved_id]["execution"]
        check(before["performance"]["schedulerCount"] == len(original_model["schedulers"]),
              "baseline plan count matches the persisted Scheduler count")
        check(preserved_before["performance"]["pollCount"] > 0, "preserved Scheduler timer is polling before mutation")

        added_model = deepcopy(original_model)
        added_model["revision"] = int(added_model.get("revision", 0)) + 1
        added_model["schedulers"].append(temporary_scheduler())
        ensure_design("add mutation")
        set_value("ScheduleData", json.dumps(added_model, separators=(",", ":")), 0.8)
        time.sleep(2.3)
        after_add = status()
        after_add_entries = entries(after_add)
        temporary_execution = after_add_entries[temporary_id]["execution"]
        preserved_after_add = after_add_entries[preserved_id]["execution"]
        check(after_add["performance"]["schedulerCount"] == len(original_model["schedulers"]) + 1,
              "adding a Scheduler creates exactly one runtime plan")
        check(temporary_execution["performance"]["pollCount"] > 0, "new Scheduler timer polls independently")
        check(preserved_after_add["planGeneration"] == preserved_before["planGeneration"],
              "adding a Scheduler preserves an unaffected plan generation")
        check(preserved_after_add["timerPhaseSeconds"] == preserved_before["timerPhaseSeconds"],
              "adding a Scheduler preserves an unaffected timer phase")
        check(preserved_after_add["performance"]["pollCount"] > preserved_before["performance"]["pollCount"],
              "unaffected Scheduler timer continues polling after addition")

        removed_model = deepcopy(added_model)
        removed_model["revision"] += 1
        removed_model["schedulers"] = [item for item in removed_model["schedulers"] if item["id"] != temporary_id]
        ensure_design("delete mutation")
        set_value("ScheduleData", json.dumps(removed_model, separators=(",", ":")), 0.8)
        time.sleep(2.5)
        after_delete = status()
        after_delete_entries = entries(after_delete)
        preserved_after_delete = after_delete_entries[preserved_id]["execution"]
        check(temporary_id not in after_delete_entries, "deleted Scheduler plan remains absent after multiple former timer periods")
        check(after_delete["performance"]["schedulerCount"] == len(original_model["schedulers"]),
              "deleting a Scheduler removes exactly one runtime plan")
        check(preserved_after_delete["planGeneration"] == preserved_before["planGeneration"],
              "deleting another Scheduler preserves the unaffected plan generation")
        check(preserved_after_delete["timerPhaseSeconds"] == preserved_before["timerPhaseSeconds"],
              "deleting another Scheduler preserves the unaffected timer phase")
        check(preserved_after_delete["performance"]["pollCount"] > preserved_after_add["performance"]["pollCount"],
              "unaffected Scheduler timer continues polling after deletion")
        check('\"_' not in controls("ScheduleData")["ScheduleData"]["String"],
              "runtime plan and timer state is absent from ScheduleData")
    finally:
        ensure_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ScheduleData", original_schedule, 0.8)
        set_value("TestDateTime", original_test_time, 0.3)
        final = controls(
            "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
            "script.status", "script.error.count",
        )
        final_provider = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        restored = (final["ScheduleData"]["String"] == original_schedule
                    and final["TestDateTime"]["String"] == original_test_time
                    and final["AutomaticExecutionEnabled"]["Value"] < 0.5
                    and final["ResolveTestTime"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} plan lifecycle fixtures restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore plan lifecycle fixtures")
        check(final["script.status"]["String"] == "OK" and final["script.error.count"]["Value"] == 0
              and final_provider["script.status"]["String"] == "OK"
              and final_provider["script.error.count"]["Value"] == 0,
              "plugin and runtime provider finish healthy after plan lifecycle testing")

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
