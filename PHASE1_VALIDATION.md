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
- [ ] Validate normal edge ordering, duplicate-time ordering, callback failure isolation, and unavailable Action handling.
- [x] Validate startup, Scheduler enable, pause, resume, and repeat behavior for stateful Event Actions.
- [ ] Validate that one-shots are not replayed on startup, enable, resume, or forward clock discontinuity; startup, enable, and resume are complete.
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

Remaining execution validation covers real scheduled edges, equal-time Event ordering, callback failure/unavailable Action isolation, and forward/backward clock discontinuities.

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

## Build validation

- [x] Run `python3 scripts/compile_plugin.py` successfully.
- [x] Confirm the generated `.qplug` has no unresolved `#include` directives.
- [ ] Validate with the official Q-SYS Plugin Compiler before any release milestone.
