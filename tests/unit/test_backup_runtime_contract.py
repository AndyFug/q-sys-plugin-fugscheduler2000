#!/usr/bin/env python3
"""Offline regression checks for the consolidated backup runtime contract."""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "src/runtime.lua"


def function_body(source: str, name: str) -> str:
    marker = f"function FugSchedulerRuntime.{name}("
    start = source.index(marker)
    match = re.search(r"\nfunction FugSchedulerRuntime\.[A-Za-z0-9_]+\(", source[start + len(marker):])
    end = len(source) if match is None else start + len(marker) + match.start()
    return source[start:end]


def main() -> None:
    source = RUNTIME.read_text()
    names = re.findall(r"^function FugSchedulerRuntime\.([A-Za-z0-9_]+)\(", source, re.MULTILINE)
    duplicates = sorted(name for name, count in Counter(names).items() if count > 1)
    if duplicates:
        raise AssertionError(f"duplicate runtime implementations remain: {duplicates}")

    initialise = function_body(source, "initialize")
    if "ConfigurationBackupCatalog.String" in initialise or "refreshBackupList" in initialise:
        raise AssertionError("essential startup must not synchronously decode the backup catalogue")
    administration = function_body(source, "initialiseBackupAdministration")
    deferred_refresh = function_body(source, "scheduleBackupRefresh")
    if "scheduleBackupRefresh" not in administration:
        raise AssertionError("Admin initialisation must automatically schedule catalogue metadata refresh")
    if "Timer.CallAfter" not in deferred_refresh or "refreshBackupList" not in deferred_refresh:
        raise AssertionError("automatic catalogue refresh must run in its own deferred execution slice")

    selection = function_body(source, "inspectSelectedBackup")
    if "json.decode" in selection or "validateSchedule" in selection or "loadBackupEnvelope" in selection:
        raise AssertionError("Saved Configuration selection must remain metadata-only")

    file_refresh = function_body(source, "refreshBackupFileList")
    if "json.load" in file_refresh or "readBackupFile" in file_refresh or "validateBackupEnvelope" in file_refresh:
        raise AssertionError("file refresh must list filenames without opening backup files")

    file_import = function_body(source, "importSelectedBackupFile")
    validate_at = file_import.index("validateBackupEnvelope")
    persist_at = file_import.index("persistControlBackupCatalogue")
    confirm_at = file_import.index('pendingBackupAction = {type = "load"')
    if not (validate_at < persist_at < confirm_at):
        raise AssertionError("selected files must validate, persist to the catalogue, then arm confirmed loading")
    if 'setText("ConfigurationBackupTransfer"' in file_import or "Controls.ScheduleData.String" in file_import:
        raise AssertionError("physical file import must bypass the clipboard and direct live installation")

    import_body = function_body(source, "importBackupTransfer")
    if import_body.index("validateBackupEnvelope") > import_body.index("persistControlBackupCatalogue"):
        raise AssertionError("clipboard imports must validate before catalogue insertion")
    if "Controls.ScheduleData.String" in import_body or "loadBackup(" in import_body:
        raise AssertionError("clipboard import must never change live ScheduleData")

    print("SUCCESS: consolidated backup runtime contract checks passed")


if __name__ == "__main__":
    main()
