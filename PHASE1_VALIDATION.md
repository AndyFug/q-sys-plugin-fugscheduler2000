# FugScheduler 2000 Phase 1 Validation

Use this checklist in Q-SYS Designer before relying on the external callback architecture.

## Boilerplate

- [x] `FugScheduler2000.qplug` loads without design-time errors.
- [ ] Plugin appears as `AndyFug~FugScheduler 2000` with the expected color/name.
- [x] The Actions page opens and its callback controls operate.
- [ ] Overview, Schedules, and Diagnostics pages open.
- [x] The `ActionSource` Text control pin can be exposed as an input.
- [x] The reserved `code` input can be connected to `SchedulerRuntimeProvider` for live runtime replacement.
- [ ] Status and action-registry controls can be exposed as outputs.

## ActionSource evaluator experiment

- [x] Create a Text Controller containing the sample in `references/action_source_test.lua`.
- [x] Connect its built-in `code` output to the plugin's ordinary `ActionSource` Text input.
- [x] Confirm plugin runtime provides a working dynamic Lua compiler (`load` or `loadstring`).
- [x] Confirm `GetFugSchedulerActions()` returns two registered callbacks.
- [x] Confirm both callbacks can be selected and invoked from the plugin Actions page.
- [x] Replace one callback with a known `Component.New(...)` operation and confirm Q-SYS API access.
- [ ] Record behavior after restarting/reconnecting the source controller; live source edits already refresh automatically.
- [x] Confirm syntax, provider, validation, and callback errors appear without stopping the plugin.
- [x] Confirm a failed update leaves the previous valid registry active.

## Callback registry spike

- [x] Load two actions with stable IDs and labels from `GetFugSchedulerActions()`.
- [x] Reject a duplicate ID with a useful status message.
- [x] Populate a Text control's `Choices` from registered actions.
- [x] Invoke a selected callback from the plugin test control.
- [x] Catch a deliberately failing callback with `pcall` and keep the plugin running.

## Persistence spike

- [x] Confirm `ScheduleData` and `TestDateTime` Text control values survive design save/reload.
- [x] Confirm the sample JSON containing Day Patterns, Events, Event Actions, Week Patterns, and Overrides persists in `ScheduleData` after saving and reopening the design.
- [x] Confirm the schema-version-1 sample containing two Schedulers persists and reloads intact.
- [x] Confirm at least the 3.4 KB sample JSON persists and reloads intact; further UI editing and maximum-length testing remain optional.
- [ ] Compare JSON persistence with counted controls for Day Patterns, Events, and Event Actions.

## Multi-Scheduler status spike

- [x] Confirm every configured Scheduler resolves independently for the same `TestDateTime`.
- [x] Confirm `SchedulerSelect` changes only the human-readable selected status view.
- [x] Confirm `GlobalSchedulerStatus` contains all configured Scheduler IDs in persisted order.
- [ ] Confirm one Scheduler resolution failure is isolated and reported without hiding other Scheduler statuses.
- [ ] Confirm third-party Lua can read and decode `GlobalSchedulerStatus` through a Named Component or exposed output pin.

## Resolver spike

- [x] Resolve a normal weekday through the Default Week Pattern.
- [x] Resolve a weekend through the Default Week Pattern.
- [x] Resolve a date through a Week Pattern Override.
- [x] Confirm a Day Pattern Override takes precedence over a containing Week Pattern Override.
- [x] Resolve the current Event from the previous day before today's first Event.
- [x] Resolve the next Event from the following day after today's last Event.
- [x] Preserve ordered multiple Event Actions in status output.
- [x] Reject invalid Schedule JSON without replacing the previous valid resolved schedule.
- [x] Restore valid Schedule JSON without restarting the plugin.
- [x] Keep automatic scheduled callback execution disabled during resolver validation.

## QRC findings — multi-Scheduler foundation

Validated against the active `fugscheduler2000_test` Designer emulator through QRC:

- `SchedulerRuntimeProvider` accepted the current `src/runtime.lua` byte-for-byte with script status `OK` and zero errors.
- The persisted sample loaded 2 Schedulers, 5 Day Patterns, 3 Week Patterns, and 2 Overrides with zero warnings.
- At `2026-12-25 12:00`, `demo-scheduler` resolved `Closed State` and `demo-announcements` resolved `Opening Announcement` independently.
- Selecting `demo-announcements` updated the banked status controls without removing either Scheduler from `GlobalSchedulerStatus`.
- Duplicate Scheduler IDs were rejected while the previous valid selected status and aggregate status remained active.
- Restoring valid JSON recovered immediately without restarting the plugin or runtime provider.

## QRC findings — Scheduler transaction layer and visual editor

Validated against the active `fugscheduler2000_test` Designer emulator through QRC:

