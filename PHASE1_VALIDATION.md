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

- [x] Confirm `ScheduleData` survives design save/reload. `TestDateTime` remains a persistent control value in Designer but is now deliberately cleared by runtime start before operational status is published.
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

### Event Action editor follow-up

Implemented in source after the original Day Patterns acceptance run:

- [x] Changed `EventActionPicker` from an attachment-creation picker to the selected row's **Attached Action** editor.
- [x] Changed **Add Action** to create and select a row using the first registered Action while forcing the new assignment disabled.
- [x] Preserved the selected row's execution options and order when its attached Action changes.
- [x] Removed implicit first-row selection so Event Action editors remain disabled until a row is explicitly selected or newly added.
- [x] Confirm in Designer/QRC that an existing Event Action can change its attached Action without changing its options or order.
- [x] Confirm an Event with no Event Actions enables only **Add Action**, with the empty list and all row editors disabled.
- [x] Confirm a new Event Action uses the first registered Action, is selected automatically, and remains disabled until explicitly enabled.
- [x] Extended `tests/qrc/validate_execution.py` with repeatable attached-Action reassignment and disabled-by-default Add Action coverage.
- [x] Ran the updated QRC acceptance test after deploying the new plugin/runtime build: 70 assertions passed with restoration confirmed.

QRC findings:

- With an Event Action list present but no selected row, the Attached Action and row editor controls remained disabled while **Add Action** remained available.
- A focused empty-Event QRC check confirmed the empty Event Action list and every row editor were disabled while **Add Action** alone remained enabled; the original `ScheduleData` was restored byte-for-byte and momentary controls were left idle.
- Explicit row selection populated the Attached Action editor with the selected stable Action ID.
- Reassigning the Attached Action preserved enabled, mode, startup/resume, repeat, ordering, and neighboring Action data.
- **Add Action** created and selected a third row using the first registered Action while forcing `enabled = false`; deleting it restored the temporary fixture exactly.
- The complete execution acceptance run restored the original `ScheduleData`, test time, logging preferences, Action Provider source, and Action source, left automatic execution disabled, and finished with all scripts `OK` and zero errors.

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
- [x] Updated new and duplicated Overrides to start disabled so operators can finish configuration before activation; local compile validation is complete and QRC regression remains pending.
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
- The validated build at that time produced a UUID-v4-style ID and an immediately valid enabled Day Pattern Override using a valid same-day range and the Scheduler's first Day Pattern. The source now creates and duplicates Overrides disabled by default; that safer default awaits the next QRC regression run.
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

## Override date editing implementation

Implemented and QRC-validated in development build `0.1.0.10`:

- [x] Added a persistent presentation-only Date Format preference with `DMY`, `MDY`, and `ISO` stable IDs on a Preferences page.
- [x] Kept canonical Override dates in `ScheduleData` as ISO `YYYY-MM-DD` values.
- [x] Added runtime-only selected-Override Start/End text buffering so invalid text remains visible without changing configuration or resolver state.
- [x] Added fixed-English long-form date displays, separate red ordinary-text validation messages, and an inclusive range summary.
- [x] Added atomic Start edits that preserve duration, End edits that change duration, `-1 Day`, `Today`, `+1 Day`, and `1 Day` operations.
- [x] Used Core-local `os.date`, `os.time`, and `os.difftime` with local-midday normalization for calendar arithmetic.
- [x] Added `tests/qrc/validate_override_dates.py` and updated the existing Override test for buffered invalid input and preference restoration.
- [x] Local include compilation succeeds and the generated artifact contains no unresolved include directives.
- [x] Confirmed the final rebuilt `.qplug` was deployed while simulation was stopped.
- [x] Ran the new date test plus existing Override and Week Pattern regression tests and recorded assertion counts.
- [x] Confirmed date preference persistence across a complete Designer stop/start cycle.

Validation blocker on 2026-10-26:

- QRC `StatusGet` and direct TCP connection attempts to `10.211.55.4:1710` timed out before and after the initial design-time deployment.
- The host could reach the emulator, but the dev container selected its `192.168.215.1` gateway and could not establish TCP connectivity to the emulator subnet.
- No runtime deployment or plugin control manipulation occurred while the expected active design could not be identified through QRC.
- Restarting the dev container restored connectivity; subsequent sessions confirmed `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test` before every deployment or mutation phase.
- The official SDK documents `TextColor` as a design-time layout property but does not document a writable runtime Text-control color property. The implementation therefore uses a separate red ordinary-text validation control rather than inventing an unsupported API.

### QRC findings — Override date editing

Validated against the active `fugscheduler2000_test` Designer emulator through QRC:

