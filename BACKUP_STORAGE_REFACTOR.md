# Backup Storage and Startup Refactor Handoff

## Purpose

This document captures the findings and implementation plan from live testing on 2026-11-10 so a new session can continue safely.

The current goals are:

1. Preserve reliable plugin cold startup with production-sized persisted data.
2. Use the persistent `ConfigurationBackupCatalog` as the ten-entry primary store on Emulator and physical Cores.
3. Keep catalogue and file processing completely outside the scheduler's critical startup and execution paths.
4. Provide explicit portable JSON and physical-Core file workflows without coupling them to live `ScheduleData`.
5. Retain the Slot Inspector live-status fix and its regression coverage.

Read `AGENTS.md`, `README.md`, `PLAN.md`, `BUILD.md`, `tests/README.md`, the `qsys-plugin-sdk` skill, and the `qsys-deploy` skill before editing or live testing.

---

## Confirmed problem

Designer emulator cold startup fails with:

```text
Fault - 3419: Max execution limits exceeded
```

The failure occurs before the active schedule is installed:

- `Status`: `Scheduler ready; 0/0 assigned Slots enabled; Master Enable ARMED`
- `ScheduleStatus`: `Checking persisted ScheduleData`
- `GlobalSchedulerSlotStatus`: `{}`
- `ConfigurationBackupStatus`: `Loading named configuration backups`
- `RegistryStatus`: `Checking ActionSource evaluator support`

Production-design persistent control sizes observed through QRC:

| Control | Size |
|---|---:|
| `ConfigurationBackupCatalog` | 187,100 characters |
| `ScheduleData` | 51,277 characters |
| `ActionSource` | 4,336 characters |
| `DiagnosticLog` | 11,927 characters |
| `OneShotExecutionLedger` | 33 characters |

`FugSchedulerRuntime.initialize()` currently calls `reloadBackupCatalog()` synchronously before `reloadActions()` and `reloadSchedule()`.

`reloadBackupCatalog()` currently:

1. Decodes the entire catalogue.
2. Calls `validateBackupCatalog()`.
3. Copies the complete catalogue.
4. Fully validates every contained `configuration.schedule` with `validateSchedule()`.
5. Copies and normalises every backup schedule.
6. Retains every decoded schedule in `FugSchedulerRuntime.backupCatalog`.

This work is unnecessary during scheduler startup and is the likely execution-limit trigger.

### Baseline proof

The exact previously committed `0.1.0.33` artifact was restored and tested in the same Designer design. It fails with the same `3419` error. Therefore the failure was not introduced by the pending Slot Inspector fix.

The current Designer design used for testing is:

```text
Host: 10.211.55.4
Design: hpww26_v1.0-dev21
Component: FugScheduler_1
Action provider: FugSchedulerActionProvider_1
```

At handoff time Designer is emulating the faulted `0.1.0.33` baseline. Stop emulation before deploying another `.qplug`.

The physical Core at `172.16.11.15` was not updated with plugin code during this work. Do not modify the physical Core until emulator validation is complete.

---

## Why existing tests missed it

The existing scale tests validate schedule installation, compiled-plan rebuilding, timer polling, and execution performance after the plugin has already started.

They do not validate a cold start with all of the following present simultaneously:

- a production-sized active `ScheduleData`
- a large accumulated backup catalogue
- a populated Action source
- persisted operational state

`validate_admin_backups.py` exercises backup operations using small temporary fixtures and restores the original catalogue. It does not restart the plugin with a large catalogue.

A new cold-start acceptance workflow is required.

---

## First backup architecture response — superseded

This section records the file-primary design that produced validated build `0.1.0.36`. It is historical context only. The authoritative product behaviour is **Second Admin storage design — current handoff** below.

## Target backup architecture

### Active state remains control-backed

The authoritative live configuration remains:

```text
ScheduleData persistent control
```

Backups must never be required for active schedule startup or execution.

### Physical-Core backup storage

Use one self-contained JSON file per backup:

```text
media/FugScheduler2000/backups/
  2026-11-10_182130__site-build__<uuid>.json
  2026-11-10_200500__pre-opening__<uuid>.json
```

Recommended envelope:

```json
{
  "schemaVersion": 1,
  "id": "stable UUID",
  "name": "Site Build",
  "savedAt": "2026-11-10T18:21:30",
  "schedule": {
    "schemaVersion": 2
  }
}
```

Filenames must be sanitised, collision-resistant, and include a stable ID. Do not rely solely on an operator-entered name.

### Admin behaviour

- Plugin startup performs no backup file parsing or validation.
- Admin page initially reports that backups have not been scanned.
- A `Refresh Backups` operation lists backup filenames from the directory.
- Listing files must not parse every contained schedule.
- Selecting a backup may parse only that selected file to display a summary.
- Loading parses and validates only the selected file after confirmation and while Master Enable is off.
- Saving validates/copies the active schedule once and writes one file.
- Deleting removes only the selected file.
- A corrupt backup reports an error for that file and cannot block active scheduler startup.