- The Schedules page controls were present on `AndyFugFugScheduler2000`: label-based Scheduler selector, label, enabled, paused, label-based Default Week Pattern selector, add, duplicate, delete, and editor status. Stable IDs are intentionally omitted from the primary editor.
- The original transaction-layer test build added stable ID `scheduler`; the follow-up selector/identity refinement now generates opaque UUID-style IDs for newly created Schedulers.
- The new Scheduler was immediately valid, disabled by default, and contained `default-day`, `default-week`, seven weekday assignments, no Overrides, and no Events.
- Canonical serialization preserved empty schema collections as JSON arrays (`events: []` and `overrides: []`) rather than objects.
- Label, enabled, paused, and Default Week Pattern edits used the same validated transaction path and updated `ScheduleData`, `Status`, and `GlobalSchedulerStatus`.
- Restarting Designer emulation retained the added Scheduler's stable ID, label, enabled state, paused state, Default Week Pattern, and canonical JSON.
- The original transaction-layer test build duplicated `scheduler` as root-scoped ID `scheduler-copy`, preserved Scheduler-internal entity IDs, and created a separate aggregate status entry. Changing the duplicate's paused state did not alter the original Scheduler. The refined implementation now assigns a fresh UUID-style Scheduler ID when duplicating.
- Deleting the duplicate and added Scheduler selected a valid neighboring Scheduler and rebuilt selector choices and aggregate status.
- Deleting down to one Scheduler disabled the delete control. A forced QRC press was also rejected with `Delete rejected: at least one Scheduler is required`; `ScheduleData` remained at the previous valid revision.
- An empty Scheduler label and an invalid Default Week Pattern ID were rejected. Editor controls snapped back to the previous valid values, and the previous `ScheduleData` and global status remained active.
- Runtime-only `_...` indexes were absent from committed `ScheduleData`.
- The original two-Scheduler sample was restored after testing.
- `SchedulerRuntimeProvider` and `AndyFugFugScheduler2000` both finished with script status `OK` and zero errors.

### Structured selector and UUID follow-up

- Removed the Stable ID field from the primary Schedules editor while retaining IDs in `ScheduleData` and `GlobalSchedulerStatus`.
- Confirmed Q-SYS structured ComboBox choices display their `Text` label and expose the selected object as JSON through the control's `String` value.
- `SchedulerSelect` now displays Scheduler labels while mapping selections through each choice's `Id` field.
- `SchedulerDefaultWeekPattern` now displays Week Pattern labels while retaining stable Week Pattern IDs.
- Selecting the structured `{Text = "Demo Announcements", Id = "demo-announcements"}` choice updated the editor and selected status to the correct Scheduler.
- Adding a Scheduler generated UUID `f4e18ca4-25f1-4253-be45-a4892e3769b3`, matching UUID-v4 version and variant formatting. The same ID appeared in the selector JSON, persisted model, and aggregate status.
- Renaming that Scheduler changed the structured choice's `Text` field without changing its UUID `Id`.
- The temporary UUID test Scheduler was deleted after validation; pre-existing user Scheduler data was left intact.
- The structured-selector build finished with `SchedulerRuntimeProvider` and plugin script status `OK` and zero errors.

## Day Pattern / Event editor implementation

Implemented in the version 0.3.0 source and deployed to the Designer plugin directory:

- [x] Reload/restart the active design so the existing plugin component acquires the newly declared controls and Day Patterns page.
- [x] Confirm the Day Patterns page renders three scrollable columns for Day Patterns, Events, and Event Actions.
- [x] Confirm structured ListBox choices display labels while returning their JSON `Id` values through the control String.
- [x] Confirm Scheduler selection changes the Day Pattern context without modifying other Schedulers.
- [x] Confirm Day Pattern add/duplicate creates fresh UUID-style Day Pattern IDs and fresh Event IDs in duplicates.
- [x] Confirm referenced Day Pattern deletion is disabled and remains rejected when forced through QRC.
- [x] Confirm unreferenced Day Pattern deletion selects a valid neighboring pattern.
- [x] Confirm Event add/duplicate/delete, label editing, and HH:MM validation use the atomic transaction path.
- [x] Confirm Events display chronologically while equal-time Events retain persisted row order and produce a warning.
- [x] Confirm registered Actions can be attached, deleted, and moved without losing existing Event Action option fields.
- [x] Confirm invalid edits preserve the previous model, revision, resolver output, and editor selection.
- [x] Confirm runtime-only indexes remain absent from committed ScheduleData.
- [ ] Confirm design save/reload retains the edited nested configuration.
- [ ] Confirm automatic scheduled callback execution remains disabled.

QRC deployment findings before the required design reload:

