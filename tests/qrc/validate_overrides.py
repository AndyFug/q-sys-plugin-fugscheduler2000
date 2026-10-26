#!/usr/bin/env python3
"""Exercise the FugScheduler Overrides editor through QRC and restore ScheduleData."""

from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path

HOST = "10.211.55.4"
DESIGN = "fugscheduler2000_test"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"
UUID_V4 = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

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


def set_value(name: str, value: object) -> None:
    qrc("set", COMPONENT, name, json.dumps(value, separators=(",", ":")))
    time.sleep(0.14)


def press(name: str) -> None:
    set_value(name, True)
    set_value(name, False)


def choice(identifier: str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def selected_id(name: str) -> str:
    return json.loads(controls(name)[name]["String"])["Id"]


def schedule_text() -> str:
    return controls("ScheduleData")["ScheduleData"]["String"]


def schedule() -> dict:
    return json.loads(schedule_text())


def selected_scheduler(model: dict, scheduler_id: str) -> dict:
    return next(item for item in model["schedulers"] if item["id"] == scheduler_id)


def selected_override(model: dict, scheduler_id: str, override_id: str) -> dict:
    scheduler = selected_scheduler(model, scheduler_id)
    return next(item for item in scheduler["overrides"] if item["id"] == override_id)


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


def failure_snapshot() -> dict[str, str]:
    names = ["ScheduleData", "GlobalSchedulerStatus", "ResolutionSource", "SchedulerSelect", "OverrideSelect"]
    state = controls(*names)
    return {name: state[name]["String"] for name in names}


def main() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active", "expected active Emulator")
    check(status["DesignName"] == DESIGN, "expected design is active")

    original = schedule_text()
    original_preference = controls("DateFormatPreference")["DateFormatPreference"]["String"]
    restored = False
    preference_restored = False

    try:
        set_value("DateFormatPreference", choice("ISO", "yyyy-mm-dd"))
        required = [
            "OverrideSelect", "OverrideLabel", "OverrideEnabled", "OverrideType",
            "OverrideStartDate", "OverrideEndDate", "OverridePattern", "OverrideSummary",
            "AddOverride", "DuplicateOverride", "DeleteOverride", "MoveOverrideUp",
            "MoveOverrideDown", "OverrideEditorStatus", "SchedulerSelect", "DayPatternSelect",
            "WeekPatternSelect", "ScheduleData", "GlobalSchedulerStatus", "ResolutionSource",
            "TestDateTime", "ResolveTestTime", "Status", "script.status", "script.error.count",
        ]
        state = controls(*required)
        check(all(name in state for name in required), "Overrides page controls exist")
        check(state["script.status"]["String"] == "OK" and state["script.error.count"]["Value"] == 0,
              "plugin script is OK with zero errors")
        runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        check(runtime_health["script.status"]["String"] == "OK" and runtime_health["script.error.count"]["Value"] == 0,
              "runtime provider script is OK with zero errors")

        press("AddScheduler")
        scheduler_id = selected_id("SchedulerSelect")
        check(bool(UUID_V4.match(scheduler_id)), "temporary Scheduler has a UUID-v4-style ID")
        set_value("SchedulerLabel", "Override QRC Test")

        press("AddOverride")
        override_id = selected_id("OverrideSelect")
        check(bool(UUID_V4.match(override_id)), "Add creates a UUID-v4-style Override ID")
        model = schedule()
        override = selected_override(model, scheduler_id, override_id)
        check(override["type"] == "DayPattern" and override["enabled"] is False and
              override["patternId"] == "default-day" and override["startDate"] == override["endDate"],
              "new Override is disabled and immediately schema-valid with Day Pattern defaults")

        list_state = controls("OverrideSelect")
        listed = [json.loads(item) for item in list_state["OverrideSelect"]["Choices"]]
        check(all(set(item) >= {"Text", "Id"} for item in listed) and listed[0]["Id"] == override_id,
              "Override ListBox returns structured Text/Id selections")

        revision = model["revision"]
        set_value("OverrideLabel", "Day Priority")
        model = schedule()
        check(model["revision"] == revision + 1 and selected_override(model, scheduler_id, override_id)["label"] == "Day Priority",
              "Override label edit commits exactly once")

        before = failure_snapshot()
        set_value("OverrideLabel", "")
        after = failure_snapshot()
        snapped = controls("OverrideLabel", "OverrideEditorStatus")
        check(after == before and snapped["OverrideLabel"]["String"] == "Day Priority",
              "empty label rejection preserves JSON, resolver output, and selections")
        check("rejected" in snapped["OverrideEditorStatus"]["String"].lower(),
              "empty label rejection remains visible after snap-back")

        set_value("OverrideEnabled", True)
        check(selected_override(schedule(), scheduler_id, override_id)["enabled"] is True,
              "Override enabled state commits true")
        set_value("OverrideEnabled", False)
        check(selected_override(schedule(), scheduler_id, override_id)["enabled"] is False,
              "Override enabled state commits false")
        set_value("OverrideEnabled", True)
        check(selected_override(schedule(), scheduler_id, override_id)["enabled"] is True,
              "Override can be re-enabled for resolver testing")

        set_value("OverrideStartDate", "2030-01-02")
        set_value("OverrideEndDate", "2030-01-03")
        override = selected_override(schedule(), scheduler_id, override_id)
        check(override["startDate"] == "2030-01-02" and override["endDate"] == "2030-01-03",
              "valid inclusive start and end dates commit")

        for invalid_value, label in [("2030/1/02", "invalid date formatting"), ("2030-02-30", "invalid calendar date")]:
            before = failure_snapshot()
            set_value("OverrideStartDate", invalid_value)
            check(failure_snapshot() == before and controls("OverrideStartDate")["OverrideStartDate"]["String"] == invalid_value,
                  f"{label} is rejected and remains buffered")

        before = failure_snapshot()
        set_value("OverrideEndDate", "2030-01-01")
        check(failure_snapshot() == before and controls("OverrideEndDate")["OverrideEndDate"]["String"] == "2030-01-01",
              "end date before start is rejected without state changes")

        press("AddDayPattern")
        alternate_day_id = selected_id("DayPatternSelect")
        set_value("DayPatternLabel", "Override Test Day")
        set_value("OverrideSelect", choice(override_id, "Day Priority"))
        set_value("OverridePattern", choice(alternate_day_id, "Override Test Day"))
        check(selected_override(schedule(), scheduler_id, override_id)["patternId"] == alternate_day_id,
              "DayPattern Override stores a Day Pattern ID")

        set_value("OverrideType", choice("WeekPattern", "Week Pattern"))
        override = selected_override(schedule(), scheduler_id, override_id)
        check(override["type"] == "WeekPattern" and override["patternId"] == "default-week",
              "WeekPattern type change assigns a valid Week Pattern ID")
        set_value("OverrideType", choice("DayPattern", "Day Pattern"))
        override = selected_override(schedule(), scheduler_id, override_id)
        check(override["type"] == "DayPattern" and override["patternId"] in {"default-day", alternate_day_id},
              "type changes never leave an invalid cross-type reference")
        set_value("OverridePattern", choice(alternate_day_id, "Override Test Day"))

        press("DuplicateOverride")
        duplicate_id = selected_id("OverrideSelect")
        model = schedule()
        source = selected_override(model, scheduler_id, override_id)
        duplicate = selected_override(model, scheduler_id, duplicate_id)
        check(duplicate_id != override_id and bool(UUID_V4.match(duplicate_id)),
              "Duplicate creates a fresh Override ID")
        copied_fields = ["type", "startDate", "endDate", "patternId"]
        check(all(duplicate[field] == source[field] for field in copied_fields) and
              duplicate["enabled"] is False and "Copy" in duplicate["label"],
              "Duplicate copies structural fields independently and starts disabled")

        set_value("OverrideLabel", "Week Priority")
        model = schedule()
        check(selected_override(model, scheduler_id, duplicate_id)["label"] == "Week Priority" and
              selected_override(model, scheduler_id, override_id)["label"] == "Day Priority",
              "editing the duplicate does not alter the source")

        set_value("OverrideLabel", "Day Priority")
        duplicate_choices = [json.loads(item) for item in controls("OverrideSelect")["OverrideSelect"]["Choices"]]
        duplicate_texts = [item["Text"] for item in duplicate_choices if item["Id"] in {override_id, duplicate_id}]
        check(sorted(duplicate_texts) == ["Day Priority (1)", "Day Priority (2)"] and
              all(override_id not in text and duplicate_id not in text for text in duplicate_texts),
              "duplicate Override labels are disambiguated without displaying IDs")
        set_value("OverrideLabel", "Week Priority")

        before_order = [item["id"] for item in selected_scheduler(model, scheduler_id)["overrides"]]
        press("MoveOverrideUp")
        moved_model = schedule()
        after_order = [item["id"] for item in selected_scheduler(moved_model, scheduler_id)["overrides"]]
        moved_duplicate = selected_override(moved_model, scheduler_id, duplicate_id)
        check(after_order != before_order and all(moved_duplicate[field] == duplicate[field] for field in copied_fields),
              "Move Up changes persisted order without losing fields")
        boundary = controls("MoveOverrideUp")
        check(boundary["MoveOverrideUp"]["Disabled"] is True, "boundary Move Up is visually disabled")
        boundary_before = schedule_text()
        press("MoveOverrideUp")
        check(schedule_text() == boundary_before, "forced boundary Move Up is harmless")
        press("MoveOverrideDown")
        check([item["id"] for item in selected_scheduler(schedule(), scheduler_id)["overrides"]] == before_order,
              "Move Down restores persisted priority order")

        set_value("OverrideEnabled", True)
        check(selected_override(schedule(), scheduler_id, duplicate_id)["enabled"] is True,
              "duplicated Override can be explicitly enabled")
        set_value("OverrideSelect", choice(override_id, "Day Priority"))
        summary = controls("OverrideSummary")["OverrideSummary"]["String"]
        check("Overlaps 1 enabled Day Pattern Override" in summary,
              "enabled same-type overlap produces a concise warning")
        set_value("OverrideSelect", choice(duplicate_id, "Week Priority"))
        set_value("OverrideEnabled", False)
        disabled_summary = controls("OverrideSummary")["OverrideSummary"]["String"]
        check("Disabled; no active overlaps" in disabled_summary,
              "disabled Override summary reports no active overlaps")
        set_value("OverrideSelect", choice(override_id, "Day Priority"))
        summary = controls("OverrideSummary")["OverrideSummary"]["String"]
        check("No enabled same-type overlaps" in summary,
              "disabled overlap does not produce an active warning")

        set_value("OverrideSelect", choice(duplicate_id, "Week Priority"))
        set_value("OverrideType", choice("WeekPattern", "Week Pattern"))
        set_value("OverrideEnabled", True)
        set_value("OverrideSelect", choice(override_id, "Day Priority"))
        set_value("TestDateTime", "2030-01-02 12:00")
        press("ResolveTestTime")
        check(controls("ResolutionSource")["ResolutionSource"]["String"] == "Day Override: Day Priority",
              "Day Pattern Override outranks an overlapping Week Pattern Override")

        set_value("OverrideEnabled", False)
        press("ResolveTestTime")
        check(controls("ResolutionSource")["ResolutionSource"]["String"] == "Week Override: Week Priority",
              "disabled Day Pattern Override does not affect resolution")
        set_value("OverrideSelect", choice(duplicate_id, "Week Priority"))
        set_value("OverrideEnabled", False)
        press("ResolveTestTime")
        check(controls("ResolutionSource")["ResolutionSource"]["String"] == "Default Week Pattern: Default Week",
              "disabled Week Pattern Override does not affect resolution")

        set_value("OverrideEnabled", True)
        nested_before_reload = schedule_text()
        qrc("deploy", RUNTIME_PROVIDER, str(ROOT / "src/runtime.lua"))
        time.sleep(0.6)
        check(schedule_text() == nested_before_reload, "runtime reload retains nested Override configuration")

        set_value("OverrideSelect", choice(duplicate_id, "Week Priority"))
        press("DeleteOverride")
        model = schedule()
        check(all(item["id"] != duplicate_id for item in selected_scheduler(model, scheduler_id)["overrides"]),
              "Delete succeeds for the selected Override")
        check(selected_id("OverrideSelect") == override_id, "Delete selects the neighboring Override")

        check(no_runtime_keys(model), "runtime underscore indexes are absent from ScheduleData")
        press("AddWeekPattern")
        set_value("WeekPatternLabel", "Override Test Week")
        check(any(item["label"] == "Override Test Week" for item in selected_scheduler(schedule(), scheduler_id)["weekPatterns"]),
              "existing Week Pattern editor still commits edits")
        check(any(item["label"] == "Override Test Day" for item in selected_scheduler(schedule(), scheduler_id)["dayPatterns"]),
              "existing Day Pattern editor still retains edits")
        check(selected_scheduler(schedule(), scheduler_id)["label"] == "Override QRC Test",
              "existing Scheduler editor still retains edits")
        check("automatic execution OFF" in controls("Status")["Status"]["String"],
              "automatic scheduled callback execution remains disabled")

        final_health = controls("script.status", "script.error.count")
        check(final_health["script.status"]["String"] == "OK" and final_health["script.error.count"]["Value"] == 0,
              "plugin finishes with zero script errors")

    finally:
        set_value("ScheduleData", original)
        set_value("DateFormatPreference", original_preference)
        restored = schedule_text() == original
        preference_restored = controls("DateFormatPreference")["DateFormatPreference"]["String"] == original_preference
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} byte-for-byte ScheduleData restoration")
        print(f"RESTORE preference: {'PASS' if preference_restored else 'FAIL'} byte-for-byte restoration")
        if restored:
            assertions.append("original ScheduleData restored byte-for-byte")
        if preference_restored:
            assertions.append("original date preference restored byte-for-byte")

    if not restored or not preference_restored:
        raise AssertionError("original persistent values were not restored byte-for-byte")
    print(f"RESULT: {len(assertions)} assertions passed")


if __name__ == "__main__":
    main()