- The final plugin component fingerprint is `83e65d5c6a1bc2e03379bab4fda9a323`, changed from the prior documented build fingerprint `e59013699ad34d3fd8c5bf3208be2973`; all 115 component controls were present.
- The Preferences page exposed structured `DMY`, `MDY`, and `ISO` choices with neutral labels `dd/mm/yyyy`, `mm/dd/yyyy`, and `yyyy-mm-dd`.
- Preference changes and a complete Designer stop/start persistence check left `ScheduleData`, revision, and resolver status unchanged; the original preference was restored byte-for-byte afterward.
- Canonical ISO dates rendered and committed correctly in all three preferences. One-digit day/month input normalized to two digits.
- Invalid formatting, invalid calendar dates, and End-before-Start text remained visible in the runtime-only buffer while JSON, revision, resolver output, and selections remained unchanged.
- Separate red ordinary-text validation controls displayed field errors because a writable runtime Text-control color API is not documented.
- Fixed-English long-form dates and inclusive summaries rendered correctly, including `3 days inclusive` for 24–26 December 2026.
- Start edits preserved range duration and committed Start/End together in one revision; End edits changed duration in one revision.
- `1 Day` collapsed End to Start; `-1 Day` and `+1 Day` initially shifted the complete range, then were refined in build `0.1.0.13` to shorten or extend duration by moving only End. `Today` remains the only convenience action that moves Start and preserves duration.
- Leap-day, year, and configured spring DST-boundary duration changes retained the expected calendar-day behavior using local-midday platform normalization.
- Invalid buffers were discarded safely when changing Override or Scheduler, and no runtime `_...` keys or date buffer fields entered `ScheduleData`.
- `tests/qrc/validate_override_dates.py` completed 44 assertions.
- Updated `tests/qrc/validate_overrides.py` completed 46 assertions; `tests/qrc/validate_week_patterns.py` completed 42 assertions.
- Every test restored `ScheduleData` byte-for-byte; date tests also restored `DateFormatPreference` byte-for-byte.
- Automatic scheduled callback execution remained disabled, all momentary controls finished false, and both scripts finished with status `OK` and zero errors.

## Overrides layout refinement

Validated in development build `0.1.0.11`:

- Stacked the compact Type and Pattern ComboBoxes so each label sits directly beside its field.
- Tightened Start and End date row spacing while retaining dedicated validation-message space.
- Replaced the large coloured range convenience buttons with a compact centred neutral-grey group.
- Deployed the design-time plugin while simulation was stopped; the component fingerprint changed to `754de19e3030fc424ba6a489cdaebc88`.
- Confirmed the unchanged control set, existing `ScheduleData`, and date preference remained intact after restart.
- Deployed the matching runtime source byte-for-byte; both scripts reported `OK` with zero errors.
- Follow-up build `0.1.0.12` matched the Type and Pattern ComboBox widths to the 270-pixel Label field width; the reloaded component fingerprint changed to `05fba2a8c9c9a5e850282a9983ebb500` with persistent values intact.
- Build `0.1.0.13` changed the neutral-grey convenience button text to white and refined `-1 Day`/`+1 Day` as End-only duration controls. The date test completed 46 assertions with byte-for-byte restoration before deployment; the reloaded component fingerprint changed to `b64e8d1e37a87931ab02de6760ea5470` and both scripts reported `OK` with zero errors.
- Build `0.1.0.14` moved compact convenience controls beside their associated date entries and moved each friendly resolved date beneath its entry. Start provides `Today`, ±1 Day, and ±1 Week while preserving duration; End provides `1 Day`, ±1 Day, and ±1 Week while changing duration. The component now exposes 121 controls with fingerprint `d6db0c7a9c3fc6400f7352b792987032`; the expanded date test completed 54 assertions and restored both persistent values byte-for-byte.
- Build `0.1.0.15` moved the complete End Date row upward by 5 pixels, but the visual change was too subtle.
- Build `0.1.0.16` uses an exact 8-pixel gap between the Start friendly-date line and the End entry row by overlaying the mutually exclusive validation text on the friendly-date line. The End row is 13 pixels above its original build-0.1.0.14 position; the reloaded component fingerprint changed to `fbd108d305d50acd7535300d3d54cb03`, the deployed artifact hash matched the generated file, and both scripts reported `OK` with zero errors.
- Build `0.1.0.17` doubled the Pattern-to-Start section gap from 10 to 20 pixels while retaining all internal date-section spacing. The reloaded component fingerprint changed to `c68207ce40759824bb8af08b45ba0b69`; matching runtime deployment completed with both scripts healthy.
- Build `0.1.0.18` fixed overlapping invalid-date and friendly-date text by clearing the friendly-date control while its red validation control is active. The component fingerprint changed to `3303075343396c4c2c1b875301a69293`; the updated date test completed 54 assertions with byte-for-byte restoration and both scripts healthy.

## Guarded Event execution implementation

Implemented in source; design reload and QRC acceptance remain pending:

- [x] Added explicit Event Action enabled, Stateful/One Shot, restore-on-start, restore-on-resume, and repeat interval editing.
- [x] Added validation that one-shot assignments cannot restore or repeat.
- [x] Added optional Action Registry defaults that are copied into a new Event Action once at attachment time.
- [x] Added a persistent plugin-wide `AutomaticExecutionEnabled` safety control that defaults off for new controls.
- [x] Added independent per-Scheduler occurrence tracking and a retained one-second Q-SYS timer.
- [x] Added ordered execution for all Events crossed in an ordinary poll interval, including duplicate-time persisted order.
- [x] Added startup/enable restoration, resume restoration, missed one-shot suppression, repeat scheduling without catch-up bursts, and callback isolation.
- [x] Added backward-clock reset and forward-discontinuity handling that skips historical one-shots and restores only the current configured state.
- [x] Added runtime execution details to `GlobalSchedulerStatus` without serializing them into `ScheduleData`.
- [x] Added `tests/qrc/validate_execution.py` for guarded startup, repeat, pause, resume, one-shot suppression, and guaranteed restoration.
- [x] Deploy the design-time plugin while emulation is stopped and confirm the new controls appear after restart.
- [x] Confirm the master execution guard remains off across initial design reload and blocks callbacks and repeats.
- [x] Validate normal edge ordering, duplicate-time ordering, callback failure isolation, and unavailable Action handling.
- [x] Validate startup, Scheduler enable, pause, resume, and repeat behavior for stateful Event Actions.
- [ ] Validate that one-shots are not replayed on startup, enable, resume, or forward clock discontinuity; startup, enable, resume, and schedule-change coverage are complete, while deterministic forward-discontinuity injection remains blocked.
- [x] Validate repeat timers restart from resume time without catch-up bursts.
- [x] Run existing Week Pattern and Override regression tests with the execution guard off and restore persistent controls byte-for-byte.