A small metadata index is optional. If used, it must contain metadata only and must be rebuildable from the directory. It must never contain full schedule objects.

### Emulator and portability caveats

The official Q-SYS SDK JSON example states that file writing does not work in emulation:

```text
../.agents/skills/qsys-plugin-sdk/references/official-sdk/Code Examples/19-JSON-Object.md
```

Recommended handling:

- Abstract backup storage behind a small backend boundary.
- Physical Core backend uses individual files.
- Emulator tests may use an in-memory or explicit import/export-buffer backend.
- Do not restore the production monolithic catalogue as the normal emulator backend.
- Keep an explicit JSON import/export control or workflow for portable transfer.

Also validate before relying on file storage:

1. File deletion API and behaviour.
2. Safe/atomic replacement strategy, preferably temporary file then rename if supported.
3. `dir.get` directory-listing behaviour and returned metadata.
4. Redundant-Core replication behaviour for `media/` files.
5. Core replacement and design migration procedure.

Do not assume `media/` files replicate to a redundant standby Core.

---

## Legacy catalogue migration — superseded

This migration proposal is retained only as historical context. The current design does not require legacy conversion; explicit Refresh may ignore the previous schema and the first new save replaces it.

Existing backups must not be discarded.

The legacy source is the persistent `ConfigurationBackupCatalog` control and, on physical hardware, its current mirror:

```text
media/FugScheduler2000/configurations.json
```

Migration must be explicit and non-blocking.

Recommended approach:

1. Start the scheduler without touching the legacy catalogue.
2. Expose a guarded `Migrate Legacy Backups` admin operation, or provide a one-time external migration utility.
3. Decode the legacy catalogue outside the critical startup path.
4. Write one backup file per legacy configuration, yielding between configurations where necessary.
5. Verify every written file by reading and validating it.
6. Preserve the original legacy control/file until all backups are verified.
7. Record migration status and do not silently repeat completed migration.
8. Only clear/archive the legacy catalogue after explicit operator confirmation.

The legacy catalogue is large enough that even decoding it should be tested against the execution limit. If a single `rapidjson.decode` is unsafe, use an external migration utility against an exported `configurations.json` rather than attempting runtime migration.

A repository copy of the previously edited/exported catalogue exists at:

```text
temp/configurations.json
```

Temporary live-edit snapshots also exist under:

```text
temp/live-edit/
```

These temporary paths are not committed and must not become release dependencies.

---

## Startup refactor

Even after backups move to files, startup should be deliberately phased.

Suggested phases:

1. **Immediate lightweight state**
   - clear diagnostic test time
   - initialise basic status text
   - clear transient choices
   - do not parse backups

2. **Attach handlers**
   - attach control handlers in a later `Timer.CallAfter` execution slice if required

3. **Essential runtime state**
   - load preferences
   - load one-shot ledger
   - load Action registry
   - decode, validate, install, and start the active `ScheduleData`

4. **Nonessential administration**
   - initialise Admin controls
   - wait for an explicit backup refresh or defer a filename-only scan

Use short, generation-safe `Timer.CallAfter` phases. Active scheduling must become healthy even if the backup directory is unavailable or corrupt.

Do not add broad parsing, sorting, validation, or timeline rebuilding to the one-second execution poll.

---

## Pending Slot Inspector fix

A separate live UI bug was identified:

- Scheduler Slots overview used the live per-Slot runtime plan correctly.
- Slot Inspector could show stale Current/Next information because `resolutionResultsById` was not refreshed by `publishLiveRuntimeStatus()`.
- `publishLiveRuntimeStatus()` also performed a final publish based on the Scheduler Definitions editor selection rather than the Slot Inspector selection.

The current local source change in `src/runtime.lua`:

1. Builds `resultsById` while already creating live scheduler statuses.
2. Assigns it to `FugSchedulerRuntime.resolutionResultsById` before `publishGlobalStatus()` refreshes the Inspector.
3. Removes the redundant final `publishResolution()` based on `selectedScheduler()`.

This version does not add another resolution pass; it reuses results already calculated for live status publishing.

`tests/qrc/validate_execution.py` has pending regression coverage that deliberately:

- selects one Scheduler Definition in the editor
- selects a different Scheduler Slot in Slot Inspector
- executes a real event edge containing a deliberately failing callback
- confirms Slot Inspector and overview both advance Current/Next correctly

Keep this fix and regression test while performing the backup/startup refactor.

---

## Current repository state

Modified tracked files at handoff:

```text
FugScheduler2000.qplug
src/info.lua
src/runtime.lua
tests/qrc/validate_execution.py
```

Local source metadata currently represents failed test build:

