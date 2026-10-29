#!/usr/bin/env python3
"""Validate named configuration backups and restore all persistent values byte-for-byte."""

from __future__ import annotations

import json
import subprocess
import time
from copy import deepcopy
from pathlib import Path

HOST = "10.211.55.4"
COMPONENT = "AndyFugFugScheduler2000"
RUNTIME_PROVIDER = "SchedulerRuntimeProvider"
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


def set_value(name: str, value: object, delay: float = 0.7) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def press(name: str, delay: float = 0.7) -> None:
    set_value(name, True, 0.15)
    set_value(name, False, delay)


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] == "fugscheduler2000_test", "expected design is active")


def main() -> None:
    ensure_design()
    required = [
        "ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupSelect",
        "ConfigurationBackupName", "SaveConfigurationBackup", "LoadConfigurationBackup",
        "DeleteConfigurationBackup", "ConfirmConfigurationBackupAction", "CancelConfigurationBackupAction",
        "ConfigurationBackupSummary", "ConfigurationBackupFileStatus", "ConfigurationBackupStatus",
        "AutomaticExecutionEnabled",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "all Admin backup controls exist")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable is off before backup testing")
    original_schedule = initial["ScheduleData"]["String"]
    original_catalog = initial["ConfigurationBackupCatalog"]["String"]
    backup_name = "QRC Admin Backup Test"

    try:
        set_value("ConfigurationBackupName", backup_name)
        press("SaveConfigurationBackup")
        saved_catalog_text = controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"]
        saved_catalog = json.loads(saved_catalog_text)
        saved = next(item for item in saved_catalog["configurations"] if item["name"] == backup_name)
        check(saved["schedule"] == json.loads(original_schedule),
              "new named backup contains the complete Scheduler and Slot configuration")
        check("emulation" in controls("ConfigurationBackupFileStatus")["ConfigurationBackupFileStatus"]["String"].lower(),
              "Admin reports that the Core file mirror is unavailable in emulation")

        press("DeleteConfigurationBackup")
        delete_armed = controls("ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        check(delete_armed["ConfigurationBackupCatalog"]["String"] == saved_catalog_text and
              "delete" in delete_armed["ConfigurationBackupStatus"]["String"].lower(),
              "Delete arms confirmation without changing the catalogue")
        press("CancelConfigurationBackupAction")
        check(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"] == saved_catalog_text,
              "cancelling Delete preserves the selected backup")

        changed = json.loads(original_schedule)
        changed["revision"] = int(changed.get("revision", 0)) + 1
        changed["schedulers"][0]["label"] = "QRC Backup Changed Label"
        set_value("ScheduleData", json.dumps(changed, separators=(",", ":")), 1.2)

        set_value("ConfigurationBackupName", backup_name)
        before_overwrite = controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"]
        press("SaveConfigurationBackup")
        armed = controls("ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        check(armed["ConfigurationBackupCatalog"]["String"] == before_overwrite and
              "overwrite" in armed["ConfigurationBackupStatus"]["String"].lower(),
              "saving an existing name arms overwrite without changing the catalogue")
        press("CancelConfigurationBackupAction")
        check(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"] == before_overwrite,
              "cancelling overwrite preserves the existing backup")

        press("LoadConfigurationBackup")
        press("ConfirmConfigurationBackupAction", 1.4)
        restored = json.loads(controls("ScheduleData")["ScheduleData"]["String"])
        original_model = json.loads(original_schedule)
        restored_without_revision = deepcopy(restored)
        original_without_revision = deepcopy(original_model)
        restored_without_revision.pop("revision", None)
        original_without_revision.pop("revision", None)
        check(restored_without_revision == original_without_revision and
              restored["revision"] > changed["revision"],
              "confirmed load atomically restores the backup with a new local revision")

        changed_again = deepcopy(changed)
        changed_again["revision"] = restored["revision"] + 1
        for slot in changed_again["schedulerSlots"]:
            slot["enabled"] = False
            slot["paused"] = False
            slot.pop("pauseIntent", None)
        set_value("ScheduleData", json.dumps(changed_again, separators=(",", ":")), 1.0)
        set_value("AutomaticExecutionEnabled", True, 0.8)
        press("LoadConfigurationBackup")
        press("ConfirmConfigurationBackupAction")
        guarded = controls("ScheduleData", "ConfigurationBackupStatus")
        check(json.loads(guarded["ScheduleData"]["String"])["schedulers"][0]["label"] == "QRC Backup Changed Label" and
              "master enable" in guarded["ConfigurationBackupStatus"]["String"].lower(),
              "restore is rejected while Master Enable is on")
        set_value("AutomaticExecutionEnabled", False)
        press("CancelConfigurationBackupAction")

        press("DeleteConfigurationBackup")
        press("ConfirmConfigurationBackupAction")
        deleted_catalog = json.loads(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"])
        check(all(item["name"] != backup_name for item in deleted_catalog["configurations"]),
              "confirmed Delete removes the selected configuration")
    finally:
        set_value("AutomaticExecutionEnabled", False, 0.3)
        set_value("ScheduleData", original_schedule, 1.2)
        set_value("ConfigurationBackupCatalog", original_catalog, 1.0)
        final = controls("ScheduleData", "ConfigurationBackupCatalog", "AutomaticExecutionEnabled")
        restored = (final["ScheduleData"]["String"] == original_schedule and
                    final["ConfigurationBackupCatalog"]["String"] == original_catalog and
                    final["AutomaticExecutionEnabled"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} ScheduleData and backup catalogue restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore Admin backup test state")

    plugin_health = controls("script.status", "script.error.count")
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(plugin_health["script.status"]["String"] == "OK" and plugin_health["script.error.count"]["Value"] == 0 and
          runtime_health["script.status"]["String"] == "OK" and runtime_health["script.error.count"]["Value"] == 0,
          "plugin and runtime provider finish healthy")
    print(f"SUCCESS: {len(assertions)} Admin backup assertions passed")


if __name__ == "__main__":
    main()