Pause-until-next-Event, timed pause, next-day pause policy, and Advance to Next Event remain the next operational transport slice.

### QRC findings — guarded Event execution

Validated against the active `fugscheduler2000_test` Designer emulator:

- Before deployment, QRC confirmed the expected active design and the prior 121-control component. The user stopped emulation, the generated `.qplug` was deployed with a matching SHA-256 hash, and emulation was restarted.
- The reloaded plugin exposes 128 controls, including all seven new execution and Event Action option controls.
- `SchedulerRuntimeProvider` accepted the current `src/runtime.lua` byte-for-byte; both scripts reported `OK` with zero errors.
- The plugin-wide automatic-execution guard remained off after design reload. The execution test also refused to begin unless the guard was off.
- A temporary enabled Scheduler restored its current stateful Action on engine startup, while the one-shot assignment in the same Event did not replay.
- A two-second repeat fired while active, stopped throughout pause, restarted from resume, and did not produce a catch-up burst.
- Resume restored the configured stateful Action and did not replay the current one-shot Action.
- Turning the master guard off blocked subsequent repeats and returned aggregate status to `automatic execution OFF`.
- Event Action editor controls displayed the persisted enabled, Stateful, startup, resume, and repeat values correctly.
- Runtime execution state remained absent from serialized `ScheduleData`.
- `tests/qrc/validate_execution.py` completed 29 assertions and restored `ScheduleData`, `TestDateTime`, and the master guard.
- Adding a later current Event through a schedule edit immediately reconciled that Event's stateful Action even with startup/resume restoration disabled.
- Moving that Event into the future immediately restored the preceding stateful Event, skipped its one-shot Action, and restarted its repeat interval from the edit time.
- Regression results: Week Patterns 42 assertions, Overrides 48 assertions, and Override Dates 54 assertions. Every test restored persistent controls byte-for-byte.
- Final state: expected emulator design active, master execution guard false, plugin and runtime-provider scripts `OK`, and zero script errors.

### QRC findings — remaining guarded execution acceptance

Validated against the active `fugscheduler2000_test` Designer emulator on 2026-10-26:

- QRC confirmed `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test` before provider mutation, Scheduler mutation, the scheduled-edge phase, runtime deployment, and cleanup.
- The first preflight found `AutomaticExecutionEnabled = true`, so testing was refused until the user disabled it. Every subsequent execution test began with the guard false and finished with it false.
- `tests/qrc/validate_execution.py` now snapshots `ScheduleData`, `TestDateTime`, both logging preferences, the plugin `ActionSource`, and the complete `ActionProvider` `code` source. Guaranteed cleanup restored and explicitly verified every value byte-for-byte, restored the provider source byte-for-byte, and left tested momentary controls false.
- A genuine upcoming Core-local `HH:MM` edge executed automatically. Two Events sharing that timestamp executed in persisted Event order, and all Event Actions executed in configured array order.
- An unavailable Action logged Error and did not prevent the following failing and successful Actions. A deliberately failing callback remained isolated by `pcall`, logged Error with its failure text, and did not prevent the following successful Action or the next same-time Event.
- Successful edge execution logged at Info with Scheduler, Event, Action, action index, and `reason=scheduled edge` context. A two-second repeat after the initial edge logged at Debug.
- The scheduled one-shot executed exactly once at its edge. Separate lifecycle coverage confirmed current one-shots did not replay on startup, Scheduler enable, resume, or schedule change.
- `ExecutionStatus` retained the latest scheduled execution result, and serialized `ScheduleData` contained no runtime-only `_...` state.
- Commands run: `python3 scripts/compile_plugin.py`; unresolved-include scan with `rg`; verified runtime deployment with `qsys-qrc.cjs ... deploy SchedulerRuntimeProvider src/runtime.lua`; `python3 tests/qrc/validate_execution.py`; and `python3 tests/qrc/validate_logging.py`.
- The local compile succeeded and `FugScheduler2000.qplug` contained no unresolved include directives. No design-time declarations changed, so no `.qplug` redeployment or emulation restart was required.
- The expanded execution test completed 56 assertions. `tests/qrc/validate_logging.py` then completed 18 regression assertions. Both tests confirmed restoration.
- During test development, four rapid post-edge visual-editor transactions caused Q-SYS `Max execution limits exceeded` diagnostics. The acceptance test was corrected to avoid unnecessary rapid editor mutations; no product runtime change was required. The plugin script was explicitly reloaded, the corrected test passed, and final script health returned to `OK` with zero errors.
- `TestDateTime` is resolver-only, while live execution polling calls `os.time()` directly. No existing validated QRC, control, or documented Q-SYS API can inject a backward or forward live clock discontinuity. Host, emulator, and Core clocks were not changed. Backward-reset and forward-skip/state-restoration behavior therefore remain code-reviewed but not deterministically QRC-validated; implementing a test seam requires a separate proposal and approval.
- Final observed persistent states after byte-for-byte restoration were Debug Output `Info` and Event Log `Info`, matching the values present at test start. This differs from the documented default Event Log `Off` but was preserved as required rather than overwritten. Automatic execution finished false.
- Final health: `AndyFugFugScheduler2000`, `SchedulerRuntimeProvider`, and `ActionProvider` all reported `OK` with zero script errors.

Remaining execution validation is limited to deterministic backward/forward clock-discontinuity behavior once a safe supported injection mechanism or approved test seam exists.

## Advance to Next Event implementation

