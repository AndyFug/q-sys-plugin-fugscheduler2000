#!/usr/bin/env python3
"""Exercise the FugScheduler Week Patterns editor through QRC and restore ScheduleData."""

from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
UUID_V4 = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
WEEKDAYS = {
    "Mon": "WeekPatternMon",
    "Tue": "WeekPatternTue",
    "Wed": "WeekPatternWed",
    "Thu": "WeekPatternThu",
    "Fri": "WeekPatternFri",
    "Sat": "WeekPatternSat",
    "Sun": "WeekPatternSun",
}

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


def set_value(name: str, value: object) -> None:
    qrc("set", COMPONENT, name, json.dumps(value, separators=(",", ":")))
    time.sleep(0.12)


def press(name: str) -> None:
    set_value(name, True)
    set_value(name, False)


def choice(identifier: str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def selected_id(name: str) -> str:
    value = controls(name)[name]["String"]
    return json.loads(value)["Id"]


def schedule_text() -> str:
    return controls("ScheduleData")["ScheduleData"]["String"]


def schedule() -> dict:
    return json.loads(schedule_text())


def selected_scheduler(model: dict, scheduler_id: str) -> dict:
    return next(item for item in model["schedulers"] if item["id"] == scheduler_id)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def no_runtime_keys(value: object) -> bool:
    if isinstance(value, dict):
        return all(not str(key).startswith("_") and no_runtime_keys(item) for key, item in value.items())
    if isinstance(value, list):
        return all(no_runtime_keys(item) for item in value)
    return True


def main() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active", "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")

    original = schedule_text()
    original_model = json.loads(original)
    restored = False

    try:
        required = [
            "WeekPatternSelect", "WeekPatternLabel", "WeekPatternReferences", "WeekPatternEditorStatus",
            "AddWeekPattern", "DuplicateWeekPattern", "DeleteWeekPattern", *WEEKDAYS.values(),
            "SchedulerSelect", "DayPatternSelect", "ScheduleData", "GlobalSchedulerStatus",
            "ResolutionSource", "Status", "script.status", "script.error.count",
        ]
        state = controls(*required)
        check(all(name in state for name in required), "Week Pattern page controls exist")
        check(state["script.status"]["String"] == "OK" and state["script.error.count"]["Value"] == 0,
              "plugin script is OK with zero errors")

        press("AddScheduler")
        scheduler_id = selected_id("SchedulerSelect")
        check(bool(UUID_V4.match(scheduler_id)), "temporary Scheduler has a UUID-v4-style ID")
        set_value("SchedulerLabel", "Week Pattern QRC Test")
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        check(scheduler["label"] == "Week Pattern QRC Test", "Scheduler editor still commits label edits")

        list_state = controls("WeekPatternSelect", "DeleteWeekPattern")
        selection = json.loads(list_state["WeekPatternSelect"]["String"])
        listed = [json.loads(item) for item in list_state["WeekPatternSelect"]["Choices"]]
        check(selection["Id"] == "default-week" and all(set(item) >= {"Text", "Id"} for item in listed),
              "Week Pattern ListBox returns structured Text/Id selections")
        check(list_state["DeleteWeekPattern"]["Disabled"] is True, "final/default Week Pattern delete is visually disabled")

        before = schedule_text()
        press("DeleteWeekPattern")
        rejected = controls("ScheduleData", "WeekPatternEditorStatus")
        check(rejected["ScheduleData"]["String"] == before, "forced final/default Week Pattern deletion is rejected")

        press("AddWeekPattern")
        new_week_id = selected_id("WeekPatternSelect")
        check(bool(UUID_V4.match(new_week_id)), "Add creates a UUID-v4-style Week Pattern ID")
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        new_week = next(item for item in scheduler["weekPatterns"] if item["id"] == new_week_id)
        check(all(new_week["days"][day] == "default-day" for day in WEEKDAYS),
              "new Week Pattern assigns the first Day Pattern to all weekdays")
        check(scheduler["defaultWeekPatternId"] == "default-week" and scheduler["overrides"] == [],
              "new Week Pattern does not change the default or create Overrides")

        revision = model["revision"]
        set_value("WeekPatternLabel", "Visual Test Week")
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        new_week = next(item for item in scheduler["weekPatterns"] if item["id"] == new_week_id)
        check(model["revision"] == revision + 1 and new_week["label"] == "Visual Test Week",
              "Week Pattern label edit commits exactly once")

        failure_before = controls(
            "ScheduleData", "GlobalSchedulerStatus", "ResolutionSource", "SchedulerSelect", "WeekPatternSelect"
        )
        set_value("WeekPatternLabel", "")
        failure_after = controls(
            "ScheduleData", "GlobalSchedulerStatus", "ResolutionSource", "SchedulerSelect", "WeekPatternSelect",
            "WeekPatternLabel", "WeekPatternEditorStatus"
        )
        unchanged = all(
            failure_after[name]["String"] == failure_before[name]["String"]
            for name in ["ScheduleData", "GlobalSchedulerStatus", "ResolutionSource", "SchedulerSelect", "WeekPatternSelect"]
        )
        check(unchanged and failure_after["WeekPatternLabel"]["String"] == "Visual Test Week",
              "empty label rejection preserves model, resolver output, and selections")
        check("rejected" in failure_after["WeekPatternEditorStatus"]["String"].lower(),
              "empty label rejection remains visible after snap-back")

        press("AddDayPattern")
        alternate_day_id = selected_id("DayPatternSelect")
        set_value("DayPatternLabel", "Alternate Test Day")
        set_value("WeekPatternSelect", choice(new_week_id, "Visual Test Week"))
        check(selected_id("WeekPatternSelect") == new_week_id, "Week Pattern selection is remembered per Scheduler")

        for day_key, control_name in WEEKDAYS.items():
            before_revision = schedule()["revision"]
            set_value(control_name, choice(alternate_day_id, "Alternate Test Day"))
            after_model = schedule()
            scheduler = selected_scheduler(after_model, scheduler_id)
            assigned = next(item for item in scheduler["weekPatterns"] if item["id"] == new_week_id)
            check(after_model["revision"] == before_revision + 1 and assigned["days"][day_key] == alternate_day_id,
                  f"{day_key} assignment commits the selected Day Pattern ID")

        source_days = dict(next(
            item for item in selected_scheduler(schedule(), scheduler_id)["weekPatterns"] if item["id"] == new_week_id
        )["days"])
        press("DuplicateWeekPattern")
        duplicate_id = selected_id("WeekPatternSelect")
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        duplicate = next(item for item in scheduler["weekPatterns"] if item["id"] == duplicate_id)
        check(duplicate_id != new_week_id and bool(UUID_V4.match(duplicate_id)), "Duplicate creates a fresh Week Pattern ID")
        check(duplicate["days"] == source_days and "Copy" in duplicate["label"],
              "Duplicate copies all assignments and uses a Copy label")

        set_value("WeekPatternMon", choice("default-day", "Default Day"))
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        source = next(item for item in scheduler["weekPatterns"] if item["id"] == new_week_id)
        duplicate = next(item for item in scheduler["weekPatterns"] if item["id"] == duplicate_id)
        check(source["days"]["Mon"] == alternate_day_id and duplicate["days"]["Mon"] == "default-day",
              "editing the duplicate does not alter the source")

        set_value("WeekPatternLabel", "Visual Test Week")
        duplicate_choices = [json.loads(item) for item in controls("WeekPatternSelect")["WeekPatternSelect"]["Choices"]]
        duplicate_texts = [item["Text"] for item in duplicate_choices if item["Id"] in {new_week_id, duplicate_id}]
        check(sorted(duplicate_texts) == ["Visual Test Week (1)", "Visual Test Week (2)"],
              "duplicate Week Pattern labels are disambiguated by display order")
        check(all(new_week_id not in text and duplicate_id not in text for text in duplicate_texts),
              "duplicate-label display text does not expose stable IDs")

        nested_before_reload = schedule_text()
        qrc("deploy", "SchedulerRuntimeProvider", str(ROOT / "src/runtime.lua"))
        time.sleep(0.5)
        check(schedule_text() == nested_before_reload, "runtime reload retains nested Week Pattern configuration")

        press("DeleteWeekPattern")
        model = schedule()
        scheduler = selected_scheduler(model, scheduler_id)
        check(all(item["id"] != duplicate_id for item in scheduler["weekPatterns"]),
              "unreferenced Week Pattern deletion succeeds")
        check(selected_id("WeekPatternSelect") != duplicate_id, "successful deletion selects a neighboring Week Pattern")

        set_value("WeekPatternSelect", choice("default-week", "Default Week"))
        default_before = schedule_text()
        default_state = controls("DeleteWeekPattern")
        check(default_state["DeleteWeekPattern"]["Disabled"] is True, "default Week Pattern delete is visually disabled")
        press("DeleteWeekPattern")
        check(schedule_text() == default_before, "forced default Week Pattern deletion is rejected")

        set_value("WeekPatternSelect", choice(new_week_id, "Visual Test Week"))
        with_override = schedule()
        temporary_scheduler = selected_scheduler(with_override, scheduler_id)
        temporary_scheduler["overrides"].append({
            "id": "disabled-week-reference",
            "label": "Disabled Week Reference",
            "type": "WeekPattern",
            "startDate": "2030-01-01",
            "endDate": "2030-01-02",
            "patternId": new_week_id,
            "enabled": False,
        })
        set_value("ScheduleData", json.dumps(with_override, indent=4))
        set_value("WeekPatternSelect", choice(new_week_id, "Visual Test Week"))
        override_state = controls("DeleteWeekPattern", "WeekPatternReferences")
        check(override_state["DeleteWeekPattern"]["Disabled"] is True and "used by 1 Overrides" in override_state["WeekPatternReferences"]["String"],
              "disabled Week Pattern Override references disable deletion")
        override_before = schedule_text()
        press("DeleteWeekPattern")
        check(schedule_text() == override_before, "forced deletion with a disabled Override reference is rejected")

        without_override = schedule()
        temporary_scheduler = selected_scheduler(without_override, scheduler_id)
        temporary_scheduler["overrides"] = [
            item for item in temporary_scheduler["overrides"] if item["id"] != "disabled-week-reference"
        ]
        set_value("ScheduleData", json.dumps(without_override, indent=4))
        set_value("WeekPatternSelect", choice(new_week_id, "Visual Test Week"))
        press("DeleteWeekPattern")
        check(all(
            item["id"] != new_week_id
            for item in selected_scheduler(schedule(), scheduler_id)["weekPatterns"]
        ), "unreferenced source Week Pattern can be deleted after Override removal")

        set_value("WeekPatternSelect", choice("default-week", "Default Week"))
        final_before = schedule_text()
        press("DeleteWeekPattern")
        check(schedule_text() == final_before, "final remaining Week Pattern deletion remains rejected")

        current_model = schedule()
        check(no_runtime_keys(current_model), "runtime underscore indexes are absent from ScheduleData")
        status_text = controls("Status")["Status"]["String"]
        check("automatic execution OFF" in status_text, "automatic scheduled callback execution remains disabled")
        health = controls("script.status", "script.error.count")
        check(health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0,
              "plugin remains OK with zero script errors")

    finally:
        set_value("ScheduleData", original)
        restored_text = schedule_text()
        restored = restored_text == original
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} byte-for-byte ScheduleData restoration")
        if restored:
            assertions.append("original ScheduleData restored byte-for-byte")

    if not restored:
        raise AssertionError("original ScheduleData was not restored byte-for-byte")
    check(json.loads(schedule_text()) == original_model, "restored ScheduleData decodes to the original model")
    print(f"RESULT: {len(assertions)} assertions passed")


if __name__ == "__main__":
    main()