```text
Version:      0.1.0
BuildVersion: 0.1.0.35
BuildDate:    2026-11-10T20:04:30Z
```

Current local generated artifact:

```text
FugScheduler2000.qplug
SHA-256 ba2af1373d40390ab69271c90f07348b16bdb45a07039e36a9f0682c9e103842
```

Current Designer plugin directory contains exact baseline `0.1.0.33`:

```text
/qsys-plugins/FugScheduler2000.qplug
SHA-256 d4ddfb27bbb5c8b53c42bdf88691098388a144017f24e96f8141484571c43969
```

A baseline copy is also at:

```text
temp/live-edit/FugScheduler2000-build33.qplug
```

Do not deploy while Designer is emulating. Stop emulation, compile a new numbered build intentionally, deploy, restart emulation, then verify QRC status and script health.

---

## Proposed implementation order

### Phase 1: restore cold startup

- Remove `reloadBackupCatalog()` from the essential synchronous startup path.
- Phase startup so active Actions and `ScheduleData` load independently of Admin backups.
- Admin controls should safely show `Backups not scanned` when no backup backend is loaded.
- Compile and deploy a new numbered emulator build.
- Confirm `script.status = OK`, zero errors, correct assigned Slot count, and active schedule resolution.

### Phase 2: file backend

- Add a backup storage abstraction.
- Implement physical-Core directory creation and filename listing.
- Implement one-file save and selected-file load.
- Validate file deletion and replacement APIs before implementing delete/overwrite.
- Ensure every file operation is isolated with `pcall` and concise error reporting.

### Phase 3: Admin UI adaptation

- Add `Refresh Backups`.
- Show filename/metadata without parsing all schedules.
- Parse one selected file for summary only when needed.
- Preserve overwrite/load/delete confirmation guards.
- Keep Master Enable load guard.

### Phase 4: migration and import/export

- Add guarded legacy migration or an external migration utility.
- Add portable selected-backup export/import workflow.
- Document Core replacement and redundant-pair handling.

### Phase 5: tests

- Update `tests/qrc/validate_admin_backups.py` for the new backend boundary.
- Add cold-start validation with production-sized persistence.
- Retain byte-for-byte restoration rules for control-backed state.
- Add selected-file corruption tests.
- Add tests proving backup failures do not affect active schedule execution.
- Run the pending Slot Inspector callback-failure regression.
- Re-run execution, scale, logging, overview, pause, override, and admin suites.

---

## First-response acceptance criteria — superseded

These criteria describe the build-`0.1.0.36` file-primary response. Use the second-design requirements and current local-source state below for new work.

1. Plugin cold-starts with the current 51 KB active schedule and 187 KB legacy catalogue present.
2. Active scheduling starts without parsing or validating backups.
3. Backup storage failure cannot fault or inhibit the scheduler.
4. Startup and all runtime callbacks remain below Q-SYS execution limits.
5. Admin refresh lists individual backup files without validating every schedule.
6. Only the selected backup is parsed and validated for summary/load.
7. Corrupt backup files are isolated and clearly reported.
8. Existing legacy backups are preserved and can be migrated safely.
9. Slot Inspector Current/Next remains tied to its selected Slot even when the Scheduler Definitions editor selects something else and an Action callback fails.
10. Emulator and physical-Core behaviour differences are documented and tested where possible.
11. No physical-Core deployment occurs until emulator cold-start, regression, and scale validation pass.

---

## First-response implementation update — superseded

The source now phases handler attachment, preferences/ledger loading, Action loading, active `ScheduleData` installation, and nonessential Admin initialisation through generation-checked `Timer.CallAfter` slices. Backup administration starts as **Backups not scanned** and never reads `ConfigurationBackupCatalog` during startup.

The new backend stores one immutable JSON envelope per backup under `media/FugScheduler2000/backups/` on physical Cores. Refresh reads directory entries and generated filename metadata only. Selection, export, and confirmed load parse only the selected file. Designer Emulator uses session-memory envelopes with explicit JSON export/import because official SDK file writes are unavailable in emulation.

Physical overwrite and deletion are deliberately disabled until atomic replacement and deletion APIs are validated. New names create new collision-resistant files, so ordinary save/import does not rely on replacement. The legacy persistent catalogue remains unchanged and unparsed; `tools/migrate_legacy_backups.py` provides an external verified, no-replacement conversion path.

Redundant-Core `media/` replication has not been validated in this repository. The current product decision is to assume shared media provisionally, but this remains a deployment risk requiring physical redundant-pair testing before release.

---

## Second Admin storage design — current handoff

After emulator validation of build `0.1.0.36`, the Admin storage design changed again based on operator workflow feedback.

### Agreed product behaviour

