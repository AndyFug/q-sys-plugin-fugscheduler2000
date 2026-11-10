#!/usr/bin/env python3
"""Validate that one pre-provisioned corrupt physical-Core backup file is isolated."""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

HOST = os.environ.get("QSYS_HOST", "")
EXPECTED_DESIGN = os.environ.get("QSYS_DESIGN_NAME", "")
CORRUPT_FILE = os.environ.get("FUGSCHEDULER_CORRUPT_BACKUP_FILE", "")
COMPONENT = os.environ.get("FUGSCHEDULER_COMPONENT", "AndyFugFugScheduler2000")
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


def controls(*names: str) -> dict[str, dict]:
    result = qrc("get", COMPONENT, *names)
    return {item["Name"]: item for item in result["Controls"]}


def set_value(name: str, value: object, delay: float = 0.6) -> None:
    qrc("set", COMPONENT, name, json.dumps(value))
    time.sleep(delay)


def press(name: str, delay: float = 0.7) -> None:
    set_value(name, True, 0.15)
    set_value(name, False, delay)


def choice(identifier: str, text: str) -> str:
    return json.dumps({"Text": text, "Id": identifier}, separators=(",", ":"))


def main() -> None:
    if not HOST or not EXPECTED_DESIGN or not CORRUPT_FILE:
        raise SystemExit(
            "Set QSYS_HOST, QSYS_DESIGN_NAME, and FUGSCHEDULER_CORRUPT_BACKUP_FILE. "
            "Use only a safe non-production physical-Core test design with the corrupt fixture pre-provisioned."
        )

    status = qrc("status")
    check(status["Platform"] != "Emulator" and status.get("IsEmulator") is not True,
          "expected a physical Core, not Designer Emulator")
    check(status["State"] == "Active" and status["DesignName"] == EXPECTED_DESIGN,
          "expected physical-Core test design is active")

    initial = controls(
        "ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupTransfer",
        "ConfigurationBackupFileSelect", "ConfigurationBackupFileStatus",
        "RefreshConfigurationBackupFiles", "ImportConfigurationBackupFile",
        "AutomaticExecutionEnabled", "script.status", "script.error.count",
    )
    check(initial["AutomaticExecutionEnabled"]["Value"] < 0.5,
          "Master Enable is off before selected-file isolation testing")
    original_schedule = initial["ScheduleData"]["String"]
    original_catalogue = initial["ConfigurationBackupCatalog"]["String"]
    original_clipboard = initial["ConfigurationBackupTransfer"]["String"]

    try:
        press("RefreshConfigurationBackupFiles")
        set_value("ConfigurationBackupFileSelect", choice(CORRUPT_FILE, CORRUPT_FILE), 0.4)
        press("ImportConfigurationBackupFile")
        rejected = controls(
            "ScheduleData", "ConfigurationBackupCatalog", "ConfigurationBackupTransfer",
            "ConfigurationBackupFileStatus",
        )
        check(rejected["ScheduleData"]["String"] == original_schedule,
              "corrupt selected file does not change live ScheduleData")
        check(rejected["ConfigurationBackupCatalog"]["String"] == original_catalogue,
              "corrupt selected file does not add or alter Saved Configurations")
        check(rejected["ConfigurationBackupTransfer"]["String"] == original_clipboard,
              "corrupt selected file leaves the JSON clipboard unchanged")
        status_text = rejected["ConfigurationBackupFileStatus"]["String"].lower()
        check("rejected" in status_text and "catalogue and live configuration unchanged" in status_text,
              "selected corrupt file reports an isolated validation rejection")
    finally:
        set_value("AutomaticExecutionEnabled", False, 0.2)
        current_clipboard = controls("ConfigurationBackupTransfer")["ConfigurationBackupTransfer"]["String"]
        if current_clipboard != original_clipboard:
            set_value("ConfigurationBackupTransfer", original_clipboard, 0.3)

    health = controls("script.status", "script.error.count")
    check(health["script.status"]["String"] == "OK" and health["script.error.count"]["Value"] == 0,
          "plugin finishes healthy after corrupt selected-file rejection")
    print(f"SUCCESS: {len(assertions)} physical backup-file isolation assertions passed")


if __name__ == "__main__":
    main()
