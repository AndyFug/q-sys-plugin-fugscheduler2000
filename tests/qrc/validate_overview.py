#!/usr/bin/env python3
"""Validate stable Scheduler Slots, assignment filtering, Inspector, and deletion guards."""

from __future__ import annotations

import json
import subprocess
import time
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


def set_value(name: str, value: object, delay: float = 0.45) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def press(name: str, delay: float = 0.45) -> None:
    set_value(name, True, 0.12)
    set_value(name, False, delay)


def choice(identifier: object, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def scheduler(identifier: str, label: str) -> dict:
    day_id, week_id = f"{identifier}-day", f"{identifier}-week"
    return {
        "id": identifier,
        "label": label,
        "defaultWeekPatternId": week_id,
        "dayPatterns": [{
            "id": day_id,
            "label": f"{label} Day",
            "events": [{
                "id": f"{identifier}-event", "label": f"{label} Event", "time": "09:00",
                "actions": [{"actionId": "Callback1", "enabled": True, "oneShot": False,
                             "fireOnStartup": False, "fireOnResume": False}],
            }],
        }],
        "weekPatterns": [{
            "id": week_id, "label": f"{label} Week",
            "days": {day: day_id for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
        }],
        "overrides": [],
    }


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")


def main() -> None:
    ensure_design()
    required = ["ScheduleData", "AutomaticExecutionEnabled", "SchedulerSlotsPreviousBank",
                "SchedulerSlotsNextBank", "SchedulerSlotsBankStatus", "SchedulerDefinitionSelect",
                "SchedulerDefinitionAssignedSlot", "UnassignSchedulerDefinition", "DeleteSchedulerDefinition",
                "InspectorSlotSelect", "InspectorSlotEnabled", "InspectorSlotPaused",
                "AssignedSchedulerSlotCount", "GlobalSchedulerSlotStatus"]
    for slot in range(1, 9):
        required += [f"SchedulerSlotDefinition {slot}", f"SchedulerSlotAssignedId {slot}",
                     f"SchedulerSlotEnabled {slot}", f"SchedulerSlotPaused {slot}"]
    initial = controls(*required)
    check(all(name in initial for name in required), "all stable Slot, Inspector, and Definition controls exist")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable starts off")

    original_schedule = initial["ScheduleData"]["String"]
    fixture = {
        "schemaVersion": 2,
        "revision": 1,
        "schedulerSlots": [{"slot": index, "enabled": False, "paused": False} for index in range(1, 9)],
        "schedulers": [scheduler("slot-test-a", "Slot Test A"), scheduler("slot-test-b", "Slot Test B")],
    }

    try:
        set_value("ScheduleData", json.dumps(fixture, separators=(",", ":")), 1.2)
        state = controls("SchedulerSlotsBankStatus", "SchedulerSlotsPreviousBank", "SchedulerSlotsNextBank",
                         "AssignedSchedulerSlotCount", "GlobalSchedulerSlotStatus",
                         "SchedulerSlotDefinition 1", "SchedulerSlotEnabled 1", "SchedulerSlotPaused 1")
        check(state["SchedulerSlotsBankStatus"]["String"] == "Page 1 of 1 (Slots 1-8)",
              "default eight Slots occupy one bank")
        check(state["SchedulerSlotsPreviousBank"].get("Disabled") is True and
              state["SchedulerSlotsNextBank"].get("Disabled") is True,
              "bank navigation is disabled when all eight Slots fit")
        check(state["AssignedSchedulerSlotCount"]["String"] == "0", "unassigned Definition library has no runtime Slots")
        check(json.loads(state["GlobalSchedulerSlotStatus"]["String"])["slots"] == [],
              "unassigned Definitions are absent from aggregate runtime status")
        check(state["SchedulerSlotEnabled 1"].get("Disabled") is True and
              state["SchedulerSlotPaused 1"].get("Disabled") is True,
              "unassigned Slot operational controls are disabled")

        set_value("SchedulerSlotDefinition 1", choice("slot-test-a", "Slot Test A"), 1.2)
        assigned = controls("ScheduleData", "SchedulerSlotAssignedId 1", "SchedulerSlotEnabled 1",
                            "SchedulerSlotPaused 1", "SchedulerSlotDefinition 2", "AssignedSchedulerSlotCount",
                            "SchedulerDefinitionAssignedSlot", "UnassignSchedulerDefinition", "DeleteSchedulerDefinition")
        model = json.loads(assigned["ScheduleData"]["String"])
        check(model["schedulerSlots"][0]["schedulerId"] == "slot-test-a", "Slot assignment persists by Definition ID")
        check(assigned["SchedulerSlotAssignedId 1"]["String"] == "slot-test-a", "stable assigned-ID output reports Definition")
        check(assigned["SchedulerSlotEnabled 1"].get("Disabled") is False and
              assigned["SchedulerSlotPaused 1"].get("Disabled") is False,
              "assigned Slot operational controls become active")
        check(not any("slot-test-a" in item for item in assigned["SchedulerSlotDefinition 2"].get("Choices", [])),
              "Definition assigned to Slot 1 is excluded from Slot 2 choices")
        before_duplicate_assignment = assigned["ScheduleData"]["String"]
        set_value("SchedulerSlotDefinition 2", choice("slot-test-a", "Slot Test A"), 0.8)
        duplicate_attempt = controls("ScheduleData", "SchedulerSlotAssignedId 2")
        check(duplicate_attempt["ScheduleData"]["String"] == before_duplicate_assignment,
              "forced duplicate assignment preserves ScheduleData")
        check(duplicate_attempt["SchedulerSlotAssignedId 2"]["String"] == "",
              "forced duplicate assignment leaves the second Slot unassigned")
        check(assigned["AssignedSchedulerSlotCount"]["String"] == "1", "assigned Slot count updates")
        check(assigned["SchedulerDefinitionAssignedSlot"]["String"] == "Scheduler Slot 1",
              "Definition editor reports its assigned Slot")
        check(assigned["UnassignSchedulerDefinition"].get("Disabled") is False,
              "Unassign helper is enabled for an assigned Definition")
        check(assigned["DeleteSchedulerDefinition"].get("Disabled") is True,
              "Delete Definition is visually disabled while assigned")

        before_forced_delete = assigned["ScheduleData"]["String"]
        press("DeleteSchedulerDefinition")
        after_forced_delete = controls("ScheduleData", "SchedulerDefinitionEditorStatus")
        check(after_forced_delete["ScheduleData"]["String"] == before_forced_delete,
              "forced delete press preserves an assigned Definition")
        check("unassign it first" in after_forced_delete["SchedulerDefinitionEditorStatus"]["String"],
              "forced delete reports the assignment guard")

        set_value("InspectorSlotSelect", choice(1, "Slot 1 — Slot Test A"), 0.7)
        set_value("InspectorSlotEnabled", True, 0.8)
        set_value("InspectorSlotPaused", True, 0.8)
        inspector = controls("ScheduleData", "SchedulerSlotEnabled 1", "SchedulerSlotPaused 1",
                             "InspectorSlotEnabled", "InspectorSlotPaused")
        inspector_model = json.loads(inspector["ScheduleData"]["String"])
        check(inspector_model["schedulerSlots"][0]["enabled"] is True and
              inspector_model["schedulerSlots"][0]["paused"] is True,
              "Inspector runtime toggles persist against the selected Slot")
        check(inspector["SchedulerSlotEnabled 1"]["Value"] > 0.5 and
              inspector["SchedulerSlotPaused 1"]["Value"] > 0.5,
              "Scheduler Slots page mirrors Inspector runtime state")

        press("UnassignSchedulerDefinition", 1.0)
        unassigned = controls("ScheduleData", "SchedulerSlotAssignedId 1", "SchedulerSlotEnabled 1",
                              "SchedulerSlotPaused 1", "AssignedSchedulerSlotCount", "UnassignSchedulerDefinition")
        unassigned_model = json.loads(unassigned["ScheduleData"]["String"])
        check("schedulerId" not in unassigned_model["schedulerSlots"][0] and
              unassigned_model["schedulerSlots"][0]["enabled"] is False and
              unassigned_model["schedulerSlots"][0]["paused"] is False,
              "Unassign clears assignment and operational state")
        check(unassigned["AssignedSchedulerSlotCount"]["String"] == "0" and
              unassigned["UnassignSchedulerDefinition"].get("Disabled") is True,
              "unassigned Definition returns helper controls to idle state")
    finally:
        set_value("ScheduleData", original_schedule, 1.2)
        for name in ["DeleteSchedulerDefinition", "UnassignSchedulerDefinition",
                     "SchedulerSlotsPreviousBank", "SchedulerSlotsNextBank"]:
            set_value(name, False, 0.05)
        final = controls("ScheduleData", "AutomaticExecutionEnabled", "DeleteSchedulerDefinition",
                         "UnassignSchedulerDefinition", "SchedulerSlotsPreviousBank", "SchedulerSlotsNextBank")
        restored = final["ScheduleData"]["String"] == original_schedule
        idle = final["AutomaticExecutionEnabled"]["Value"] < 0.5 and all(
            final[name]["Value"] < 0.5 for name in ["DeleteSchedulerDefinition", "UnassignSchedulerDefinition",
                                                    "SchedulerSlotsPreviousBank", "SchedulerSlotsNextBank"])
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} Slot fixture restored byte-for-byte")
        if not restored or not idle:
            raise AssertionError("failed to restore Slot fixture or leave controls idle")

    health = controls("Status", "script.status", "script.error.count")
    runtime = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    action = controls("script.status", "script.error.count", component=ACTION_PROVIDER)
    check(health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0 and
          runtime["script.status"]["String"] == "OK" and runtime["script.error.count"]["Value"] == 0 and
          action["script.status"]["String"] == "OK" and action["script.error.count"]["Value"] == 0,
          "plugin, runtime provider, and Action provider finish healthy")
    print(f"SUCCESS: {len(assertions)} Scheduler Slot assertions passed")


if __name__ == "__main__":
    main()