- `ConfigurationBackupCatalog` is again the persistent primary store on both Designer Emulator and physical Cores.
- The catalogue is limited to **10 Saved Configurations**.
- Essential startup loads Actions, active `ScheduleData`, operational state, and Scheduler plans before any catalogue work.
- The new catalogue schema stores metadata plus each complete schedule as an opaque `scheduleJson` string. A deferred post-startup slice automatically decodes catalogue metadata/strings and maintains the Saved Configurations list, but does not decode or semantically validate each stored schedule.
- Selecting a Saved Configuration is metadata-only. Confirmed **Load Configuration** parses and validates only the selected `scheduleJson` before atomically installing it.
- Clipboard import parses and validates the complete backup before adding it to the catalogue. It never changes live ScheduleData directly.
- The right Admin section remains a Node-RED-style JSON clipboard for copying a selected Saved Configuration out and pasting/importing a portable backup in.
- A separate **Backup Files** ListBox is required on physical Cores. Refresh lists any `.json` filenames without opening them.
- **Export Configuration File** writes the selected control-backed backup as a new individual JSON file.
- **Import Configuration File** opens only the selected file, parses and validates it as a FugScheduler backup, adds it to Saved Configurations, and arms the shared Confirm/Cancel load flow. It bypasses the JSON clipboard and does not change the live schedule until confirmed with Master Enable off.
- Physical file overwrite and deletion remain disabled until atomic replacement and deletion APIs are validated.
- Legacy catalogue conversion is no longer required. When the old schema is encountered during deferred metadata refresh, it may be ignored and replaced when the operator saves the first new-format configuration.

### Validated baseline before this pivot

Numbered build `0.1.0.36` was deployed and validated with the earlier session-memory/file-primary Admin implementation:

- cold start: 9 assertions
- Admin backup isolation: 19 assertions
- execution and Slot Inspector regression: 76 assertions
- execution scale: 25 assertions after moving 8-Scheduler or 120-Event models to deferred UI refresh
- Scheduler Slots/Inspector: 29 assertions
- pause modes: 17 assertions
- Week Patterns: 42 assertions
- Overrides: 48 assertions
- Override dates: 54 assertions
- logging: 18 assertions

The final deployed `.qplug` at that validated point has SHA-256:

```text
8a1979a1821a7897c86df66013bd7fefc4a6d4a49642d694f6d9c98a2bdcbccb
```

Designer is currently emulating `fugscheduler2000_test`. Do not copy a `.qplug` until emulation is stopped.

### Current local source state

Build `0.1.0.37` implemented and validated the second design. The current local source now contains the next Admin usability adjustment and remains **undeployed and not live-validated**:

- `src/controls.lua` declares the persistent catalogue, JSON clipboard, separate file ListBox, and physical file actions.
- `src/layout.lua` contains the final two-list/clipboard Admin layout with physical-Core-only file labelling.
- `src/runtime.lua` has one authoritative backup section. Superseded monolithic, session-memory, migration, and duplicate override implementations have been removed.
- After essential scheduler startup, catalogue metadata refresh runs automatically in a separate generation-checked timer slice. It decodes only schema-v2 metadata and opaque strings; selection does not parse stored schedules.
- Confirmed Load validates only the selected `scheduleJson`; clipboard import validates before insertion and never installs live configuration.
- The selected-file importer validates the complete selected file before catalogue insertion, bypasses the clipboard, and arms confirmed loading only after persistence succeeds. Corrupt files leave the catalogue, clipboard, and live configuration unchanged.
- `tests/qrc/validate_admin_backups.py` covers persistent catalogue behaviour, restart persistence, opaque `scheduleJson`, clipboard isolation, overwrite guards, Master Enable guarding, the 10-entry limit, deletion, and Emulator file-action disablement.
- `tests/qrc/validate_cold_start.py` now uses a production-sized schema-v2 opaque catalogue and expects deferred automatic list restoration. `tests/unit/test_backup_runtime_contract.py` checks consolidation, essential-startup isolation, deferred metadata refresh, metadata-only selection, filename-only file refresh, and selected-file validation ordering. `tests/qrc/validate_backup_file_isolation.py` provides an explicit physical-Core regression for a pre-provisioned corrupt selected file.
- Legacy conversion utilities and tests were removed because conversion is no longer required.
- The changed controls require a new numbered Designer deployment after local compilation. Stop emulation before copying the `.qplug`.

### Recommended next-session order

1. Compile locally without deploying or changing the numbered build.
2. Review the generated diff and run offline Python/backup-contract checks.
3. Ask the operator to stop Designer emulation before any `.qplug` copy.
4. Create a new numbered build only when intentionally preparing the next Designer deployment.
5. After restart, run cold-start and Admin regressions first, then execution scale and the Slot Inspector regression because startup/Admin code shares `src/runtime.lua`.
6. Validate physical file creation/readback and corrupt selected-file isolation on a safe physical Core before release; do not deploy plugin code to the production Core.
