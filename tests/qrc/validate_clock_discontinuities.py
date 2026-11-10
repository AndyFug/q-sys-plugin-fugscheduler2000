#!/usr/bin/env python3
"""Validate one-shot tolerance, persistent receipts, and clock-discontinuity reconciliation through QRC."""

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
    command = ["node", str(QRC), "--host", HOST, *args]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


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


def set_value(name: str, value: object, delay: float = 0.2, component: str = COMPONENT) -> None:
    qrc("set", component, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def history_count(fragment: str) -> int:
    history = controls("log.history")["log.history"].get("Strings", [])
    return sum(fragment in line for line in history)


def provider_source() -> str:
    return """-- Temporary safe clock-discontinuity acceptance provider.
function GetFugSchedulerActions()
  return {
    {id = "ClockStateBase", label = "Clock State Base", callback = function() print("CLOCK TEST STATE BASE") end},
    {id = "ClockStateB", label = "Clock State B", callback = function() print("CLOCK TEST STATE B") end},
    {id = "ClockStateC", label = "Clock State C", callback = function() print("CLOCK TEST STATE C") end},
    {id = "ClockShotA", label = "Clock Shot A", callback = function() print("CLOCK TEST SHOT A") end},
    {id = "ClockShotB", label = "Clock Shot B", callback = function() print("CLOCK TEST SHOT B") end},
    {id = "ClockShotC", label = "Clock Shot C", callback = function() print("CLOCK TEST SHOT C") end}
  }
end
"""


def event(event_id: str, label: str, when: datetime, actions: list[dict]) -> dict:
    return {
        "id": event_id,
        "label": label,
        "time": when.strftime("%H:%M"),
        "actions": actions,
    }


def state_action(action_id: str) -> dict:
    return {
        "actionId": action_id,
        "enabled": True,
        "oneShot": False,
        "fireOnStartup": False,
        "fireOnResume": False,
    }


def shot_action(action_id: str) -> dict:
    return {
        "actionId": action_id,
        "enabled": True,
        "oneShot": True,
        "fireOnStartup": False,
        "fireOnResume": False,
    }


def main() -> None:
    ensure_expected_design("preflight")
    required = [
        "AutomaticExecutionEnabled", "ScheduleData", "TestDateTime", "DebugLogLevel", "EventLogLevel",
        "OneShotLateToleranceSeconds", "OneShotExecutionLedger", "ExecutionTestClockOffsetSeconds",
        "GlobalSchedulerSlotStatus", "ExecutionStatus", "ActionSource", "log.history",
        "script.status", "script.error.count",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "clock tolerance, ledger, and test-clock controls exist")
    check(
        initial["script.status"]["String"] == "OK" and initial["script.error.count"]["Value"] == 0,
        "plugin script is OK with zero errors",
    )
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(
        runtime_health["script.status"]["String"] == "OK"
        and runtime_health["script.error.count"]["Value"] == 0,
        "runtime provider is OK with zero errors",
    )
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable is off before testing")
    check(int(initial["OneShotLateToleranceSeconds"]["Value"]) == 0, "default one-shot tolerance is zero")

    provider_initial = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
    original = {
        "ScheduleData": initial["ScheduleData"]["String"],
        "TestDateTime": initial["TestDateTime"]["String"],
        "DebugLogLevel": initial["DebugLogLevel"]["String"],
        "EventLogLevel": initial["EventLogLevel"]["String"],
        "OneShotLateToleranceSeconds": initial["OneShotLateToleranceSeconds"]["Value"],
        "OneShotExecutionLedger": initial["OneShotExecutionLedger"]["String"],
        "ActionSource": initial["ActionSource"]["String"],
        "ProviderSource": provider_initial["code"]["String"],
    }

    try:
        set_value("code", provider_source(), delay=1.0, component=ACTION_PROVIDER)
        provider_after = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
        check(
            provider_after["script.status"]["String"] == "OK"
            and provider_after["script.error.count"]["Value"] == 0,
            "temporary clock-test Action Provider is healthy",
        )

        set_value("TestDateTime", "")
        set_value("DebugLogLevel", json.dumps({"Text": "Debug", "Id": 7}, separators=(",", ":")))
        set_value("EventLogLevel", json.dumps({"Text": "Off", "Id": 0}, separators=(",", ":")))
        set_value("OneShotLateToleranceSeconds", 20000)
        check(int(controls("OneShotLateToleranceSeconds")["OneShotLateToleranceSeconds"]["Value"]) == 14400,
              "one-shot tolerance is capped at four hours")
        set_value("OneShotLateToleranceSeconds", 300)
        set_value("ExecutionTestClockOffsetSeconds", 0)

        live = json.loads(controls("GlobalSchedulerSlotStatus")["GlobalSchedulerSlotStatus"]["String"])
        now = datetime.strptime(live["resolvedFor"], "%Y-%m-%d %H:%M:%S")
        minute = now.replace(second=0)
        if (minute + timedelta(minutes=7)).date() != minute.date():
            raise RuntimeError("run this acceptance test at least seven minutes before local midnight")
        scheduler_id = "qrc-clock-discontinuity"
        day_id = "qrc-clock-day"
        week_id = "qrc-clock-week"
        events = [
            event("clock-base", "Clock Base", minute - timedelta(minutes=1), [state_action("ClockStateBase")]),
            event("clock-a", "Clock A", minute + timedelta(minutes=2), [shot_action("ClockShotA")]),
            event("clock-b", "Clock B", minute + timedelta(minutes=3), [
                state_action("ClockStateB"), shot_action("ClockShotB")
            ]),
            event("clock-c", "Clock C", minute + timedelta(minutes=6), [
                state_action("ClockStateC"), shot_action("ClockShotC")
            ]),
        ]
        scheduler = {
            "id": scheduler_id,
            "label": "Clock Discontinuity Test",
            "defaultWeekPatternId": week_id,
            "dayPatterns": [{"id": day_id, "label": "Clock Test Day", "events": events}],
            "weekPatterns": [{
                "id": week_id,
                "label": "Clock Test Week",
                "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
            }],
            "overrides": [],
        }
        model = json.loads(original["ScheduleData"])
        model["schemaVersion"] = 2
        model["schedulers"] = [scheduler]
        slot_count = max(1, len(model.get("schedulerSlots", [])))
        model["schedulerSlots"] = [
            {"slot": 1, "schedulerId": scheduler_id, "enabled": True, "paused": False},
            *[{"slot": number, "enabled": False, "paused": False} for number in range(2, slot_count + 1)],
        ]
        set_value("ScheduleData", json.dumps(model, indent=2), delay=1.5)
        set_value("AutomaticExecutionEnabled", True, delay=1.5)

        shot_a_before = history_count("CLOCK TEST SHOT A")
        shot_b_before = history_count("CLOCK TEST SHOT B")
        state_b_before = history_count("CLOCK TEST STATE B")
        set_value("ExecutionTestClockOffsetSeconds", 240, delay=2.0)
        check(history_count("CLOCK TEST SHOT A") == shot_a_before, "older skipped one-shot does not execute")
        check(history_count("CLOCK TEST SHOT B") == shot_b_before + 1, "latest skipped one-shot executes inside tolerance")
        check(history_count("CLOCK TEST STATE B") > state_b_before, "forward jump reconciles the new Current Event state")

        ledger_after_first = json.loads(controls("OneShotExecutionLedger")["OneShotExecutionLedger"]["String"])
        check(len(ledger_after_first["receipts"]) == 1, "one persistent one-shot receipt is recorded")
        aggregate = json.loads(controls("GlobalSchedulerSlotStatus")["GlobalSchedulerSlotStatus"]["String"])
        check(aggregate["oneShotPolicy"]["lateToleranceSeconds"] == 300, "aggregate status reports the tolerance")
        check(aggregate["oneShotPolicy"]["receiptCount"] == 1, "aggregate status reports the receipt count")

        set_value("ExecutionTestClockOffsetSeconds", 0, delay=2.0)
        check("without replaying one-shots" in controls("ExecutionStatus")["ExecutionStatus"]["String"],
              "backward jump reports one-shot replay suppression")
        shot_b_once = history_count("CLOCK TEST SHOT B")
        set_value("ExecutionTestClockOffsetSeconds", 240, delay=2.0)
        check(history_count("CLOCK TEST SHOT B") == shot_b_once,
              "crossing the same occurrence again is suppressed by the ledger")

        set_value("AutomaticExecutionEnabled", False)
        set_value("ExecutionTestClockOffsetSeconds", 0)
        ensure_expected_design("runtime reload")
        qrc("deploy", RUNTIME_PROVIDER, str(ROOT / "src/runtime.lua"))
        time.sleep(2.0)
        set_value("OneShotLateToleranceSeconds", 300)
        set_value("ExecutionTestClockOffsetSeconds", 240, delay=1.0)
        set_value("AutomaticExecutionEnabled", True, delay=2.0)
        check(history_count("CLOCK TEST SHOT B") == shot_b_once,
              "persistent receipt suppresses startup recovery after runtime reload")

        set_value("AutomaticExecutionEnabled", False)
        set_value("ExecutionTestClockOffsetSeconds", 0, delay=1.0)
        set_value("OneShotLateToleranceSeconds", 0)
        set_value("AutomaticExecutionEnabled", True, delay=1.0)
        shot_c_before = history_count("CLOCK TEST SHOT C")
        state_c_before = history_count("CLOCK TEST STATE C")
        set_value("ExecutionTestClockOffsetSeconds", 420, delay=2.0)
        check(history_count("CLOCK TEST SHOT C") == shot_c_before,
              "zero tolerance disables late one-shot recovery")
        check(history_count("CLOCK TEST STATE C") > state_c_before,
              "zero tolerance does not disable stateful clock-jump reconciliation")

    finally:
        set_value("AutomaticExecutionEnabled", False)
        set_value("ExecutionTestClockOffsetSeconds", 0)
        set_value("ScheduleData", original["ScheduleData"], delay=1.0)
        set_value("OneShotExecutionLedger", original["OneShotExecutionLedger"])
        set_value("OneShotLateToleranceSeconds", original["OneShotLateToleranceSeconds"])
        set_value("DebugLogLevel", original["DebugLogLevel"])
        set_value("EventLogLevel", original["EventLogLevel"])
        set_value("TestDateTime", original["TestDateTime"])
        set_value("code", original["ProviderSource"], delay=1.0, component=ACTION_PROVIDER)
        set_value("ActionSource", original["ActionSource"], delay=0.5)

        restored = controls(
            "AutomaticExecutionEnabled", "ExecutionTestClockOffsetSeconds", "ScheduleData",
            "OneShotExecutionLedger", "OneShotLateToleranceSeconds", "DebugLogLevel", "EventLogLevel",
            "ActionSource", "TestDateTime", "script.status", "script.error.count",
        )
        check(restored["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable finishes off")
        check(int(restored["ExecutionTestClockOffsetSeconds"]["Value"]) == 0, "execution test clock finishes at zero")
        check(restored["ScheduleData"]["String"] == original["ScheduleData"], "ScheduleData restored byte-for-byte")
        check(restored["OneShotExecutionLedger"]["String"] == original["OneShotExecutionLedger"],
              "one-shot ledger restored byte-for-byte")
        check(restored["OneShotLateToleranceSeconds"]["Value"] == original["OneShotLateToleranceSeconds"],
              "one-shot tolerance restored")
        check(restored["DebugLogLevel"]["String"] == original["DebugLogLevel"], "Debug Output preference restored")
        check(restored["EventLogLevel"]["String"] == original["EventLogLevel"], "Event Log preference restored")
        check(restored["TestDateTime"]["String"] == original["TestDateTime"], "TestDateTime restored byte-for-byte")
        check(restored["ActionSource"]["String"] == original["ActionSource"], "ActionSource restored byte-for-byte")
        check(
            restored["script.status"]["String"] == "OK" and restored["script.error.count"]["Value"] == 0,
            "plugin finishes OK with zero errors",
        )
        runtime_final = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        provider_final = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
        check(provider_final["code"]["String"] == original["ProviderSource"],
              "Action Provider source restored byte-for-byte")
        check(
            runtime_final["script.status"]["String"] == "OK"
            and runtime_final["script.error.count"]["Value"] == 0
            and provider_final["script.status"]["String"] == "OK"
            and provider_final["script.error.count"]["Value"] == 0,
            "runtime and Action providers finish OK with zero errors",
        )

    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
