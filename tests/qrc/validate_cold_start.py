#!/usr/bin/env python3
"""Validate cold startup without decoding a production-sized Saved Configuration catalogue."""

from __future__ import annotations

import json
import socket
import subprocess
import time
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
assertions: list[str] = []


def qrc(*args: str) -> object:
    result = subprocess.run(["node", str(QRC), "--host", HOST, *args], cwd=ROOT,
                            text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def controls(*names: str) -> dict[str, dict]:
    result = qrc("get", COMPONENT, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.7) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def set_large_text(name: str, value: str, delay: float = 0.7) -> None:
    """Set large Text values directly over QRC without an OS command-line size limit."""
    request_id = 9001
    request = {
        "jsonrpc": "2.0",
        "method": "Component.Set",
        "params": {"Name": COMPONENT, "Controls": [{"Name": name, "Value": value}]},
        "id": request_id,
    }
    with socket.create_connection((HOST, 1710), timeout=10) as connection:
        connection.sendall(json.dumps(request, separators=(",", ":")).encode("utf-8") + b"\0")
        connection.settimeout(15)
        buffer = b""
        while True:
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError("QRC connection closed before the large Text write response")
            buffer += chunk
            while b"\0" in buffer:
                message, buffer = buffer.split(b"\0", 1)
                if not message:
                    continue
                decoded = json.loads(message.decode("utf-8"))
                if decoded.get("id") == request_id:
                    if "error" in decoded:
                        raise RuntimeError(str(decoded["error"]))
                    time.sleep(delay)
                    return


def press(name: str, delay: float = 0.7) -> None:
    set_value(name, True, 0.15)
    set_value(name, False, delay)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] in {"fugscheduler_test", "fugscheduler2000_test"},
          "expected FugScheduler test design is active")


def main() -> None:
    ensure_design()
    initial = controls(
        "ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupStatus",
        "ScheduleStatus", "GlobalSchedulerSlotStatus", "AssignedSchedulerSlotCount",
        "AutomaticExecutionEnabled", "script.status", "script.error.count", "reload",
    )
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5,
          "Master Enable is off before cold-start validation")
    original_schedule = initial["ScheduleData"]["String"]
    original_catalog = initial["ConfigurationBackupCatalog"]["String"]
    schedule = json.loads(original_schedule)

    configurations = []
    schedule_json = json.dumps(schedule, separators=(",", ":"))
    padded_schedule_json = schedule_json + (" " * max(0, 20_000 - len(schedule_json)))
    for index in range(1, 11):
        configurations.append({
            "id": f"00000000-0000-4000-8000-{index:012d}",
            "name": f"Cold Start Saved Configuration {index}",
            "savedAt": "2026-11-10T20:00:00",
            "scheduleJson": padded_schedule_json,
        })
    large_catalog = json.dumps({"schemaVersion": 2, "configurations": configurations}, separators=(",", ":"))
    check(len(large_catalog) >= 190_000, "ten-backup opaque catalogue is production-sized")

    try:
        set_large_text("ConfigurationBackupCatalog", large_catalog, 0.8)
        before_reload = controls("script.status", "script.error.count", "ScheduleStatus",
                                 "ConfigurationBackupStatus")
        check(before_reload["script.status"]["String"] == "OK" and
              before_reload["script.error.count"]["Value"] == 0 and
              "10/10" in before_reload["ConfigurationBackupStatus"]["String"],
              "automatic metadata refresh handles a large opaque catalogue without schedule parsing")

        press("reload", 0.3)
        time.sleep(6.0)
        started = controls(
            "script.status", "script.error.count", "ScheduleStatus", "ConfigurationBackupStatus",
            "GlobalSchedulerSlotStatus", "AssignedSchedulerSlotCount", "ConfigurationBackupCatalog",
        )
        check(started["script.status"]["String"] == "OK" and started["script.error.count"]["Value"] == 0,
              "cold runtime reload finishes OK with zero script errors")
        check("Loaded" in started["ScheduleStatus"]["String"],
              "active ScheduleData validates and installs during phased startup")
        check(started["GlobalSchedulerSlotStatus"]["String"] not in {"", "{}"},
              "aggregate live Scheduler Slot status is published after cold startup")
        check("10/10" in started["ConfigurationBackupStatus"]["String"],
              "deferred startup refresh repopulates all Saved Configuration metadata")
        check(started["ConfigurationBackupCatalog"]["String"] == large_catalog,
              "large opaque catalogue is preserved byte-for-byte without decoding or rewriting")
    finally:
        set_value("AutomaticExecutionEnabled", False, 0.2)
        set_value("ConfigurationBackupCatalog", original_catalog, 0.8)
        final = controls("ScheduleData", "ConfigurationBackupCatalog", "AutomaticExecutionEnabled")
        restored = (final["ScheduleData"]["String"] == original_schedule and
                    final["ConfigurationBackupCatalog"]["String"] == original_catalog and
                    final["AutomaticExecutionEnabled"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} cold-start persistent controls restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore cold-start test controls")

    print(f"SUCCESS: {len(assertions)} cold-start assertions passed")


if __name__ == "__main__":
    main()