- `SchedulerRuntimeProvider` accepted the updated `src/runtime.lua` byte-for-byte with script status `OK` and zero errors.
- The existing plugin component continued with script status `OK` and zero errors using its pre-update control declaration.
- Q-SYS did not add newly declared plugin controls to the already-running component after file deployment or a runtime reload trigger; a Designer design reload/restart is required before UI and CRUD validation.

### QRC findings after design reload

- Structured Day Pattern, Event, and Event Action ListBoxes returned JSON selections containing operator-facing `Text` and internal `Id` values.
- A temporary Scheduler, Day Pattern, and Event received correctly formatted UUID-v4-style IDs.
- A new Day Pattern started empty; a new Event selected the first unused minute and started without Event Actions.
- Invalid `25:00` input was rejected, `ScheduleData` remained byte-for-byte unchanged, and the Event time control snapped back to `00:00` with useful feedback.
- Event Action attachment, deletion, and move-up ordering committed the expected ordered `actionId` arrays.
- Event duplication created a fresh ID, copied Actions independently, retained the same time, and produced the expected duplicate-time warning.
- Day Pattern duplication created a fresh Day Pattern ID plus fresh IDs for every nested Event while preserving copied Event Actions.
- Unreferenced Day Patterns deleted successfully. Forced deletion of the referenced default Day Pattern retained the previous JSON and revision and reported its seven weekday references.
- Event choices displayed chronologically even when that differed from persisted row order. Equal-time ordering remained tied to persisted row order.
- Runtime reload retained the temporary nested configuration, and committed JSON contained no runtime `_...` indexes.
- The test harness completed 26 primary assertions plus four follow-up assertions, restored the original `ScheduleData` byte-for-byte, and left the plugin at script status `OK` with zero errors.
- Scrollable line-based ListBox mirrors were validated for `ScheduleData`, `GlobalSchedulerStatus`, and `DiagnosticLog` without changing the underlying Text controls.

## Week Pattern editor implementation

Implemented in the version 0.1.0 source:

- [x] Added the Week Patterns page between Day Patterns and Actions.
- [x] Added a scrollable structured Week Pattern ListBox with duplicate-label disambiguation that does not expose IDs.
- [x] Added Scheduler-scoped runtime Week Pattern selection and refresh on Scheduler changes.
- [x] Added label, add, duplicate, and guarded delete operations through the atomic schedule transaction path.
- [x] Added seven structured Day Pattern ComboBoxes that persist Day Pattern IDs rather than labels.
- [x] New Week Patterns receive UUID-v4-style IDs and assign the Scheduler's first Day Pattern to every weekday without changing defaults or Overrides.
- [x] Duplicates receive fresh IDs, copy all weekday assignments independently, and do not change defaults or Overrides.
- [x] Delete availability and runtime guards cover Scheduler defaults, enabled or disabled Week Pattern Overrides, and the final Week Pattern.
- [x] Week Pattern labels are validated as non-empty; duplicate labels remain warnings.
- [x] Transaction install/rejection refreshes the Scheduler, Day Pattern, and Week Pattern editors without persisting runtime selections or lookup indexes.
- [x] Local include compilation succeeds and the generated artifact contains no unresolved include directives.
- [x] Deploy the design-time plugin after QRC confirms the expected active emulator design.
- [x] Restart Designer so the existing plugin component acquires the new controls.
- [x] Run the requested Week Pattern QRC acceptance tests and restore the original ScheduleData byte-for-byte.

Initial validation blocker on 2026-10-23:

- Two QRC `StatusGet` attempts to `10.211.55.4:1710` failed with `ECONNREFUSED`.
- No deployment or control manipulation occurred until QRC later confirmed `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test`.

### QRC findings — Week Pattern editor

Validated against the active `fugscheduler2000_test` Designer emulator through QRC:

- The reloaded component fingerprint changed and all Week Pattern controls appeared, including the ListBox, label, references, CRUD buttons, seven weekday ComboBoxes, and editor status.
- `SchedulerRuntimeProvider` initially exposed a missing-global fault because raw `src/runtime.lua` hot deployment does not include design-time globals. The runtime now supplies a self-contained weekday metadata fallback; subsequent deployment completed byte-for-byte with script status `OK` and zero errors.
- The Week Pattern ListBox returned structured JSON selections with operator-facing `Text` and stable `Id` fields.
- A temporary Scheduler and newly added Week Pattern received valid UUID-v4-style IDs.
- A new Week Pattern assigned the Scheduler's first Day Pattern to all seven weekdays without changing the Scheduler default or creating Overrides.
- Label edits incremented the configuration revision exactly once. Empty labels were rejected, controls snapped back, and the prior JSON, aggregate status, resolver source, Scheduler selection, and Week Pattern selection remained unchanged.
- Every weekday ComboBox committed the selected Day Pattern ID in one revision.
- Duplication produced a fresh Week Pattern ID, copied all assignments, used a `Copy` label, and remained independent when edited. Duplicate labels were disambiguated by display order without exposing stable IDs.
- Unreferenced deletion succeeded and selected a neighboring Week Pattern.
- Default and final Week Pattern deletion remained disabled visually and rejected forced QRC presses.
- A disabled Week Pattern Override prevented deletion, updated the reference summary, and rejected a forced QRC press.
- Runtime hot reload retained nested Week Pattern configuration.
- Existing Scheduler and Day Pattern editors successfully created and edited temporary configuration during the test.
- Committed JSON contained no runtime `_...` indexes, and plugin status continued to report that automatic Event execution is off.
- `tests/qrc/validate_week_patterns.py` completed 42 assertions.
- The original `ScheduleData` was restored byte-for-byte after testing.
- `SchedulerRuntimeProvider` and `AndyFugFugScheduler2000` both finished with script status `OK` and zero errors.