Implemented in source; design reload and QRC acceptance remain pending:

- [x] Added an Inspector transport button plus stable counted `SchedulerSlotAdvance` input pins.
- [x] Require Master Enable, an assigned Slot, and Slot Enable; an active pause is deliberately cleared rather than blocking the command.
- [x] Execute the resolved Next occurrence once in Event Action order with reason `manual advance`.
- [x] Make the occurrence Current immediately, start eligible repeats from the advance time, and suppress its later scheduled edge.
- [x] Persist the consumed occurrence identity in `ScheduleData` and restore the advanced cursor after runtime restart.
- [x] Clear the persisted marker after the original scheduled timestamp or when schedule changes invalidate the target.
- [x] Publish manual-advance state in aggregate Slot status and add `tests/qrc/validate_advance_next_event.py`.
- [x] Deploy the changed design-time plugin while emulation is stopped, restart Designer, and run the new QRC acceptance test.

### QRC findings — Advance to Next Event

Validated in development build `0.1.0.28` against the active `fugscheduler2000_test` emulator:

- The generated and deployed `.qplug` SHA-256 matched: `7dc71350c46d502b72b2af72e275222bd75d2320e1b1c867e656b147a9652c4a`.
- The reloaded component fingerprint is `da3e8ea3e75d26c5f05de9628292700c`; the Inspector control and stable `SchedulerSlotAdvance 1` input were present.
- A paused enabled Slot advanced while Master Enable was on, cleared its active pause intent, persisted the target occurrence identity, and made the target Event Current immediately.
- The target one-shot Action executed exactly once with `reason=manual advance`.
- After waiting through the target's original wall-clock edge, the persisted marker cleared and the one-shot did not replay; Current and Next remained correctly positioned.
- The stable per-Slot input performed the same transition as the Inspector button.
- `tests/qrc/validate_advance_next_event.py` completed 14 assertions with byte-for-byte ScheduleData and Action Provider restoration.

## Named Admin configuration backups

Implemented in source; physical-Core file behavior and QRC acceptance remain pending:

- [x] Added an Admin page with named backup selection, save, guarded load, selected-backup delete, shared Confirm/Cancel flows, summaries, and file-mirror status.
- [x] Store all named backups in one schema-versioned persistent `ConfigurationBackupCatalog` Text control.
- [x] Snapshot only the complete Scheduler Definition and Scheduler Slot `ScheduleData` root; preferences and runtime-only state remain excluded.
- [x] Validate every catalogue entry and complete schedule before use.
- [x] Load backups atomically with a new local revision and reject loads while Master Enable is on.
- [x] Attempt to mirror the complete catalogue to `/FugScheduler2000/configurations.json` on a physical Core; report that file writes are unavailable in emulation.
- [x] When the persistent control is empty on a physical Core, attempt to seed it from the same file.
- [ ] Determine whether the requested absolute folder path maps to writable Core storage; the official SDK examples document `media/` and `design/` paths instead.
- [x] Added `tests/qrc/validate_admin_backups.py` with byte-for-byte restoration.
- [x] Validate UI controls and persistent catalogue behavior in Designer/QRC.
- [ ] Validate file creation, replacement, Core restart persistence, and off-Core file retrieval on a physical Core.

### QRC findings — Admin configuration backups

Validated in development build `0.1.0.28` against the active `fugscheduler2000_test` emulator:

- The Admin controls appeared after the design-time plugin reload and the empty schema-version-1 catalogue initialised in `ConfigurationBackupCatalog`.
- A named save captured the complete Scheduler Definition and Scheduler Slot model.
- Reusing a name armed overwrite confirmation without changing the catalogue; Cancel preserved the previous backup.
- Delete now uses the same armed Confirm/Cancel flow and removes only the selected catalogue entry after confirmation.
- Confirmed Load atomically restored the saved model and assigned a new local revision.
- Load remained rejected while Master Enable was on.
- Designer correctly reported that the Core media-file mirror is unavailable in emulation.
- The initial `tests/qrc/validate_admin_backups.py` run completed 11 assertions and restored ScheduleData plus ConfigurationBackupCatalog byte-for-byte.
- Post-feature regressions passed: Scheduler Slots/Inspector `29`, pause modes `17`, guarded execution `73`, and logging `18` assertions, all with restoration confirmed.
- Build `0.1.0.29` added selected-backup Delete using the shared Confirm/Cancel flow and changed the experimental physical-Core path to `/FugScheduler2000/configurations.json`.
- The build-0.1.0.29 generated/deployed SHA-256 matched: `ebb534086d2d41467dcfc853d499e58d37d98c717fbffeeeda71b275d51099a9`; the reloaded component fingerprint is `233afcfbcde59c14b07089a4d841945d`.
- The expanded Admin test completed 14 assertions: Delete armed without mutation, Cancel preserved the selected entry, Confirm removed only that entry, and the original two saved configurations were restored byte-for-byte.
- Final state: Master Enable false, Delete/Confirm/Cancel momentary controls false, the original two-backup catalogue restored, plugin and runtime provider `OK`, and zero script errors.
- Build `0.1.0.30` removed the Admin file-mirror information panel, renamed the group to Configuration Backups, moved Confirm/Cancel into a tighter lower pair, and made left alignment the FugUi default for every ListBox. The generated/deployed SHA-256 matched `2df7352bf0769564489f4f0f7af2a0e88a42e2fbc12075a4c855aa056ba29abc`; the reloaded component fingerprint is `8cfdc5ff2f54bbaf84804c3a2313796d`, with the original two-backup catalogue retained and both scripts healthy.
- Build `0.1.0.31` added the compact top-right filesystem-location note requested for the Admin group. The generated/deployed SHA-256 matched `7e48b263a381b46e22aa8fbde3ae81f83366ce71a0ca63f879e8599f6da48ccd`; physical-Core path validation remains deferred.

