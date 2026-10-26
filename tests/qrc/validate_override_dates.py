#!/usr/bin/env python3
"""Validate Override date preferences, buffering, and range operations through QRC."""

from __future__ import annotations

import json
import subprocess
import time
from datetime import date
from pathlib import Path

HOST = "10.211.55.4"
DESIGN = "fugscheduler2000_test"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
ROOT = Path(__file__).resolve().parents[2]
QRC = ROOT.parent / ".agents/skills/qsys-deploy/scripts/qsys-qrc.cjs"

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
    return next(item for item in selected_scheduler(model, scheduler_id)["overrides"] if item["id"] == override_id)


def preference_text() -> str:
    return controls("DateFormatPreference")["DateFormatPreference"]["String"]


def set_preference(identifier: str, label: str) -> None:
    set_value("DateFormatPreference", choice(identifier, label))


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    assertions.append(label)
    print(f"PASS {len(assertions):02d}: {label}")


def failure_snapshot() -> dict[str, str]:
    names = [
        "ScheduleData", "GlobalSchedulerStatus", "ResolutionSource",
        "SchedulerSelect", "OverrideSelect",
    ]
    state = controls(*names)
    return {name: state[name]["String"] for name in names}


def no_runtime_keys(value: object) -> bool:
    if isinstance(value, dict):
        return all(not str(key).startswith("_") and no_runtime_keys(item) for key, item in value.items())
    if isinstance(value, list):
        return all(no_runtime_keys(item) for item in value)
    return True