## Overrides editor implementation

Implemented and validated in development build `0.1.0.9`:

- [x] Added the Overrides page between Week Patterns and Actions.
- [x] Added a Scheduler-scoped scrollable structured Override ListBox with duplicate-label disambiguation that never displays IDs.
- [x] Added label, enabled state, Day Pattern/Week Pattern type, inclusive start/end dates, and type-dependent structured pattern selection.
- [x] Added UUID-v4-style Add, adjacent independent Duplicate, Delete with neighboring selection, and complete-object Move Up/Down transactions.
- [x] Preserved persisted array order without adding an order field; Day Pattern Overrides continue to outrank Week Pattern Overrides while same-type array order defines priority.
- [x] Added strict `YYYY-MM-DD` calendar validation and start-before-or-equal-to-end validation through the existing atomic transaction path.
- [x] Added concise priority, enabled-state, duplicate-label, and enabled same-type overlap feedback using the shared centered editor status styling.
- [x] Extended validated schedule installation and transaction rejection refreshes across Scheduler, Day Pattern, Week Pattern, and Override editors.
- [x] Kept Override selection maps and runtime `_...` lookup indexes outside persisted `ScheduleData`.
- [x] Added `tests/qrc/validate_overrides.py` to exercise the visual editor and restore the original JSON byte-for-byte.

### QRC findings — Overrides editor

Validated against the active `fugscheduler2000_test` Designer emulator through QRC:

- The design-time `.qplug` was deployed while emulation was stopped, then Designer was returned to emulation before runtime deployment and control testing.
- The reloaded plugin component fingerprint changed from `bf546f2e95d9ecc079ba00c69ab6d9db` to `9c5905fabcc6efbbf978fe2993003550`, and all 14 new Override controls appeared. The final corrected bundled-runtime build reloaded as fingerprint `e59013699ad34d3fd8c5bf3208be2973`.
- `SchedulerRuntimeProvider` accepted the current `src/runtime.lua` byte-for-byte with script status `OK` and zero errors.
- The Override ListBox returned structured `Text`/`Id` selections; duplicate labels were disambiguated by display order without exposing stable IDs.
- Add produced a UUID-v4-style ID and an immediately valid enabled Day Pattern Override using a valid same-day range and the Scheduler's first Day Pattern.
- Label and enabled edits committed exactly once. Empty labels, malformed dates, invalid calendar dates, and reversed ranges were rejected while JSON, revision, resolver output, and editor selections remained unchanged and controls snapped back.
- Type changes selected valid type-appropriate pattern IDs and never left a cross-type reference. Pattern controls persisted IDs rather than labels.
- Duplicate inserted an independent copy beside its source with a fresh ID and `Copy` label. Editing the duplicate did not change the source.
- Move Up/Down changed persisted array order without losing fields. Boundary buttons were disabled and forced QRC presses were harmless.
- Delete removed the selected Override and selected its neighbor.
- Enabled same-type overlaps produced concise warnings; disabled Overrides reported no active overlap and did not create active overlap warnings.
- Resolver checks confirmed Day Pattern Override precedence over an overlapping Week Pattern Override, and confirmed disabled Day Pattern and Week Pattern Overrides did not affect resolution.
- Runtime hot reload retained nested Override configuration. Existing Scheduler, Day Pattern, and Week Pattern editors continued to commit and retain edits.
- Committed JSON contained no runtime `_...` indexes, and automatic scheduled callback execution remained disabled.
- `tests/qrc/validate_overrides.py` completed 45 assertions.
- The original `ScheduleData` was restored byte-for-byte after testing.
- `SchedulerRuntimeProvider` and `AndyFugFugScheduler2000` both finished with script status `OK` and zero errors.

## Build validation

- [x] Run `python3 scripts/compile_plugin.py` successfully.
- [x] Confirm the generated `.qplug` has no unresolved `#include` directives.
- [ ] Validate with the official Q-SYS Plugin Compiler before any release milestone.
