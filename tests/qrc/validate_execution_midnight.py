#!/usr/bin/env python3
"""Exercise a genuine live Scheduler cursor transition across local midnight.

This test intentionally waits for the next real local midnight. It never changes the
host, emulator, or Core clock and restores all changed persistent controls.
"""

from __future__ import annotations

import json
import signal
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


# Convert normal interrupt/termination signals into exceptions so fixture cleanup runs.
def interrupt_handler(signum: int, _frame: object) -> None:
    raise InterruptedError(f"midnight acceptance interrupted by signal {signum}")


signal.signal(signal.SIGINT, interrupt_handler)
signal.signal(signal.SIGTERM, interrupt_handler)


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
    print(f"PASS {len(assertions):02d}: {label}", flush=True)


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


def qsys_now() -> datetime:
    set_value("TestDateTime", "", 0.2)
    press("ResolveTestTime")
    raw = controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"]
    return datetime.strptime(json.loads(raw)["generatedAt"], "%Y-%m-%d %H:%M:%S")


def action(action_id: str) -> dict:
    return {
        "actionId": action_id,
        "enabled": True,
        "oneShot": True,
        "fireOnStartup": False,
        "fireOnResume": False,
    }


def fixture(scheduler_id: str) -> dict:
    day_id = scheduler_id + "-day"
    return {
        "id": scheduler_id,
        "label": "Live Midnight QRC Test",
        "enabled": True,
        "paused": False,
        "defaultWeekPatternId": scheduler_id + "-week",
        "dayPatterns": [{
            "id": day_id,
            "label": "Live Midnight Day",
            "events": [
                {"id": scheduler_id + "-before", "label": "Before Midnight", "time": "23:59",
                 "actions": [action("Callback1")]},
                {"id": scheduler_id + "-midnight", "label": "At Midnight", "time": "00:00",
                 "actions": [action("Callback1"), action("Callback2")]},
                {"id": scheduler_id + "-after", "label": "After Midnight", "time": "00:01",
                 "actions": [action("Callback2")]},
            ],
        }],
        "weekPatterns": [{
            "id": scheduler_id + "-week",
            "label": "Live Midnight Week",
            "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": [],
    }


def main() -> None:
    ensure_design("preflight")
    initial = controls(
        "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
        "GlobalSchedulerStatus", "DiagnosticLog", "script.status", "script.error.count",
    )
    runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    provider = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution is off before midnight testing")
    check(initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0
          and runtime["script.status"]["String"] == "OK" and runtime["script.error.count"]["Value"] == 0
          and provider["script.status"]["String"] == "OK" and provider["script.error.count"]["Value"] == 0,
          "plugin, runtime provider, and Action Provider start healthy")

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    scheduler_id = "qrc-live-midnight-" + datetime.now().strftime("%Y%m%d%H%M%S")

    try:
        now = qsys_now()
        midnight = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        wait_seconds = (midnight - now).total_seconds()
        if not (20 <= wait_seconds <= 1500):
            raise AssertionError(f"live midnight test must begin 20 seconds to 25 minutes before midnight; now={now}")

        model = json.loads(original_schedule)
        staged = deepcopy(model)
        staged["revision"] = int(staged.get("revision", 0)) + 1
        for scheduler in staged["schedulers"]:
            scheduler["enabled"] = False
        staged["schedulers"].append(fixture(scheduler_id))
        ensure_design("fixture mutation")
        set_value("ScheduleData", json.dumps(staged, separators=(",", ":")), 1.0)
        time.sleep(2.0)
        prepared = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        prepared_entry = {item["id"]: item for item in prepared["schedulers"]}[scheduler_id]
        check(prepared_entry["execution"]["performance"]["pollCount"] > 0,
              "midnight Scheduler timer is polling before arming")
        check(prepared_entry["currentEvent"]["id"] == scheduler_id + "-after",
              "pre-midnight Current is the prior date's final Event")
        check(prepared_entry["nextEvent"]["id"] == scheduler_id + "-before",
              "pre-midnight Next is the same date's 23:59 Event")

        set_value("AutomaticExecutionEnabled", True, 0.5)
        target = midnight + timedelta(seconds=5)
        print(f"WAIT: observing genuine midnight transition until {target:%Y-%m-%d %H:%M:%S} (~{(target-now).total_seconds():.0f}s)",
              flush=True)
        while True:
            remaining = (target - datetime.now()).total_seconds()
            if remaining <= 0:
                break
            time.sleep(min(30, max(1, remaining)))
            health = controls("script.status", "script.error.count")
            if health["script.status"]["String"] != "OK" or health["script.error.count"]["Value"] != 0:
                raise AssertionError("plugin became unhealthy while waiting for midnight")
            print(f"WAIT: {max(0, int(remaining))}s remaining", flush=True)

        ensure_design("post-midnight")
        post = controls("GlobalSchedulerStatus", "DiagnosticLog", "script.status", "script.error.count")
        global_status = json.loads(post["GlobalSchedulerStatus"]["String"])
        entry = {item["id"]: item for item in global_status["schedulers"]}[scheduler_id]
        expected_date = midnight.strftime("%Y-%m-%d")
        prior_date = (midnight - timedelta(days=1)).strftime("%Y-%m-%d")
        check(entry["previousEvent"]["id"] == scheduler_id + "-before", "Previous advances to the 23:59 Event")
        check(entry["previousEvent"]["date"] == prior_date, "Previous retains the pre-midnight occurrence date")
        check(entry["currentEvent"]["id"] == scheduler_id + "-midnight", "Current advances to the 00:00 Event")
        check(entry["currentEvent"]["date"] == expected_date, "Current retains the new date after midnight")
        check(entry["nextEvent"]["id"] == scheduler_id + "-after", "Next extends into the new date's 00:01 Event")
        check(entry["nextEvent"]["date"] == expected_date, "Next retains the new date occurrence identity")

        log = post["DiagnosticLog"]["String"]
        prefix = f'Scheduler "Live Midnight QRC Test" [{scheduler_id}] | '
        fragments = [
            prefix + f'Event "Before Midnight" [{scheduler_id}-before] | Action "Callback 1" [Callback1]',
            prefix + f'Event "At Midnight" [{scheduler_id}-midnight] | Action "Callback 1" [Callback1]',
            prefix + f'Event "At Midnight" [{scheduler_id}-midnight] | Action "Callback 2" [Callback2]',
        ]
        positions = [log.find(fragment) for fragment in fragments]
        check(all(position >= 0 for position in positions), "pre-midnight and midnight callbacks all execute")
        check(positions == sorted(positions), "callbacks execute in occurrence and persisted Action order across midnight")
        check(post["script.status"]["String"] == "OK" and post["script.error.count"]["Value"] == 0,
              "plugin remains healthy after the live midnight transition")
    finally:
        ensure_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ScheduleData", original_schedule, 0.8)
        set_value("TestDateTime", original_test_time, 0.3)
        final = controls(
            "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled", "ResolveTestTime",
            "script.status", "script.error.count",
        )
        final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        final_provider = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
        restored = (final["ScheduleData"]["String"] == original_schedule
                    and final["TestDateTime"]["String"] == original_test_time
                    and final["AutomaticExecutionEnabled"]["Value"] < 0.5
                    and final["ResolveTestTime"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} midnight fixtures restored byte-for-byte", flush=True)
        if not restored:
            raise AssertionError("failed to restore midnight fixtures")
        check(final["script.status"]["String"] == "OK" and final["script.error.count"]["Value"] == 0
              and final_runtime["script.status"]["String"] == "OK" and final_runtime["script.error.count"]["Value"] == 0
              and final_provider["script.status"]["String"] == "OK" and final_provider["script.error.count"]["Value"] == 0,
              "all three scripts finish healthy after midnight testing")

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
