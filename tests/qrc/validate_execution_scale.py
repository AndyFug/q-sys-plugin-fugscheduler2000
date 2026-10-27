#!/usr/bin/env python3
"""Measure compiled Scheduler-plan polling at synthetic safe scales through QRC."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import time
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
SCALES = [(5, 10), (20, 20)]
if os.environ.get("FUGSCHEDULER_SCALE_50") == "1":
    SCALES.append((50, 20))

assertions: list[str] = []


def qrc(*args: str) -> object:
    result = subprocess.run(
        ["node", str(QRC), "--host", HOST, *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
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
    check(
        status["Platform"] == "Emulator"
        and status["State"] == "Active"
        and status.get("IsEmulator") is True,
        f"{label}: expected active Emulator",
    )
    check(status["DesignName"] == "fugscheduler2000_test", f"{label}: expected design is active")


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.2) -> None:
    encoded = json.dumps(value, separators=(",", ":"))
    if len(encoded) < 100_000:
        qrc("set", COMPONENT, name, encoded)
    else:
        request_id = 9001
        request = {
            "jsonrpc": "2.0",
            "method": "Component.Set",
            "params": {"Name": COMPONENT, "Controls": [{"Name": name, "Value": value}]},
            "id": request_id,
        }
        with socket.create_connection((HOST, 1710), timeout=10) as connection:
            connection.sendall(json.dumps(request, separators=(",", ":")).encode() + b"\0")
            buffer = b""
            while True:
                chunk = connection.recv(65536)
                if not chunk:
                    raise RuntimeError("QRC closed during large Component.Set")
                buffer += chunk
                while b"\0" in buffer:
                    frame, buffer = buffer.split(b"\0", 1)
                    if not frame:
                        continue
                    response = json.loads(frame)
                    if response.get("id") == request_id:
                        if "error" in response:
                            raise RuntimeError(json.dumps(response["error"]))
                        break
                else:
                    continue
                break
    time.sleep(delay)


def press(name: str) -> None:
    set_value(name, True, 0.1)
    set_value(name, False, 0.2)


def synthetic_model(scheduler_count: int, event_count: int) -> dict:
    schedulers = []
    weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for scheduler_index in range(scheduler_count):
        scheduler_id = f"scale-scheduler-{scheduler_index + 1:03d}"
        day_id = f"scale-day-{scheduler_index + 1:03d}"
        week_id = f"scale-week-{scheduler_index + 1:03d}"
        events = []
        for event_index in range(event_count):
            minutes = (event_index * 61) % 1440
            events.append({
                "id": f"scale-event-{scheduler_index + 1:03d}-{event_index + 1:03d}",
                "label": f"Scale Event {event_index + 1}",
                "time": f"{minutes // 60:02d}:{minutes % 60:02d}",
                "actions": [{
                    "actionId": "Callback1",
                    "enabled": True,
                    "oneShot": False,
                    "fireOnStartup": False,
                    "fireOnResume": False,
                }],
            })
        schedulers.append({
            "id": scheduler_id,
            "label": f"Scale Scheduler {scheduler_index + 1}",
            "enabled": False,
            "paused": False,
            "defaultWeekPatternId": week_id,
            "dayPatterns": [{"id": day_id, "label": "Scale Day", "events": events}],
            "weekPatterns": [{
                "id": week_id,
                "label": "Scale Week",
                "days": {weekday: day_id for weekday in weekdays},
            }],
            "overrides": [],
        })
    return {"schemaVersion": 1, "revision": 1, "schedulers": schedulers}


def main() -> None:
    ensure_expected_design("preflight")
    initial = controls(
        "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled",
        "GlobalSchedulerStatus", "ResolveTestTime", "script.status", "script.error.count",
    )
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(
        initial["script.status"]["String"] == "OK"
        and initial["script.error.count"]["Value"] == 0
        and runtime_health["script.status"]["String"] == "OK"
        and runtime_health["script.error.count"]["Value"] == 0,
        "plugin and runtime provider are healthy before scale testing",
    )
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution is off before scale testing")

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    restored = False

    try:
        set_value("TestDateTime", "", 0.2)
        for scheduler_count, event_count in SCALES:
            ensure_expected_design(f"{scheduler_count}x{event_count} mutation")
            model = synthetic_model(scheduler_count, event_count)
            started = time.perf_counter()
            set_value("ScheduleData", json.dumps(model, separators=(",", ":")), 4.0)
            install_seconds = time.perf_counter() - started
            snapshot = controls("GlobalSchedulerStatus", "ScheduleData", "script.status", "script.error.count")
            status = json.loads(snapshot["GlobalSchedulerStatus"]["String"])
            performance = status["performance"]
            phases = [item["execution"]["timerPhaseSeconds"] for item in status["schedulers"]]
            poll_counts = [item["execution"]["performance"]["pollCount"] for item in status["schedulers"]]

            check(performance["schedulerCount"] == scheduler_count, f"{scheduler_count}x{event_count}: Scheduler count matches")
            check(performance["eventCount"] == scheduler_count * event_count, f"{scheduler_count}x{event_count}: Event count matches")
            check(performance["actionCount"] == scheduler_count * event_count, f"{scheduler_count}x{event_count}: Action count matches")
            check(len(set(phases)) == scheduler_count, f"{scheduler_count}x{event_count}: timer phases are unique")
            check(all(count > 0 for count in poll_counts), f"{scheduler_count}x{event_count}: every Scheduler timer polled")
            check(
                snapshot["script.status"]["String"] == "OK"
                and snapshot["script.error.count"]["Value"] == 0,
                f"{scheduler_count}x{event_count}: plugin remains healthy",
            )
            check('"_' not in snapshot["ScheduleData"]["String"], f"{scheduler_count}x{event_count}: runtime state is absent from ScheduleData")
            print(
                "METRIC "
                f"scale={scheduler_count}x{event_count} "
                f"install_seconds={install_seconds:.6f} "
                f"polls={performance['pollCount']} "
                f"avg_poll_seconds={performance['averagePollDurationSeconds']:.9f} "
                f"max_poll_seconds={performance['maximumPollDurationSeconds']:.9f} "
                f"delayed_polls={performance['delayedPollCount']} "
                f"rebuild_seconds={performance['totalPlanRebuildDurationSeconds']:.9f}"
            )
    finally:
        ensure_expected_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ScheduleData", original_schedule, 1.0)
        set_value("TestDateTime", original_test_time, 0.2)
        final = controls(
            "ScheduleData", "TestDateTime", "AutomaticExecutionEnabled",
            "ResolveTestTime", "script.status", "script.error.count",
        )
        final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        restored = (
            final["ScheduleData"]["String"] == original_schedule
            and final["TestDateTime"]["String"] == original_test_time
            and final["AutomaticExecutionEnabled"]["Value"] < 0.5
            and final["ResolveTestTime"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} scale fixtures restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore scale fixtures")
        check(
            final["script.status"]["String"] == "OK"
            and final["script.error.count"]["Value"] == 0
            and final_runtime["script.status"]["String"] == "OK"
            and final_runtime["script.error.count"]["Value"] == 0,
            "plugin and runtime provider finish healthy after scale testing",
        )

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