The file approach follows the official SDK JSON read/write example in `.agents/skills/qsys-plugin-sdk/references/official-sdk/Code Examples/19-JSON-Object.md`; that reference explicitly notes that file operations do not work in emulation.

## Centralized logging implementation

Implemented in source; design reload and QRC acceptance remain pending:

- [x] Added one normalized logging handler with numeric levels `OFF = 0`, `ERROR = 3`, `INFO = 6`, and `DEBUG = 7`.
- [x] Added persistent global Debug Output and Event Log level controls on Preferences, separate from `ScheduleData`.
- [x] Defaulted Debug Output to Info and Q-SYS Event Log to Off.
- [x] Routed enabled Event Log messages through documented `Log.Message` and `Log.Error` APIs and Debug Output through `print`.
- [x] Kept DiagnosticLog independent of destination preferences and bounded to the newest 12,000 characters, trimming complete oldest lines where possible.
- [x] Added timestamp, severity, and available Scheduler/Event/Action/reason context to DiagnosticLog entries while keeping Debug Output concise.
- [x] Logged successful initial Event Action execution at Info, subsequent repeats at Debug, and missing Actions/callback failures at Error.
- [x] Preserved callback isolation and `ExecutionStatus` updates through the centralized execution-reporting path.
- [x] Routed existing registry, schedule validation, transaction, resolver, and initialization messages through the centralized logger.
- [x] Added `tests/qrc/validate_logging.py` for normalized preference IDs, basic Debug Output filtering, unconditional DiagnosticLog routing, bounded retention, restoration, and script health.
- [x] Local include compilation succeeds and the generated artifact contains no unresolved include directives.
- [x] Deployed the changed `.qplug` while emulation was stopped and confirmed the two new controls after restart.
- [x] Ran `tests/qrc/validate_logging.py` and recorded its assertion count.
- [ ] Observe enabled Info/Error output in the Q-SYS Event Log and confirm Off suppresses it; the Event Log was not available for inspection in the current Designer simulation view.
- [x] Confirmed Debug repeat output and Info initial execution output in DiagnosticLog through QRC execution testing.
- [x] Finished with automatic execution false and both scripts reporting `OK` with zero errors.

### QRC findings — centralized logging

Validated against the active `fugscheduler2000_test` Designer emulator:

- QRC confirmed the expected active emulator design before runtime deployment or control manipulation.
- The rebuilt `.qplug` was deployed while emulation was stopped with matching generated/deployed SHA-256 `88ab078d3f49e3a7a199ff7d278f06bc20dac0b31bdf4c084c867f67a5e4798f`.
- After restart, the plugin component fingerprint changed to `134631929376f6f05b0956b1e5eb29af` and exposed 130 controls, including `DebugLogLevel` and `EventLogLevel`.
- Both preferences exposed structured numeric IDs `DEBUG = 7`, `INFO = 6`, `ERROR = 3`, and `OFF = 0`; defaults were Debug Output Info and Event Log Off.
- `tests/qrc/validate_logging.py` completed 18 assertions. It confirmed Debug Output Off/Error/Info filtering through `log.history`, unconditional DiagnosticLog routing, the 12,000-character bound, Event Log preference handling, unchanged `ScheduleData`, and byte-for-byte preference restoration.
- Updated `tests/qrc/validate_execution.py` completed 31 assertions. It confirmed initial state restoration logs at Info and repeats log at Debug with Scheduler/Event/Action/reason context. The fixture now temporarily disables pre-existing Schedulers so unrelated callbacks cannot overwrite `ExecutionStatus`; original `ScheduleData` remains restored byte-for-byte.
- Event Log Info was enabled briefly and the Action Registry was reloaded to generate a known `Log.Message` entry, but the Core Event Log was not available for inspection in the current simulation view. The preference was restored to Off afterward.
- The pre-test design had automatic execution enabled; it was disabled before runtime deployment and remained false after all testing.
- Final state: Debug Output Info, Event Log Off, automatic execution false, and both `AndyFugFugScheduler2000` and `SchedulerRuntimeProvider` at script status `OK` with zero errors.
- Preferences layout follow-up moved the shared status control out of the two side-by-side groups into a separate full-width Preference Status group. A second refinement reduced that group to 92 pixels and the status box to 40 pixels, matching the compact status treatment on other pages. The final deployed artifact hash is `0acf1bf6f8d7b26ab3e6e0152c479bbbb5728dff79ccf0a0d4e95e27b63e3130`; after restart the component fingerprint changed to `1d37cadc2a3f0132a3906d8149e7cb66`, with both scripts healthy and automatic execution false.

## Scalable Scheduler execution-plan refactor

Implemented and QRC-validated in source:

- [x] Replaced timeline reconstruction/sorting in the one-second execution path with compiled per-Scheduler plans and a rolling Previous/Current/Next occurrence cursor.
- [x] Added cached date resolution, persisted-order equal-time Event compilation, incremental forward extension, Previous-history retention, and a documented 400-day safety horizon.
- [x] Added one retained generation-checked timer per Scheduler with deliberate phase staggering; unchanged Scheduler plans/timers are reused and replaced/deleted timers are stopped.
- [x] Preserved ordered Event/Action execution, callback `pcall` isolation, startup/enable/resume/schedule-change policy, one-shot suppression, repeat deadlines, and discontinuity re-anchoring.
- [x] Added root and per-Scheduler non-spamming performance diagnostics using `Timer.Now()` only for elapsed measurements.
- [x] Extended `tests/qrc/validate_execution.py` to inspect plan count, independent timer polls, stagger phases, performance counts, affected generation replacement, and unrelated plan/timer preservation.
- [x] Local include compilation succeeds and the generated artifact contains no unresolved include directives.
- [x] Run the expanded execution, plan lifecycle, detached resolver, scale, editor-regression, and logging QRC suites after the emulator is restarted into a clean script state.
- [x] Restart emulation with the restored baseline and confirm schedule persistence, safe guard state, momentary reset, and all three script-health results.
- [x] Record final assertion counts, measured poll/rebuild durations, tested scale, restoration, and all three script-health results.

