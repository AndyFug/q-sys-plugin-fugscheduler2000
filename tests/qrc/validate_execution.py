#!/usr/bin/env python3
"""Exercise guarded Scheduler lifecycle and real scheduled-edge execution through QRC."""

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


def ensure_expected_design(label: str) -> dict:
    status = qrc("status")
    check(
        status["Platform"] == "Emulator"
        and status["State"] == "Active"
        and status.get("IsEmulator") is True,
        f"{label}: expected active Emulator",
    )
    check(status["DesignName"] == "fugscheduler2000_test", f"{label}: expected design is active")
    return status


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.15, component: str = COMPONENT) -> None:
    qrc("set", component, name, json.dumps(value, separators=(",", ":")))
    time.sleep(delay)


def press(name: str) -> None:
    set_value(name, True)
    set_value(name, False)


def choice(identifier: int | str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def current_schedule_text() -> str:
    return controls("ScheduleData")["ScheduleData"]["String"]


def diagnostic_text() -> str:
    return controls("DiagnosticLog")["DiagnosticLog"]["String"]


def count_fragment(text: str, fragment: str) -> int:
    return text.count(fragment)


def provider_source() -> str:
    return """-- Temporary safe FugScheduler execution acceptance provider.
function GetFugSchedulerActions()
  return {
    {
      id = \"Callback1\",
      label = \"Callback 1\",
      callback = function() print(\"FugScheduler Callback 1 executed\") end
    },
    {
      id = \"Callback2\",
      label = \"Callback 2\",
      callback = function() print(\"FugScheduler Callback 2 executed\") end
    },
    {
      id = \"CallbackFail\",
      label = \"Callback Fail\",
      callback = function() error(\"intentional guarded execution test failure\") end
    },
    {
      id = \"CallbackRepeat\",
      label = \"Callback Repeat\",
      callback = function() print(\"FugScheduler repeat callback executed\") end
    },
    {
      id = \"CallbackOneShot\",
      label = \"Callback One Shot\",
      callback = function() print(\"FugScheduler one-shot callback executed\") end
    }
  }
end
"""


def scheduler_fixture(scheduler_id: str, day_id: str, week_id: str, current_time: str) -> dict:
    return {
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
                "time": current_time,
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
    }


def main() -> None:
    ensure_expected_design("preflight")

    required = [
        "AutomaticExecutionEnabled", "ExecutionStatus", "ScheduleData", "TestDateTime", "ResolveTestTime",
        "SchedulerSelect", "SchedulerEditorEnabled", "SchedulerPaused", "EventActionEnabled", "EventActionMode",
        "EventActionFireOnStartup", "EventActionFireOnResume", "EventActionRepeatSeconds",
        "ActionSelect", "RegisteredActionCount", "GlobalSchedulerStatus", "DiagnosticLog", "Status",
        "DebugLogLevel", "EventLogLevel", "ActionSource", "ReloadActions",
        "script.status", "script.error.count",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "execution, logging, and Event Action option controls exist")
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
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution guard is off before testing")

    provider_initial = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
    check(
        provider_initial["script.status"]["String"] == "OK"
        and provider_initial["script.error.count"]["Value"] == 0,
        "Action Provider is OK with zero errors",
    )

    original_schedule = initial["ScheduleData"]["String"]
    original_test_time = initial["TestDateTime"]["String"]
    original_debug = initial["DebugLogLevel"]["String"]
    original_event = initial["EventLogLevel"]["String"]
    original_action_source = initial["ActionSource"]["String"]
    original_provider_source = provider_initial["code"]["String"]
    restored = False

    try:
        ensure_expected_design("provider mutation")
        set_value("code", provider_source(), delay=1.0, component=ACTION_PROVIDER)
        provider_after = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
        check(provider_after["code"]["String"] == provider_source(), "temporary Action Provider source reads back byte-for-byte")
        check(
            provider_after["script.status"]["String"] == "OK"
            and provider_after["script.error.count"]["Value"] == 0,
            "temporary safe Action Provider is OK with zero errors",
        )
        registry = controls("RegisteredActionCount", "ActionSelect", "ActionSource")
        check(int(float(registry["RegisteredActionCount"]["String"])) == 5, "five temporary test Actions are registered")
        check(
            {"Callback1", "Callback2", "CallbackFail", "CallbackRepeat", "CallbackOneShot"}.issubset(
                set(registry["ActionSelect"].get("Choices", []))
            ),
            "success, failure, repeat, and one-shot test Actions are available",
        )

        ensure_expected_design("lifecycle mutation")
        set_value("DebugLogLevel", choice(7, "Debug"))
        set_value("EventLogLevel", choice(0, "Off"))
        set_value("TestDateTime", "")
        press("ResolveTestTime")
        live_status = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        now = datetime.strptime(live_status["resolvedFor"], "%Y-%m-%d %H:%M:%S")
        event_time = (now - timedelta(minutes=1)).strftime("%H:%M")

        model = json.loads(original_schedule)
        # Isolate ExecutionStatus and logging from callbacks belonging to pre-existing Schedulers.
        for existing_scheduler in model["schedulers"]:
            existing_scheduler["enabled"] = False
        scheduler_id = "qrc-execution-test-" + now.strftime("%Y%m%d%H%M%S")
        day_id = "qrc-execution-day"
        week_id = "qrc-execution-week"
        model["schedulers"].append(scheduler_fixture(scheduler_id, day_id, week_id, event_time))
        set_value("ScheduleData", json.dumps(model, indent=2), delay=1.3)
        set_value("SchedulerSelect", choice(scheduler_id, "Execution QRC Test"))
        time.sleep(1.2)
        press("ResolveTestTime")
        plan_status = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        scheduler_entries = {item["id"]: item for item in plan_status["schedulers"]}
        timer_phases = [item["execution"]["timerPhaseSeconds"] for item in plan_status["schedulers"]]
        check(plan_status["performance"]["schedulerCount"] == len(model["schedulers"]), "one runtime plan exists per configured Scheduler")
        check(len(set(timer_phases)) == len(timer_phases), "Scheduler poll timers use distinct staggered phases")
        check(
            all(item["execution"]["performance"]["pollCount"] > 0 for item in plan_status["schedulers"]),
            "independent Scheduler timers have each completed at least one poll",
        )
        check(
            plan_status["performance"]["eventCount"] >= 1
            and plan_status["performance"]["actionCount"] >= 2,
            "runtime performance status publishes Scheduler, Event, and Action counts",
        )
        preserved_scheduler_id = model["schedulers"][0]["id"]
        preserved_generation = scheduler_entries[preserved_scheduler_id]["execution"]["planGeneration"]
        preserved_phase = scheduler_entries[preserved_scheduler_id]["execution"]["timerPhaseSeconds"]

        editor = controls(
            "EventActionEnabled", "EventActionMode", "EventActionFireOnStartup",
            "EventActionFireOnResume", "EventActionRepeatSeconds",
        )
        check(editor["EventActionEnabled"]["Value"] > 0.5, "selected stateful Event Action is enabled")
        check(json.loads(editor["EventActionMode"]["String"])["Id"] == "Stateful", "selected Event Action mode is Stateful")
        check(
            editor["EventActionFireOnStartup"]["Value"] > 0.5
            and editor["EventActionFireOnResume"]["Value"] > 0.5,
            "startup and resume restoration options are visible",
        )
        check(editor["EventActionRepeatSeconds"]["String"] == "2", "repeat interval is visible in the Event Action editor")

        set_value("AutomaticExecutionEnabled", True, delay=1.3)
        startup = controls("ExecutionStatus", "Status")
        check(
            "Callback 1" in startup["ExecutionStatus"]["String"]
            and "startup" in startup["ExecutionStatus"]["String"],
            "startup restores the current stateful Action",
        )
        check("Callback 2" not in startup["ExecutionStatus"]["String"], "startup does not replay the current one-shot Action")
        check("automatic execution ARMED" in startup["Status"]["String"], "aggregate status reports the execution guard as armed")
        startup_log = diagnostic_text()
        check(
            '[INFO] Scheduler "Execution QRC Test"' in startup_log
            and "reason=startup | Executed successfully" in startup_log,
            "initial state restoration is logged at Info with execution context",
        )

        time.sleep(2.4)
        repeat_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in repeat_status and "repeat" in repeat_status, "stateful Action repeats while its Event remains current")
        repeat_log = diagnostic_text()
        check(
            '[DEBUG] Scheduler "Execution QRC Test"' in repeat_log
            and "reason=repeat | Executed successfully" in repeat_log,
            "subsequent repeat execution is logged at Debug with execution context",
        )

        set_value("SchedulerPaused", True, delay=1.2)
        paused_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        time.sleep(2.4)
        check(controls("ExecutionStatus")["ExecutionStatus"]["String"] == paused_status, "pause blocks repeat callbacks while timeline resolution continues")

        set_value("SchedulerPaused", False, delay=1.2)
        resume_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in resume_status and "resume" in resume_status, "resume restores the current stateful Action")
        check("Callback 2" not in resume_status, "resume does not replay the current one-shot Action")

        set_value("SchedulerEditorEnabled", False, delay=1.2)
        scheduler_disabled_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        time.sleep(2.4)
        check(controls("ExecutionStatus")["ExecutionStatus"]["String"] == scheduler_disabled_status, "Scheduler disable blocks repeat callbacks independently of pause")

        set_value("SchedulerEditorEnabled", True, delay=1.2)
        scheduler_enabled_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in scheduler_enabled_status and "enabled" in scheduler_enabled_status, "Scheduler enable restores the current stateful Action")
        check("Callback 2" not in scheduler_enabled_status, "Scheduler enable does not replay the current one-shot Action")

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
        changed_status = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        changed_entries = {item["id"]: item for item in changed_status["schedulers"]}
        check(
            changed_entries[preserved_scheduler_id]["execution"]["planGeneration"] == preserved_generation
            and changed_entries[preserved_scheduler_id]["execution"]["timerPhaseSeconds"] == preserved_phase,
            "a scoped Scheduler edit preserves an unrelated Scheduler plan and timer",
        )
        check(
            changed_entries[scheduler_id]["execution"]["planGeneration"]
            != scheduler_entries[scheduler_id]["execution"]["planGeneration"],
            "the affected Scheduler receives a rebuilt plan generation",
        )
        check("Callback 2" in changed_to_b and "schedule change" in changed_to_b, "a schedule edit immediately reconciles the newly current stateful Event B")

        moved_model = json.loads(current_schedule_text())
        moved_scheduler = next(item for item in moved_model["schedulers"] if item["id"] == scheduler_id)
        event_b = next(item for item in moved_scheduler["dayPatterns"][0]["events"] if item["id"] == "qrc-current-event-b")
        event_b["time"] = (now + timedelta(minutes=5)).strftime("%H:%M") if (now.hour * 60) + now.minute <= 1434 else "00:00"
        set_value("ScheduleData", json.dumps(moved_model, indent=2), delay=1.3)
        rolled_back_to_a = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in rolled_back_to_a and "schedule change" in rolled_back_to_a, "moving Event B out of the current position immediately restores stateful Event A")
        check("Callback 2" not in rolled_back_to_a, "schedule reconciliation does not replay Event A's one-shot Action")

        time.sleep(2.4)
        reconciled_repeat = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Callback 1" in reconciled_repeat and "repeat" in reconciled_repeat, "Event A repeats restart after immediate schedule reconciliation")
        lifecycle_log = diagnostic_text()
        check(
            'Event "Current State" [qrc-current-event] | Action "Callback 2" [Callback2]' not in lifecycle_log,
            "current one-shot does not replay on startup, enable, resume, or schedule change",
        )

        set_value("AutomaticExecutionEnabled", False, delay=0.4)
        disabled_status = controls("ExecutionStatus", "Status")
        check(
            "disabled" in disabled_status["ExecutionStatus"]["String"].lower()
            and "automatic execution OFF" in disabled_status["Status"]["String"],
            "master guard disables callbacks and reports OFF",
        )
        time.sleep(2.4)
        check(
            controls("ExecutionStatus")["ExecutionStatus"]["String"] == disabled_status["ExecutionStatus"]["String"],
            "master guard blocks repeat callbacks",
        )

        # Build a focused real-edge fixture only after the lifecycle checks are complete.
        ensure_expected_design("scheduled-edge mutation")
        edge_status = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])
        edge_now = datetime.strptime(edge_status["resolvedFor"], "%Y-%m-%d %H:%M:%S")
        minute_offset = 1 if edge_now.second <= 25 else 2
        edge_at = (edge_now + timedelta(minutes=minute_offset)).replace(second=0)
        prior_at = edge_now - timedelta(minutes=1)

        edge_model = json.loads(original_schedule)
        for existing_scheduler in edge_model["schedulers"]:
            existing_scheduler["enabled"] = False
        edge_scheduler_id = "qrc-scheduled-edge-" + edge_now.strftime("%Y%m%d%H%M%S")
        edge_day_id = "qrc-scheduled-edge-day"
        edge_week_id = "qrc-scheduled-edge-week"
        edge_model["schedulers"].append({
            "id": edge_scheduler_id,
            "label": "Scheduled Edge QRC Test",
            "enabled": True,
            "paused": False,
            "defaultWeekPatternId": edge_week_id,
            "dayPatterns": [{
                "id": edge_day_id,
                "label": "Scheduled Edge Day",
                "events": [
                    {
                        "id": "qrc-edge-prior",
                        "label": "Prior State",
                        "time": prior_at.strftime("%H:%M"),
                        "actions": [{
                            "actionId": "Callback1", "enabled": True, "oneShot": False,
                            "fireOnStartup": False, "fireOnResume": False,
                        }],
                    },
                    {
                        "id": "qrc-edge-a",
                        "label": "Shared Edge A",
                        "time": edge_at.strftime("%H:%M"),
                        "actions": [
                            {"actionId": "Callback1", "enabled": True, "oneShot": False, "fireOnStartup": False, "fireOnResume": False},
                            {"actionId": "MissingAction", "enabled": True, "oneShot": False, "fireOnStartup": False, "fireOnResume": False},
                            {"actionId": "CallbackFail", "enabled": True, "oneShot": False, "fireOnStartup": False, "fireOnResume": False},
                            {"actionId": "Callback2", "enabled": True, "oneShot": False, "fireOnStartup": False, "fireOnResume": False},
                        ],
                    },
                    {
                        "id": "qrc-edge-b",
                        "label": "Shared Edge B",
                        "time": edge_at.strftime("%H:%M"),
                        "actions": [
                            {"actionId": "CallbackOneShot", "enabled": True, "oneShot": True, "fireOnStartup": False, "fireOnResume": False},
                            {"actionId": "CallbackRepeat", "enabled": True, "oneShot": False, "fireOnStartup": True, "fireOnResume": True, "repeatSeconds": 2},
                        ],
                    },
                ],
            }],
            "weekPatterns": [{
                "id": edge_week_id,
                "label": "Scheduled Edge Week",
                "days": {day: edge_day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
            }],
            "overrides": [],
        })
        set_value("ScheduleData", json.dumps(edge_model, indent=2), delay=1.3)
        set_value("SchedulerSelect", choice(edge_scheduler_id, "Scheduled Edge QRC Test"))
        before_edge_log = diagnostic_text()
        one_shot_success = (
            f'Scheduler "Scheduled Edge QRC Test" [{edge_scheduler_id}] | Event "Shared Edge B" [qrc-edge-b] | '
            'Action "Callback One Shot" [CallbackOneShot] | action=1 | reason=scheduled edge | Executed successfully'
        )
        repeat_success = (
            f'Scheduler "Scheduled Edge QRC Test" [{edge_scheduler_id}] | Event "Shared Edge B" [qrc-edge-b] | '
            'Action "Callback Repeat" [CallbackRepeat] | action=2 | reason=repeat | Executed successfully'
        )
        check(count_fragment(before_edge_log, one_shot_success) == 0, "one-shot edge marker is absent before arming")

        set_value("AutomaticExecutionEnabled", True, delay=1.3)
        wait_seconds = max(0.0, (edge_at - edge_now).total_seconds()) + 2.2
        check(wait_seconds <= 95, "real scheduled edge requires no more than a short deterministic wait")
        time.sleep(wait_seconds)

        after_edge_log = diagnostic_text()
        edge_delta = after_edge_log[len(before_edge_log):] if after_edge_log.startswith(before_edge_log) else after_edge_log
        edge_prefix = f'Scheduler "Scheduled Edge QRC Test" [{edge_scheduler_id}] | '
        ordered_fragments = [
            edge_prefix + 'Event "Shared Edge A" [qrc-edge-a] | Action "Callback 1" [Callback1] | action=1 | reason=scheduled edge | Executed successfully',
            edge_prefix + 'Event "Shared Edge A" [qrc-edge-a] | Action [MissingAction] | action=2 | reason=scheduled edge | Action is unavailable; execution skipped',
            edge_prefix + 'Event "Shared Edge A" [qrc-edge-a] | Action "Callback Fail" [CallbackFail] | action=3 | reason=scheduled edge | Callback failed:',
            edge_prefix + 'Event "Shared Edge A" [qrc-edge-a] | Action "Callback 2" [Callback2] | action=4 | reason=scheduled edge | Executed successfully',
            edge_prefix + 'Event "Shared Edge B" [qrc-edge-b] | Action "Callback One Shot" [CallbackOneShot] | action=1 | reason=scheduled edge | Executed successfully',
            edge_prefix + 'Event "Shared Edge B" [qrc-edge-b] | Action "Callback Repeat" [CallbackRepeat] | action=2 | reason=scheduled edge | Executed successfully',
        ]
        positions = [edge_delta.find(fragment) for fragment in ordered_fragments]
        check(all(position >= 0 for position in positions), "real future edge executes all success, missing, failure, and later Actions")
        check(positions == sorted(positions), "shared-time Events and their Event Actions execute in persisted array order")
        check("[ERROR]" in edge_delta and "MissingAction" in edge_delta, "missing registered Action logs Error")
        check(
            "[ERROR]" in edge_delta and "intentional guarded execution test failure" in edge_delta,
            "callback failure logs Error without stopping later Event Actions",
        )
        check(
            "[INFO]" in edge_delta and "Scheduled Edge QRC Test" in edge_delta
            and "Shared Edge A" in edge_delta and "Callback 1" in edge_delta
            and "reason=scheduled edge" in edge_delta,
            "successful scheduled-edge execution logs Info with Scheduler, Event, Action, and reason context",
        )
        execution_status = controls("ExecutionStatus")["ExecutionStatus"]["String"]
        check("Scheduled Edge QRC Test" in execution_status, "ExecutionStatus retains the latest scheduled execution result")

        time.sleep(2.4)
        repeat_delta = diagnostic_text()
        check(
            count_fragment(repeat_delta, repeat_success) >= 1 and "[DEBUG]" in repeat_delta,
            "repeat after the initial scheduled execution logs at Debug",
        )
        one_shot_count = count_fragment(repeat_delta, one_shot_success)
        check(one_shot_count == 1, "scheduled one-shot executes exactly once at its real edge")

        set_value("AutomaticExecutionEnabled", False, delay=0.4)
        serialized = current_schedule_text()
        check('\"_' not in serialized, "runtime-only execution state is absent from ScheduleData")
        health = controls("script.status", "script.error.count")
        check(
            health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0,
            "plugin remains OK with zero script errors after scheduled-edge validation",
        )

    finally:
        ensure_expected_design("cleanup")
        set_value("AutomaticExecutionEnabled", False, delay=0.3)
        set_value("ScheduleData", original_schedule, delay=0.5)
        set_value("TestDateTime", original_test_time, delay=0.2)
        set_value("DebugLogLevel", original_debug, delay=0.2)
        set_value("EventLogLevel", original_event, delay=0.2)
        set_value("code", original_provider_source, delay=1.0, component=ACTION_PROVIDER)
        final_controls = controls(
            "ScheduleData", "TestDateTime", "DebugLogLevel", "EventLogLevel", "ActionSource",
            "AutomaticExecutionEnabled", "ResolveTestTime", "ReloadActions",
        )
        final_provider = controls("code", "script.status", "script.error.count", component=ACTION_PROVIDER)
        restored = (
            final_controls["ScheduleData"]["String"] == original_schedule
            and final_controls["TestDateTime"]["String"] == original_test_time
            and final_controls["DebugLogLevel"]["String"] == original_debug
            and final_controls["EventLogLevel"]["String"] == original_event
            and final_controls["ActionSource"]["String"] == original_action_source
            and final_provider["code"]["String"] == original_provider_source
            and final_controls["AutomaticExecutionEnabled"]["Value"] < 0.5
            and final_controls["ResolveTestTime"]["Value"] < 0.5
            and final_controls["ReloadActions"]["Value"] < 0.5
        )
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} execution fixtures and persistent controls restored")
        if not restored:
            raise AssertionError("failed to restore execution fixtures or persistent controls")

    final_plugin = controls("script.status", "script.error.count", "AutomaticExecutionEnabled")
    final_runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    final_action = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(
        final_plugin["script.status"]["String"] == "OK"
        and final_plugin["script.error.count"]["Value"] == 0
        and final_runtime["script.status"]["String"] == "OK"
        and final_runtime["script.error.count"]["Value"] == 0
        and final_action["script.status"]["String"] == "OK"
        and final_action["script.error.count"]["Value"] == 0,
        "plugin, runtime provider, and Action Provider finish OK with zero errors",
    )
    check(final_plugin["AutomaticExecutionEnabled"]["Value"] < 0.5, "automatic execution finishes disabled")
    print(f"Completed {len(assertions)} assertions with restoration confirmed.")


if __name__ == "__main__":
    main()