def main() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active", "expected active Emulator")
    check(status["DesignName"] == DESIGN, "expected design is active")

    original_schedule = schedule_text()
    original_preference = preference_text()
    restored_schedule = False
    restored_preference = False

    try:
        required = [
            "DateFormatPreference", "PreferencesStatus", "OverrideStartDate", "OverrideEndDate",
            "OverrideStartDateLongForm", "OverrideEndDateLongForm",
            "OverrideStartDateValidation", "OverrideEndDateValidation", "OverrideRangeSummary",
            "SetOverrideRangeToday", "ShiftOverrideStartBackDay", "ShiftOverrideStartForwardDay",
            "ShiftOverrideStartBackWeek", "ShiftOverrideStartForwardWeek", "SetOverrideRangeOneDay",
            "ShiftOverrideRangeBack", "ShiftOverrideRangeForward", "ShiftOverrideEndBackWeek",
            "ShiftOverrideEndForwardWeek", "OverrideEditorStatus", "ScheduleData", "GlobalSchedulerStatus",
            "ResolutionSource", "SchedulerSelect", "OverrideSelect", "Status", "script.status",
            "script.error.count",
        ]
        state = controls(*required)
        check(all(name in state for name in required), "date preference and Override range controls exist")
        preference_choices = [json.loads(item) for item in state["DateFormatPreference"]["Choices"]]
        check([(item["Id"], item["Text"]) for item in preference_choices] == [
            ("DMY", "dd/mm/yyyy"), ("MDY", "mm/dd/yyyy"), ("ISO", "yyyy-mm-dd")
        ], "preference exposes neutral DMY, MDY, and ISO choices")
        check(state["script.status"]["String"] == "OK" and state["script.error.count"]["Value"] == 0,
              "plugin starts OK with zero errors")
        runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        check(runtime_health["script.status"]["String"] == "OK" and runtime_health["script.error.count"]["Value"] == 0,
              "runtime provider starts OK with zero errors")

        press("AddScheduler")
        scheduler_id = selected_id("SchedulerSelect")
        set_value("SchedulerLabel", "Override Date QRC Test")
        press("AddOverride")
        override_id = selected_id("OverrideSelect")
        press("SetOverrideRangeOneDay")

        before_preference = failure_snapshot()
        before_revision = schedule()["revision"]
        set_preference("DMY", "dd/mm/yyyy")
        after_preference = failure_snapshot()
        check(after_preference == before_preference and schedule()["revision"] == before_revision,
              "preference change preserves ScheduleData, revision, resolver output, and selections")

        set_value("OverrideStartDate", "24/12/2026")
        override = selected_override(schedule(), scheduler_id, override_id)
        check(override["startDate"] == "2026-12-24" and override["endDate"] == "2026-12-24",
              "valid DMY Start commits canonical ISO while preserving one-day duration")
        set_value("OverrideEndDate", "26/12/2026")
        override = selected_override(schedule(), scheduler_id, override_id)
        check(override["endDate"] == "2026-12-26", "valid DMY End commits canonical ISO")
        rendered = controls("OverrideStartDate", "OverrideEndDate", "OverrideStartDateLongForm",
                            "OverrideEndDateLongForm", "OverrideRangeSummary")
        check(rendered["OverrideStartDate"]["String"] == "24/12/2026" and
              rendered["OverrideEndDate"]["String"] == "26/12/2026",
              "canonical dates render in DMY")
        check(rendered["OverrideStartDateLongForm"]["String"] == "Thursday, 24 December 2026" and
              rendered["OverrideEndDateLongForm"]["String"] == "Saturday, 26 December 2026",
              "long-form resolved dates use English weekday and month names")
        check(rendered["OverrideRangeSummary"]["String"] ==
              "3 days inclusive\nThursday, 24 December 2026 – Saturday, 26 December 2026",
              "inclusive range summary is correct")

        set_preference("MDY", "mm/dd/yyyy")
        rendered = controls("OverrideStartDate", "OverrideEndDate")
        check(rendered["OverrideStartDate"]["String"] == "12/24/2026" and
              rendered["OverrideEndDate"]["String"] == "12/26/2026",
              "existing ISO model dates render in MDY")
        set_value("OverrideEndDate", "12/27/2026")
        check(selected_override(schedule(), scheduler_id, override_id)["endDate"] == "2026-12-27",
              "valid MDY input commits expected ISO meaning")

        set_preference("ISO", "yyyy-mm-dd")
        rendered = controls("OverrideStartDate", "OverrideEndDate")
        check(rendered["OverrideStartDate"]["String"] == "2026-12-24" and
              rendered["OverrideEndDate"]["String"] == "2026-12-27",
              "existing ISO model dates render canonically in ISO")
        set_value("OverrideEndDate", "2026-12-28")
        check(selected_override(schedule(), scheduler_id, override_id)["endDate"] == "2026-12-28",
              "valid ISO input retains canonical meaning")

        set_preference("DMY", "dd/mm/yyyy")
        set_value("OverrideStartDate", "1/2/2030")
        normalized = controls("OverrideStartDate", "OverrideEndDate")
        override = selected_override(schedule(), scheduler_id, override_id)
        check(normalized["OverrideStartDate"]["String"] == "01/02/2030" and override["startDate"] == "2030-02-01",
              "one-digit DMY day/month input normalizes to two digits")

        invalid_before = failure_snapshot()
        invalid_revision = schedule()["revision"]
        set_value("OverrideStartDate", "31/02/2030")
        invalid_after = failure_snapshot()
        invalid_controls = controls("OverrideStartDate", "OverrideStartDateLongForm",
                                    "OverrideStartDateValidation", "OverrideEditorStatus")
        check(invalid_after == invalid_before and schedule()["revision"] == invalid_revision,
              "invalid calendar date preserves JSON, revision, resolver output, and selections")
        check(invalid_controls["OverrideStartDate"]["String"] == "31/02/2030" and
              invalid_controls["OverrideStartDateLongForm"]["String"] == "" and
              invalid_controls["OverrideStartDateValidation"]["String"] == "Invalid date",
              "invalid Start text remains buffered with clear ordinary-text validation")
        check("Start date: Invalid date" in invalid_controls["OverrideEditorStatus"]["String"],
              "centered editor status reports the complete Start validation message")

        malformed_before = failure_snapshot()
        set_value("OverrideStartDate", "2030/02/01")
        check(failure_snapshot() == malformed_before and controls("OverrideStartDate")["OverrideStartDate"]["String"] == "2030/02/01",
              "invalid preference formatting remains buffered without model changes")

        current = selected_override(schedule(), scheduler_id, override_id)
        set_value("OverrideEndDate", "01/01/2020")
        end_error = controls("OverrideEndDate", "OverrideEndDateLongForm", "OverrideEndDateValidation", "OverrideEditorStatus")
        check(selected_override(schedule(), scheduler_id, override_id) == current,
              "End before Start is rejected without changing the Override")
        check(end_error["OverrideEndDate"]["String"] == "01/01/2020" and
              end_error["OverrideEndDateLongForm"]["String"] == "" and
              end_error["OverrideEndDateValidation"]["String"] == "End date must not be before Start date",
              "reversed End remains buffered with a clear error")

        press("DuplicateOverride")
        duplicate_id = selected_id("OverrideSelect")
        set_value("OverrideSelect", choice(override_id, "New Override"))
        restored_buffer = controls("OverrideStartDate", "OverrideEndDate")
        persisted = selected_override(schedule(), scheduler_id, override_id)
        check(restored_buffer["OverrideStartDate"]["String"] == "01/02/2030" and
              restored_buffer["OverrideEndDate"]["String"] == date.fromisoformat(persisted["endDate"]).strftime("%d/%m/%Y"),
              "changing Override discards invalid buffered input and restores persisted values")

        press("SetOverrideRangeOneDay")
        set_value("OverrideStartDate", "1/3/2030")
        set_value("OverrideEndDate", "3/3/2030")
        before = schedule()
        revision = before["revision"]
        set_value("OverrideStartDate", "2/3/2030")
        after = schedule()
        shifted = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and shifted["startDate"] == "2030-03-02" and shifted["endDate"] == "2030-03-04",
              "editing Start preserves three-day duration and commits both dates once")

        revision = after["revision"]
        set_value("OverrideEndDate", "6/3/2030")
        after = schedule()
        changed = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and changed["endDate"] == "2030-03-06",
              "editing End changes duration in one revision")

        revision = after["revision"]
        press("SetOverrideRangeOneDay")
        after = schedule()
        one_day = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and one_day["endDate"] == one_day["startDate"],
              "1 Day atomically sets End equal to Start")
        check(controls("ShiftOverrideRangeBack")["ShiftOverrideRangeBack"]["Disabled"] is True,
              "-1 Day is visually disabled for a one-day range")
        one_day_before = schedule_text()
        press("ShiftOverrideRangeBack")
        check(schedule_text() == one_day_before, "forced -1 Day cannot reduce a range below one day")

        set_value("OverrideEndDate", "4/3/2030")
        before = schedule()
        source = selected_override(before, scheduler_id, override_id)
        revision = before["revision"]
        press("ShiftOverrideRangeBack")
        after = schedule()
        shifted_back = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and shifted_back["startDate"] == "2030-03-02" and shifted_back["endDate"] == "2030-03-03",
              "-1 Day shortens the range by changing only End")
        check(all(shifted_back[field] == source[field] for field in ["id", "label", "type", "enabled", "patternId"]),
              "duration change retains Override identity and non-date fields")

        revision = after["revision"]
        press("ShiftOverrideRangeForward")
        after = schedule()
        shifted_forward = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and shifted_forward["startDate"] == "2030-03-02" and shifted_forward["endDate"] == "2030-03-04",
              "+1 Day extends the range by changing only End")

        revision = after["revision"]
        press("ShiftOverrideStartBackDay")
        after = schedule()
        start_back = selected_override(after, scheduler_id, override_id)
        check(after["revision"] == revision + 1 and start_back["startDate"] == "2030-03-01" and start_back["endDate"] == "2030-03-03",
              "Start -1 Day moves the complete range and preserves duration")
        press("ShiftOverrideStartForwardDay")
        start_forward = selected_override(schedule(), scheduler_id, override_id)
        check(start_forward["startDate"] == "2030-03-02" and start_forward["endDate"] == "2030-03-04",
              "Start +1 Day restores the complete range")
        press("ShiftOverrideStartBackWeek")
        start_week_back = selected_override(schedule(), scheduler_id, override_id)
        check(start_week_back["startDate"] == "2030-02-23" and start_week_back["endDate"] == "2030-02-25",
              "Start -1 Wk moves both dates by seven calendar days")
        press("ShiftOverrideStartForwardWeek")
        start_week_forward = selected_override(schedule(), scheduler_id, override_id)
        check(start_week_forward["startDate"] == "2030-03-02" and start_week_forward["endDate"] == "2030-03-04",
              "Start +1 Wk restores both dates by seven calendar days")

        check(controls("ShiftOverrideEndBackWeek")["ShiftOverrideEndBackWeek"]["Disabled"] is True,
              "End -1 Wk is disabled when fewer than seven days can be removed")
        week_before = schedule_text()
        press("ShiftOverrideEndBackWeek")
        check(schedule_text() == week_before, "forced End -1 Wk cannot move End before Start")
        press("ShiftOverrideEndForwardWeek")
        end_week_forward = selected_override(schedule(), scheduler_id, override_id)
        check(end_week_forward["startDate"] == "2030-03-02" and end_week_forward["endDate"] == "2030-03-11",
              "End +1 Wk extends duration by seven calendar days")
        press("ShiftOverrideEndBackWeek")
        end_week_back = selected_override(schedule(), scheduler_id, override_id)
        check(end_week_back["startDate"] == "2030-03-02" and end_week_back["endDate"] == "2030-03-04",
              "End -1 Wk shortens duration by seven calendar days")

        press("ResolveTestTime")
        generated_date = json.loads(controls("GlobalSchedulerStatus")["GlobalSchedulerStatus"]["String"])["generatedAt"][:10]
        revision = schedule()["revision"]
        press("SetOverrideRangeToday")
        today_model = schedule()
        today_range = selected_override(today_model, scheduler_id, override_id)
        check(today_model["revision"] == revision + 1 and today_range["startDate"] == generated_date,
              "Today uses the Core/emulator local date and commits once")
        check((date.fromisoformat(today_range["endDate"]) - date.fromisoformat(today_range["startDate"])).days == 2,
              "Today preserves the existing inclusive duration")

        set_preference("ISO", "yyyy-mm-dd")
        press("SetOverrideRangeOneDay")
        for entered, expected_end, label in [
            ("2028-02-28", "2028-02-29", "leap-day boundary"),
            ("2030-12-31", "2031-01-01", "year boundary"),
            ("2030-03-30", "2030-03-31", "configured spring DST boundary"),
        ]:
            set_value("OverrideStartDate", entered)
            press("SetOverrideRangeOneDay")
            press("ShiftOverrideRangeForward")
            result = selected_override(schedule(), scheduler_id, override_id)
            check(result["startDate"] == entered and result["endDate"] == expected_end and
                  (date.fromisoformat(result["endDate"]) - date.fromisoformat(result["startDate"])).days == 1,
                  f"{label} duration extension uses normalized calendar days")

        set_preference("MDY", "mm/dd/yyyy")
        preference_before_reload = preference_text()
        schedule_before_reload = schedule_text()
        qrc("deploy", RUNTIME_PROVIDER, str(ROOT / "src/runtime.lua"))
        time.sleep(0.7)
        check(preference_text() == preference_before_reload and schedule_text() == schedule_before_reload,
              "date preference and ScheduleData survive runtime reload byte-for-byte")
        check(controls("OverrideStartDate")["OverrideStartDate"]["String"].count("/") == 2,
              "runtime reload renders dates using the persisted preference")

        set_value("OverrideSelect", choice(duplicate_id, "New Override Copy"))
        set_value("OverrideStartDate", "not-a-date")
        press("AddScheduler")
        empty_scheduler_id = selected_id("SchedulerSelect")
        set_value("SchedulerSelect", choice(scheduler_id, "Override Date QRC Test"))
        set_value("OverrideSelect", choice(duplicate_id, "New Override Copy"))
        check(controls("OverrideStartDate")["OverrideStartDate"]["String"] != "not-a-date",
              "changing Scheduler context discards invalid buffered input safely")

        set_value("SchedulerSelect", choice(empty_scheduler_id, "New Scheduler"))
        empty_before = schedule_text()
        press("ShiftOverrideRangeForward")
        check(schedule_text() == empty_before, "forced range action with no Override is harmless")
        set_value("SchedulerSelect", choice(scheduler_id, "Override Date QRC Test"))

        final_model = schedule()
        check(no_runtime_keys(final_model), "runtime-only date buffers and indexes are absent from ScheduleData")
        check("automatic Event execution is off" in controls("Status")["Status"]["String"],
              "automatic scheduled callback execution remains disabled")
        final_health = controls("script.status", "script.error.count")
        final_runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
        check(final_health["script.status"]["String"] == "OK" and final_health["script.error.count"]["Value"] == 0 and
              final_runtime_health["script.status"]["String"] == "OK" and final_runtime_health["script.error.count"]["Value"] == 0,
              "both scripts finish OK with zero errors")

    finally:
        set_value("ScheduleData", original_schedule)
        set_value("DateFormatPreference", original_preference)
        restored_schedule = schedule_text() == original_schedule
        restored_preference = preference_text() == original_preference
        print(f"RESTORE ScheduleData: {'PASS' if restored_schedule else 'FAIL'}")
        print(f"RESTORE DateFormatPreference: {'PASS' if restored_preference else 'FAIL'}")
        if restored_schedule:
            assertions.append("original ScheduleData restored byte-for-byte")
        if restored_preference:
            assertions.append("original date preference restored byte-for-byte")

    if not restored_schedule or not restored_preference:
        raise AssertionError("persistent values were not restored byte-for-byte")
    print(f"RESULT: {len(assertions)} assertions passed")


if __name__ == "__main__":
    main()