Development finding:

- The first hot-deployed draft synchronously searched a long safety horizon for an Event-free Scheduler and caused `Max execution limits exceeded`. The implementation now detects Event-free plans without horizon scanning and prevents repeated empty-window extension.
- A first 20 × 20 scale probe exposed a second execution-budget defect while synchronously positioning every newly added plan and rebuilding all status/editor views in the `ScheduleData` handler. New plans now position on their staggered timer, and large installed models use delayed four-Scheduler status chunks plus a generation token so obsolete deferred work cannot overwrite newer state. The corrected 20 × 20 run remained healthy.
- The optional 50 × 20 probe still exceeded the Q-SYS transaction budget before the install summary, during the synchronous external `ScheduleData` decode/complete-schema validation path. The original JSON was restored byte-for-byte, but Designer required a stop/start to clear the resulting `Compromised` state. This is recorded as a large-transaction limitation rather than partially introducing staged/deferred configuration validation without approval.
- After an execution-limit fault, QRC script reload/stop controls did not return the plugin to `OK`; a Designer stop/start was required. Automatic execution remained false. No design-time declarations changed, so the `.qplug` did not require deployment for recovery.

Final QRC findings against the active `fugscheduler2000_test` emulator:

- `tests/qrc/validate_execution.py` completed 62 assertions. It validated real future edge execution, equal-time Event and Event Action ordering, missing/callback failure isolation, Info/Debug logging, startup/enable/resume/schedule-change one-shot suppression, repeat restart without catch-up, independent Scheduler timers, unique stagger phases, affected-plan generation replacement, unrelated plan/timer preservation, runtime-state exclusion, byte-for-byte restoration, and final health.
- `tests/qrc/validate_execution_plan_lifecycle.py` completed 24 assertions. It explicitly added and removed a Scheduler, confirmed the new timer polled, waited through multiple former timer periods after deletion, and verified that an unaffected plan retained its generation and phase while continuing to poll. Persistent controls were restored and both scripts finished healthy.
- `tests/qrc/validate_execution_resolution.py` completed 21 assertions. It validated Previous/Current/Next identity across midnight, an inclusive Day Pattern Override boundary, a 121-day empty range with Current before and Next after the gap, detached `TestDateTime` resolution, runtime-state exclusion, byte-for-byte restoration, and final health.
- `tests/qrc/validate_execution_scale.py` completed 25 normal assertions with restoration. At 5 Schedulers × 10 Events/Actions, measured average poll duration was `0.000699997 s`, maximum `0.003999710 s`, delayed polls `0`, and measured total rebuild duration `0`. At 20 × 20, average was `0.000350046 s`, maximum `0.003000259 s`, delayed polls `0`, and measured total rebuild duration `0.002000809 s`. Each Scheduler timer polled independently and every phase was unique.
- The QRC wall-clock fixture-install measurements were approximately `4.03 s` because the test deliberately waits four seconds for staggered timers and deferred status completion; they are not plan-rebuild CPU durations.
- The optional 50 × 20 probe reached the external-write/schema-validation transaction limit before plan installation and is excluded from normal acceptance. The test harness supports retrying it explicitly with `FUGSCHEDULER_SCALE_50=1` after a future approved large-transaction design.
- The post-refactor editor regressions also passed: Week Patterns `42`, Overrides `48`, and Override Dates `54` assertions, each with restoration and healthy scripts.
- `tests/qrc/validate_logging.py` completed 18 assertions after the execution refactor and confirmed unchanged destination filtering and bounded DiagnosticLog behavior.
- `tests/qrc/validate_execution_midnight.py` completed 23 assertions across a genuine wall-clock midnight. It validated pre-midnight polling and cursor state, the live 23:59 and 00:00 callbacks, Previous advancing with its prior-date identity, Current advancing to 00:00 on the new date, Next extending to the new date's 00:01 Event, persisted callback order, byte-for-byte restoration, and final health for all three scripts.
- During detached-resolver test development, live transition status briefly overwrote explicit `TestDateTime` output. Live cached status publication is suppressed whenever `TestDateTime` is non-empty; runtime start, Master Enable, and Slot enable now clear the developer-only preview before normal operation.
- Every completed acceptance test restored its changed persistent controls byte-for-byte. Automatic execution finished false. Final observed logging preferences were Debug Output `Info` and Event Log `Info`, matching the values present at test start.
- The historical post-test restart retained revision `79`, the expected four Scheduler IDs and `2/4` enabled state, and `TestDateTime = 2030-01-02 12:00`. The runtime now deliberately clears that developer-only preview on start; schedule, logging preferences, runtime-field exclusion, false momentaries, and automatic execution safety remain unchanged. `AndyFugFugScheduler2000`, `SchedulerRuntimeProvider`, and `ActionProvider` all restarted `OK` with zero errors.
- Deterministic backward/forward live clock-discontinuity injection remains blocked exactly as before; no host, emulator, or Core clock was changed and no unsupported Q-SYS clock API or test seam was introduced.

