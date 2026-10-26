#!/usr/bin/env python3
"""Exercise centralized logging preferences and basic destination filtering through QRC."""

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
    command = ["node", str(QRC), "--host", HOST, *args]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.2) -> None:
    qrc("set", COMPONENT, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def press(name: str) -> None:
    set_value(name, True)
    set_value(name, False)


def choice(identifier: int, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def choice_id(control: dict) -> int:
    return int(json.loads(control["String"])["Id"])


def history_lines() -> list[str]:
    history = controls("log.history")["log.history"]
    return history.get("Strings", [])


def matching_history(fragment: str) -> int:
    return sum(fragment in line for line in history_lines())


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def main() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active", "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")

    required = [
        "DebugLogLevel", "EventLogLevel", "PreferencesStatus", "DiagnosticLog",
        "TestDateTime", "ResolveTestTime", "ReloadActions", "ScheduleData",
        "AutomaticExecutionEnabled", "script.status", "script.error.count", "log.history",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "logging preference and diagnostic controls exist")
    check(initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0,
          "plugin script is OK with zero errors")
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(runtime_health["script.status"]["String"] == "OK" and
          runtime_health["script.error.count"]["Value"] == 0,
          "runtime provider is OK with zero errors")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5,
          "automatic execution guard is off before logging tests")

    original_debug = initial["DebugLogLevel"]["String"]
    original_event = initial["EventLogLevel"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    original_schedule = initial["ScheduleData"]["String"]
    restored = False

    try:
        expected_ids = {0, 3, 6, 7}
        debug_choices = {
            int(json.loads(item)["Id"]) if isinstance(item, str) else int(item["Id"])
            for item in initial["DebugLogLevel"].get("Choices", [])
        }
        event_choices = {
            int(json.loads(item)["Id"]) if isinstance(item, str) else int(item["Id"])
            for item in initial["EventLogLevel"].get("Choices", [])
        }
        check(debug_choices == expected_ids and event_choices == expected_ids,
              "both destinations expose normalized numeric log level IDs")

        set_value("DebugLogLevel", choice(0, "Off"))
        set_value("EventLogLevel", choice(0, "Off"))
        levels = controls("DebugLogLevel", "EventLogLevel", "PreferencesStatus")
        check(choice_id(levels["DebugLogLevel"]) == 0 and choice_id(levels["EventLogLevel"]) == 0,
              "Off is retained independently for both destinations")

        error_fragment = "[ERROR] Test date/time error: expected YYYY-MM-DD HH:MM"
        before_off = matching_history(error_fragment)
        set_value("TestDateTime", "logging-test-invalid")
        press("ResolveTestTime")
        after_off = matching_history(error_fragment)
        diagnostic = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        check(after_off == before_off, "Debug Output Off suppresses an Error message")
        check(error_fragment in diagnostic, "DiagnosticLog records Error while external destinations are Off")
        check(len(diagnostic) <= 12000, "DiagnosticLog remains within its 12,000-character retention bound")

        set_value("DebugLogLevel", choice(3, "Error"))
        before_error = matching_history(error_fragment)
        press("ResolveTestTime")
        after_error = matching_history(error_fragment)
        check(after_error > before_error, "Debug Output Error level permits Error messages")

        info_fragment = "[INFO] Loaded Action Registry with"
        before_info_suppressed = matching_history(info_fragment)
        press("ReloadActions")
        after_info_suppressed = matching_history(info_fragment)
        check(after_info_suppressed == before_info_suppressed,
              "Debug Output Error level suppresses Info messages")

        set_value("DebugLogLevel", choice(6, "Info"))
        before_info = matching_history(info_fragment)
        press("ReloadActions")
        after_info = matching_history(info_fragment)
        check(after_info > before_info, "Debug Output Info level permits Info messages")

        set_value("EventLogLevel", choice(6, "Info"))
        event_level = controls("EventLogLevel", "PreferencesStatus")
        check(choice_id(event_level["EventLogLevel"]) == 6 and
              "Event Log level: Info" in event_level["PreferencesStatus"]["String"],
              "Event Log handler accepts and reports the normalized Info level")

        diagnostic = controls("DiagnosticLog")["DiagnosticLog"]["String"]
        check("[INFO] Loaded Action Registry with" in diagnostic,
              "DiagnosticLog records centralized Info messages")
        check(initial["ScheduleData"]["String"] == controls("ScheduleData")["ScheduleData"]["String"],
              "logging preference and handler tests do not change ScheduleData")

    finally:
        set_value("AutomaticExecutionEnabled", False)
        set_value("DebugLogLevel", original_debug)
        set_value("EventLogLevel", original_event)
        set_value("TestDateTime", original_test_time)
        restored_controls = controls(
            "DebugLogLevel", "EventLogLevel", "TestDateTime", "ScheduleData", "AutomaticExecutionEnabled"
        )
        restored = (
            restored_controls["DebugLogLevel"]["String"] == original_debug
            and restored_controls["EventLogLevel"]["String"] == original_event
            and restored_controls["TestDateTime"]["String"] == original_test_time
            and restored_controls["ScheduleData"]["String"] == original_schedule
            and restored_controls["AutomaticExecutionEnabled"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} logging preferences and scheduler controls restored")
        if not restored:
            raise AssertionError("failed to restore logging preferences or scheduler controls")

    final_plugin = controls("script.status", "script.error.count")
    final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(final_plugin["script.status"]["String"] == "OK" and
          final_plugin["script.error.count"]["Value"] == 0 and
          final_runtime["script.status"]["String"] == "OK" and
          final_runtime["script.error.count"]["Value"] == 0,
          "plugin and runtime provider finish OK with zero errors")
    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
