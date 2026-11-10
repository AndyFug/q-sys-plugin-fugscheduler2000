#!/usr/bin/env python3
"""Validate persistent Saved Configurations, JSON clipboard flow, and restoration."""

from __future__ import annotations

import json
import socket
import subprocess
import time
from copy import deepcopy
from datetime import datetime
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


def choice(identifier: str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def controls(*names: str, component: str = COMPONENT) -> dict[str, dict]:
    result = qrc("get", component, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.7) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def set_large_text(name: str, value: str, delay: float = 0.7) -> None:
    """Set large Text values directly over QRC without an OS command-line size limit."""
    request_id = 9101
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


def ensure_design() -> None:
    status = qrc("status")
    check(status["Platform"] == "Emulator" and status["State"] == "Active" and status.get("IsEmulator") is True,
          "expected active Emulator")
    check(status["DesignName"] in {"fugscheduler_test", "fugscheduler2000_test"},
          "expected FugScheduler test design is active")


def main() -> None:
    ensure_design()
    required = [
        "ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupSelect",
        "ConfigurationBackupName", "SaveConfigurationBackup",
        "LoadConfigurationBackup", "DeleteConfigurationBackup", "ConfirmConfigurationBackupAction",
        "CancelConfigurationBackupAction", "ConfigurationBackupSummary", "ConfigurationBackupFileStatus",
        "ConfigurationBackupTransfer", "ExportConfigurationBackup", "ImportConfigurationBackup",
        "ConfigurationBackupFileSelect", "RefreshConfigurationBackupFiles", "SaveConfigurationBackupFile",
        "ImportConfigurationBackupFile", "ConfigurationBackupCatalogStatus",
        "ConfigurationBackupStatus", "AutomaticExecutionEnabled", "reload",
    ]
    initial = controls(*required)
    check(all(name in initial for name in required), "all Saved Configuration and portable-transfer controls exist")
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5, "Master Enable is off before backup testing")
    original_schedule = initial["ScheduleData"]["String"]
    original_catalog = initial["ConfigurationBackupCatalog"]["String"]
    original_transfer = initial["ConfigurationBackupTransfer"]["String"]
    backup_name = "QRC Persistent Backup " + datetime.now().strftime("%H%M%S")

    try:
        press("reload", 0.4)
        time.sleep(3.0)
        startup = controls("ConfigurationBackupStatus", "ConfigurationBackupCatalog",
                           "ConfigurationBackupCatalogStatus")
        check("ignored" in startup["ConfigurationBackupStatus"]["String"].lower() or
              "/10" in startup["ConfigurationBackupStatus"]["String"],
              "startup automatically loads catalogue metadata without validating stored schedules")
        check(startup["ConfigurationBackupCatalog"]["String"] == original_catalog,
              "automatic startup refresh does not rewrite the persistent catalogue")

        set_value("ConfigurationBackupName", backup_name)
        press("SaveConfigurationBackup")
        saved = controls("ConfigurationBackupCatalog", "ConfigurationBackupSummary", "ConfigurationBackupStatus")
        catalogue = json.loads(saved["ConfigurationBackupCatalog"]["String"])
        item = next(entry for entry in catalogue["configurations"] if entry["name"] == backup_name)
        check(catalogue["schemaVersion"] == 2 and isinstance(item["scheduleJson"], str),
              "Saved Configuration persists metadata plus opaque schedule JSON")
        check(json.loads(item["scheduleJson"]) == json.loads(original_schedule),
              "opaque schedule JSON contains the complete Scheduler and Slot configuration")
        check("parsed and validated only after confirmed Load" in saved["ConfigurationBackupSummary"]["String"],
              "selection displays metadata without parsing the stored schedule")

        set_value("ConfigurationBackupName", backup_name)
        before_overwrite = saved["ConfigurationBackupCatalog"]["String"]
        press("SaveConfigurationBackup")
        overwrite_armed = controls("ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        check(overwrite_armed["ConfigurationBackupCatalog"]["String"] == before_overwrite and
              "overwrite" in overwrite_armed["ConfigurationBackupStatus"]["String"].lower(),
              "duplicate-name save arms overwrite without mutating the catalogue")
        press("CancelConfigurationBackupAction")
        check(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"] == before_overwrite,
              "cancelling overwrite preserves opaque stored schedule JSON")

        press("reload", 0.4)
        time.sleep(3.0)
        after_restart = controls("ConfigurationBackupStatus", "ConfigurationBackupCatalog",
                                 "ConfigurationBackupSummary")
        check(after_restart["ConfigurationBackupCatalog"]["String"] == saved["ConfigurationBackupCatalog"]["String"] and
              backup_name in after_restart["ConfigurationBackupSummary"]["String"],
              "Saved Configurations automatically repopulate after runtime restart")

        press("ExportConfigurationBackup")
        exported_text = controls("ConfigurationBackupTransfer")["ConfigurationBackupTransfer"]["String"]
        exported = json.loads(exported_text)
        check(exported["name"] == backup_name and exported["schedule"] == json.loads(original_schedule),
              "Copy Selected to JSON produces a portable complete backup envelope")

        before_bad_import = controls("ScheduleData", "ConfigurationBackupCatalog")
        set_value("ConfigurationBackupTransfer", '{"schemaVersion":1,"name":"Corrupt"}')
        press("ImportConfigurationBackup")
        rejected = controls("ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        check(rejected["ScheduleData"]["String"] == before_bad_import["ScheduleData"]["String"] and
              rejected["ConfigurationBackupCatalog"]["String"] == before_bad_import["ConfigurationBackupCatalog"]["String"] and
              "rejected" in rejected["ConfigurationBackupStatus"]["String"].lower(),
              "invalid clipboard JSON is rejected before entering the catalogue or live state")

        corrupt_catalogue = deepcopy(catalogue)
        corrupt_catalogue["configurations"][0]["scheduleJson"] = '{"schemaVersion":2'
        corrupt_catalogue_text = json.dumps(corrupt_catalogue, separators=(",", ":"))
        set_value("ConfigurationBackupCatalog", corrupt_catalogue_text, 0.7)
        press("LoadConfigurationBackup")
        before_corrupt_confirm = controls("ScheduleData", "ConfigurationBackupTransfer")
        press("ConfirmConfigurationBackupAction")
        corrupt_rejected = controls("ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupTransfer",
                                    "ConfigurationBackupStatus")
        check(corrupt_rejected["ScheduleData"]["String"] == before_corrupt_confirm["ScheduleData"]["String"] and
              corrupt_rejected["ConfigurationBackupCatalog"]["String"] == corrupt_catalogue_text and
              corrupt_rejected["ConfigurationBackupTransfer"]["String"] == before_corrupt_confirm["ConfigurationBackupTransfer"]["String"] and
              "load rejected" in corrupt_rejected["ConfigurationBackupStatus"]["String"].lower(),
              "corrupt selected schedule is isolated until confirmed Load and changes no persistent live state")
        press("CancelConfigurationBackupAction")
        set_value("ConfigurationBackupCatalog", saved["ConfigurationBackupCatalog"]["String"], 0.7)

        portable = deepcopy(exported)
        portable["id"] = "10000000-0000-4000-8000-000000000001"
        portable["name"] = "QRC Imported Portable Backup"
        portable["schedule"]["schedulers"][0]["label"] = "Imported but not active"
        before_valid_import = controls("ScheduleData", "ConfigurationBackupCatalog")
        set_value("ConfigurationBackupTransfer", json.dumps(portable, separators=(",", ":")))
        press("ImportConfigurationBackup")
        imported = controls("ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        imported_catalogue = json.loads(imported["ConfigurationBackupCatalog"]["String"])
        check(imported["ScheduleData"]["String"] == before_valid_import["ScheduleData"]["String"] and
              any(entry["name"] == portable["name"] for entry in imported_catalogue["configurations"]),
              "valid clipboard import adds a fully validated backup without changing live ScheduleData")

        set_value("ConfigurationBackupSelect", choice(item["id"], f"{backup_name} — {item['savedAt']}"), 0.5)
        changed = json.loads(original_schedule)
        changed["revision"] = int(changed.get("revision", 0)) + 1
        changed["schedulers"][0]["label"] = "QRC Backup Changed Label"
        for slot in changed["schedulerSlots"]:
            slot["enabled"] = False
            slot["paused"] = False
            slot.pop("pauseIntent", None)
        set_value("ScheduleData", json.dumps(changed, separators=(",", ":")), 1.2)
        press("LoadConfigurationBackup")
        set_value("AutomaticExecutionEnabled", True, 0.7)
        press("ConfirmConfigurationBackupAction")
        guarded = controls("ScheduleData", "ConfigurationBackupStatus")
        check(json.loads(guarded["ScheduleData"]["String"])["schedulers"][0]["label"] == "QRC Backup Changed Label" and
              "master enable" in guarded["ConfigurationBackupStatus"]["String"].lower(),
              "confirmed load is rejected while Master Enable is on")
        set_value("AutomaticExecutionEnabled", False, 0.5)
        press("ConfirmConfigurationBackupAction", 1.4)
        restored = json.loads(controls("ScheduleData")["ScheduleData"]["String"])
        expected = json.loads(original_schedule)
        restored_revision = restored.pop("revision", None)
        expected.pop("revision", None)
        check(restored == expected and restored_revision > changed["revision"],
              "confirmed load parses, validates, and atomically installs only the selected backup")

        current_catalogue = json.loads(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"])
        base_item = deepcopy(current_catalogue["configurations"][0])
        full_items = []
        for index in range(10):
            entry = deepcopy(base_item)
            entry["id"] = f"00000000-0000-4000-8000-{index + 1:012d}"
            entry["name"] = f"Limit Fixture {index + 1}"
            full_items.append(entry)
        full_catalogue_text = json.dumps({"schemaVersion": 2, "configurations": full_items}, separators=(",", ":"))
        set_large_text("ConfigurationBackupCatalog", full_catalogue_text, 0.9)
        set_value("ConfigurationBackupName", "Eleventh Backup")
        press("SaveConfigurationBackup")
        limited = controls("ConfigurationBackupCatalog", "ConfigurationBackupStatus")
        check(limited["ConfigurationBackupCatalog"]["String"] == full_catalogue_text and
              "maximum of 10" in limited["ConfigurationBackupStatus"]["String"].lower(),
              "ten-backup catalogue limit rejects an eleventh entry without mutation")

        set_value("ConfigurationBackupCatalog", saved["ConfigurationBackupCatalog"]["String"], 0.9)
        press("DeleteConfigurationBackup")
        press("ConfirmConfigurationBackupAction")
        deleted = json.loads(controls("ConfigurationBackupCatalog")["ConfigurationBackupCatalog"]["String"])
        check(all(entry["name"] != backup_name for entry in deleted["configurations"]),
              "confirmed Delete removes only the selected Saved Configuration")

        file_controls = controls("RefreshConfigurationBackupFiles", "SaveConfigurationBackupFile",
                                 "ImportConfigurationBackupFile", "ConfigurationBackupFileStatus")
        check(file_controls["RefreshConfigurationBackupFiles"]["Disabled"] and
              file_controls["SaveConfigurationBackupFile"]["Disabled"] and
              file_controls["ImportConfigurationBackupFile"]["Disabled"] and
              "unavailable" in file_controls["ConfigurationBackupFileStatus"]["String"].lower(),
              "physical backup-file actions are clearly unavailable in Designer Emulator")
    finally:
        set_value("AutomaticExecutionEnabled", False, 0.3)
        set_value("ScheduleData", original_schedule, 1.1)
        set_value("ConfigurationBackupCatalog", original_catalog, 0.8)
        set_value("ConfigurationBackupTransfer", original_transfer, 0.4)
        final = controls("ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupTransfer",
                         "AutomaticExecutionEnabled")
        restored = (final["ScheduleData"]["String"] == original_schedule and
                    final["ConfigurationBackupCatalog"]["String"] == original_catalog and
                    final["ConfigurationBackupTransfer"]["String"] == original_transfer and
                    final["AutomaticExecutionEnabled"]["Value"] < 0.5)
        print(f"RESTORE: {'PASS' if restored else 'FAIL'} persistent Admin values restored byte-for-byte")
        if not restored:
            raise AssertionError("failed to restore Admin backup test state")

    plugin_health = controls("script.status", "script.error.count")
    runtime_health = controls("script.status", "script.error.count", component=RUNTIME_PROVIDER)
    check(plugin_health["script.status"]["String"] == "OK" and plugin_health["script.error.count"]["Value"] == 0 and
          runtime_health["script.status"]["String"] == "OK" and runtime_health["script.error.count"]["Value"] == 0,
          "plugin and runtime provider finish healthy")
    print(f"SUCCESS: {len(assertions)} persistent backup assertions passed")


if __name__ == "__main__":
    main()