## Banked Overview and Inspector refactor

Implemented in source; Designer deployment and QRC acceptance pending:

- [x] Added a ten-row banked Overview backed by counted controls and fixed-bounds FugUi row boxes.
- [x] Removed row selection, kept bold Scheduler names, and left Inspector/editors responsible for the shared stable-ID selector.
- [x] Added compact live Enable/Pause toggles that persist by stable Scheduler ID, plus equal-share wrapped Current Pattern and dated Current/Next Event columns.
- [x] Kept the global safety control on Overview and relabeled it Master Execution without changing its public control name or pin contract.
- [x] Moved the former selected-Scheduler Overview detail into a dedicated Inspector page.
- [x] Moved Test Date/Time to Diagnostics, added Use Live Time, and removed the seeded test-time default for new components.
- [x] Deploy the design-time control/page change and verify fixed-bounds row geometry in Q-SYS Designer.
- [x] Validate ten-row banking, empty rows, bank boundaries, operational status fields, Master Execution safety, and live/test-time switching through QRC.
- [x] Re-run focused execution and editor regressions after the page/control lifecycle change.

Designer/QRC findings:

- The first retained-flow draft allowed grow columns to escape the intended row bounds in Designer. The corrected layout uses one fixed 880-unit FugUi Box per row and splits all local columns inside that box; visual inspection confirmed the table now fits the normal page width.
- Q-SYS exposes counted controls as runtime collections while QRC addresses them as `Name N`. The runtime now resolves both representations, and the hot-deploy fallback remains self-contained.
- Master Execution is now explicitly forced off at each runtime initialization, preventing a previously persisted armed value from surviving a restart.
- `tests/qrc/validate_overview.py` completed 39 assertions with byte-for-byte restoration and all three scripts healthy. It confirmed the bold Scheduler column, preference-formatted occurrence dates/times, equal-share wrapped detail columns, `source / Day Pattern` display, persistent live Enable/Pause transactions with revision increments, hidden toggles on unused rows, lower grey bank controls, and `Page N of M (Total X schedulers)` status. The existing execution suite completed 62 assertions and the Week Pattern, Override, and Override Date regressions completed 42, 48, and 54 assertions respectively after the page/control lifecycle change.

## Scheduler Definition and Slot architecture refactor

Implemented and deployed to the `fugscheduler2000_test` Designer emulator as build `0.1.0.20`. This supersedes the earlier banked Overview control contract above.

- [x] Added a design-time Scheduler Slot Count property with default 8 and range 1-32.
- [x] Replaced dynamic Scheduler rows with stable numbered `SchedulerSlot... N` controls and eight visible rows per bank.
- [x] Added filtered per-Slot Scheduler Definition assignment selectors; a Definition can be assigned to at most one Slot.
- [x] Made new and duplicated Scheduler Definitions unassigned and inert.
- [x] Moved enabled/paused operational state to Scheduler Slots and retained detailed Slot controls in Slot Inspector.
- [x] Added assigned-Slot readout and a disabled-when-unassigned `Unassign from Slot` helper to Scheduler Definitions.
- [x] Guarded Definition deletion in both UI state and runtime transactions while assigned.
- [x] Removed legacy Overview/Schedules controls rather than retaining compatibility aliases.
- [x] Deployed with reset schema-version-2 `ScheduleData`; the prior schema-version-1 value was backed up temporarily before the intentional development reset.
- [x] Rewrote the repeatable QRC suites for schema v2, Scheduler Definitions, assigned Slots, Slot status, and renamed controls.
- [x] Added repeatable filtered/forced-duplicate assignment, Slot Inspector mirroring, Unassign, and forced assigned-Definition deletion coverage.
- [x] Completed all safe current-time QRC suites: 328 assertions total with byte-for-byte restoration.
- [x] Updated and syntax-validated the genuine-midnight suite; live execution remains pending its required 20-second-to-25-minute pre-midnight window.

Designer/QRC findings:

- Build `0.1.0.20` produced a changed running component fingerprint and exposed the expected new controls while removing `Overview...`, `SchedulerSelect`, and `GlobalSchedulerStatus` controls.
- The first deployment exposed a control-panel layout error caused by reading height from a FugUi Box rather than its filled rectangle; the corrected layout deployed and simulated successfully.
- `SchedulerRuntimeProvider` and `ActionProvider` both reported `OK` with zero errors after hot-deploying the matching runtime.
- The repeatable Slot suite completed 26 assertions confirming filtered and forced-duplicate assignment behavior, active Enable/Pause controls only while assigned, stable assigned-ID output, assigned-slot count, Definition assignment readout, Unassign behavior, visual and forced deletion guards, false momentaries, Master Enable off, and byte-for-byte restoration.
- Empty aggregate Slot status now serializes as `"slots": []` rather than an empty JSON object.
- Execution regression found that moving an unchanged Definition between Slots could preserve an old timer phase and collide with a newly assigned Slot. Plans now retain their Slot number and derive a stable unique phase from that Slot; affected plans rebuild on Slot movement while unrelated Slot plans retain generation and phase.
- Completed suites: Week Patterns 42, Overrides 48, Override Dates 54, Scheduler Slots 26, Execution 70, Plan Lifecycle 24, Resolution 21, Scale 25, and Logging 18 assertions.

## Scheduler Slot pause transport

Implemented in source; Designer deployment and QRC acceptance remain pending:

- [x] Added persistent Manual, Next Event, Duration, Until Time, and Through Day modes to each fixed Scheduler Slot.
- [x] Added a persisted active `pauseIntent` with request time plus absolute expiry, next-calendar-date boundary, or dated Event target.
- [x] Kept steady-state evaluation inside the existing staggered one-second Slot poll with constant-time comparisons and no additional pause timers.
- [x] Deferred the one-time persistence/UI refresh for automatic expiry outside the execution callback.
- [x] Made Next Event and Through Day clear pause before the target occurrence so eligible one-shot and stateful Actions execute normally.
- [x] Kept manual/time resume on `fireOnResume`, skipped historical one-shots after unavailable runtime, and restarted repeats without catch-up.
- [x] Re-armed active intent immediately when mode/configuration changes and re-resolved Event targets after affected schedule edits.
- [x] Added stable per-Slot mode, duration, until-time, active Pause, and status controls/pins with dynamic `M`, `NE`, `DUR`, `UT`, and `TD` button legends.
- [x] Refactored Slot Inspector into stacked controls on the left and full-height live status on the right.
- [x] Added `tests/qrc/validate_pause_modes.py` for all five modes, re-arming, target updates, persistence, aggregate status, and guaranteed restoration.
- [x] Deploy the changed design-time controls while emulation is stopped and restart the expected test design.
- [x] Validate mode-dependent control availability, automatic expiry, Event-target retargeting, Through Day calendar behavior, and persisted intent reload.
- [x] Run pause, overview, execution, scale, and logging regressions and record assertion counts, restoration, performance, and script health.

Designer/QRC findings:

- The first reloaded plugin component fingerprint changed to `f40ba539b09a827c7526ea9283f66e1f` and exposed the new Inspector plus stable per-Slot pause controls. After the final layout, pinned-status, and UK-English message refinements, the component fingerprint changed to `c365454cc18aabe7bd6dad0c43c50fdc`.
- Slot Inspector uses a compact left-side Pause Controls section and full-height right-side Live Status section. Current and Next Event details are grouped side by side with bold Event names, scrollable one-row-per-Action type summaries, and selected-Slot countdowns refreshed by the existing one-second poll. The Inspector Pause button remains labelled `Pause`; compact Scheduler Slot Pause buttons use `M`, `NE`, `DUR`, `UT`, and `TD` legends. Slot Enable buttons are blank beneath the `Enable` table heading, while the Inspector button remains labelled `Enable` and uses illumination for state.
- `tests/qrc/validate_pause_modes.py` completed 17 assertions. It validated all five modes, active-intent clearing, deferred automatic expiry while Master Enable was off, Duration and Until Time absolute expiry, immediate active re-arming, Next Event target persistence and schedule-edit retargeting, Through Day's next-calendar-date boundary, persisted intent reload, aggregate status, stable per-Slot controls, byte-for-byte restoration, and final health.
- The first pause run exposed stale aggregate pause JSON while `TestDateTime` was pinned. Operational refresh now re-runs pinned resolution instead of suppressing status publication; the corrected pause suite passed.
- `tests/qrc/validate_overview.py` completed 26 assertions, including manual pause-intent mirroring and restoration.
- `tests/qrc/validate_execution.py` completed 70 assertions. Existing pause/resume, repeat, one-shot, plan-reuse, schedule-change, and real scheduled-edge behavior remained intact.
- The refined Slot Inspector build deployed as artifact `de2bb50612302f9f6c3d8b684d5f479645dda81bb250820b63e2012df0556e9d` and reloaded with component fingerprint `66f72a182a40abeb7a9935f1c151da19`. Current and Next Event names are bold; each group uses a scrollable one-row-per-Action viewer; Previous Event is no longer laid out in the Current Event group but its output pin remains available. `validate_overview.py` completed 27 assertions and `validate_execution.py` completed 73 assertions, including Action viewer rows and once-per-second countdown movement. Both suites restored persistent controls byte-for-byte and all three scripts finished `OK` with zero errors.
- `tests/qrc/validate_execution_scale.py` completed 25 assertions. At 5 × 10, average/maximum poll duration was `0.001300049`/`0.004999161` seconds with zero delayed polls. At 8 × 20, average/maximum was `0.000624895`/`0.003999710` seconds with zero delayed polls.
- `tests/qrc/validate_logging.py` completed 18 assertions with unchanged destination filtering and bounded diagnostics.
- Every suite restored changed persistent controls byte-for-byte. Master Enable finished off, and the plugin, runtime provider, and Action provider all finished `OK` with zero errors.
- The final pinned-status and UK-English runtime corrections were deployed in both the bundled `.qplug` and `SchedulerRuntimeProvider`. The generated/deployed artifact SHA-256 matched `670dc6346904f9cfef7e762874b7a303288379c964d8d8788ac5e5ce30919a04`; the plugin, runtime provider, and Action provider restarted `OK` with zero errors and Master Enable off.
- Build `0.1.0.27` deployed as SHA-256 `43539394450550147ccb194031ca164306921ea15edb18eae8852e8b1c6acff2`. The final Inspector presents Scheduler, bold Enable status, resolution, Day Pattern, pause details, aligned Current/Next groups, typed scrollable Action rows, and live countdowns. Final QRC regression counts were Week Patterns 42, Overrides 48, Override Dates 54, Scheduler Slots/Inspector 29, Pause Modes 17, Execution 73, Plan Lifecycle 24, Resolution 21, Scale 25, and Logging 18 assertions; all completed suites restored their fixtures and finished with scripts `OK` and zero errors. The live midnight-edge suite restored safely but was not executed because the emulator time was outside its required 25-minute pre-midnight window.

## Build validation

- [x] Run `python3 scripts/compile_plugin.py` successfully.
- [x] Confirm the generated `.qplug` has no unresolved `#include` directives.
- [ ] Validate with the official Q-SYS Plugin Compiler before any release milestone.
