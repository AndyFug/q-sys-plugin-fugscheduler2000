# FugScheduler 2000

FugScheduler 2000 is a new Q-SYS plugin project for creating, editing, and running reusable schedules through a friendlier UI than a hand-authored Text Controller script.

The behavioral baseline is the working implementation in:

```text
references/fugSchedulerTextController.lua
```

That controller demonstrates multiple independent Schedulers, reusable Action definitions, daily patterns, weekday defaults, special-date overrides, one-shot Actions, repeating Actions, startup behavior, pause/resume, current/next/previous status, countdowns, and logging. FugScheduler 2000 evolves those ideas into the terminology and hierarchy defined in `SCHEDULER_MODEL.md`.

## Scheduler model

The canonical concepts are documented in `SCHEDULER_MODEL.md`; the multi-Scheduler integration status contract is documented in `STATUS_MODEL.md`. A deferred staged-versus-running configuration and commit proposal is recorded in `DRAFT_PUBLISH_MODEL.md`:

- Actions are externally supplied operations.
- Events define a time and an ordered list of Event Actions.
- Day Patterns contain Events.
- Week Patterns assign Day Patterns to Monday through Sunday.
- Day Pattern and Week Pattern Overrides apply patterns over inclusive date ranges.
- A Scheduler resolves the applicable Day Pattern and executes its Events.

## Intended architecture

The plugin will own Day Patterns, Events, Week Patterns, Overrides, and scheduler execution, but site-specific Actions will remain external initially. A separate Text Controller's built-in `code` output connects to the plugin's ordinary `ActionSource` Text input. The transmitted source defines `GetFugSchedulerActions()`, which returns named callbacks and metadata for the scheduler UI.

Designer and QRC testing confirms that the plugin can evaluate this source, populate the Actions page, invoke callbacks, access `Component.New`, isolate failures, retain the previous valid registry, and hot-reload runtime code through `SchedulerRuntimeProvider`. See `PLAN.md` and `PHASE1_VALIDATION.md`.

## Current state

Initial boilerplate includes:

- template/compiler-style source under `src/`
- a vendored copy of the shared FugUi framework
- project documentation and phased plan
- a repo-local include compiler
- a generated `FugScheduler2000.qplug`
- an ordinary hidden `ActionSource` Text input control pin
- a reserved hidden `code` input for supplying the complete runtime during live debugging
- a banked operational Overview with ten Scheduler status rows and live Enable/Pause toggles, a selected-Scheduler Inspector, Schedules, Day Patterns, Week Patterns, Overrides, Actions, Preferences, Diagnostics, and About pages, with the public plugin version shown in the shared header and version, build, locally formatted build date, plugin ID, and author metadata on About
- a Phase 1 Action Registry that compiles trusted source, calls `GetFugSchedulerActions()`, validates Actions, and provides guarded callback execution
- versioned persistent `ScheduleData` JSON containing an ordered array of Schedulers, with a documented sample in `references/sample_schedule.json`
- independent validation and read-only resolution for every Scheduler's Day Patterns, Week Patterns, Overrides, and previous/current/next Events
- deterministic `TestDateTime` resolution retained as a Diagnostics-only commissioning tool, plus a guarded execution engine whose Overview-level Master Execution safety toggle defaults off
- aggregate `GlobalSchedulerStatus` JSON plus a selected-Scheduler status view for third-party integrations and UI inspection
- a validated configuration transaction layer that strips runtime indexes, commits only complete schema-v1 candidates, preserves the previous valid model on failure, and avoids recursive `ScheduleData` handling
- a first visual Scheduler editor using label-based structured selectors for Scheduler and Default Week Pattern selection, plus labels, enabled/paused state, add, duplicate, guarded delete, and transaction feedback
- a three-column Day Patterns editor with scrollable Day Pattern, Event, and Event Action lists; Day Pattern/Event CRUD; registered Action attachment; Action deletion and ordering; per-assignment enabled, one-shot, startup/resume, and repeat options; reference-guarded Day Pattern deletion; and contextual validation feedback
- a visual Week Patterns editor with a scrollable structured selector, label/add/duplicate/guarded-delete transactions, seven structured Day Pattern assignments, per-Scheduler runtime selection, and reference summaries
- a visual Scheduler-scoped Overrides editor for ordered Day Pattern and Week Pattern Overrides, including presentation-only DMY/MDY/ISO date preferences, buffered date validation, long-form dates, inclusive range summaries, atomic duration-preserving Start edits, convenience duration controls, type-dependent pattern selection, enabled state, add/duplicate/delete/move transactions, overlap warnings, and per-Scheduler runtime selection
- opaque UUID-style IDs for newly created Schedulers, Day Patterns, Week Patterns, and Events; IDs remain in persisted/status integration data rather than the primary operator UI
- disabled-by-default creation and duplication of Schedulers and Overrides so their configuration can be completed before activation
- compiled per-Scheduler execution plans with phase-staggered retained timers, cached rolling Previous/Current/Next occurrence cursors, ordered edge execution, startup/resume state restoration, missed one-shot suppression, repeat deadlines, callback isolation, performance diagnostics, and clock-discontinuity handling behind the master execution guard
- centralized severity-based logging to the bounded DiagnosticLog, filtered Debug Output, and filtered Q-SYS Event Log, with edge executions at Info and repeats at Debug

## Build

From this directory:

```bash
python3 scripts/compile_plugin.py
```

Deploy only when the Q-SYS Designer plugin directory is mounted and deployment is requested:

```bash
python3 scripts/compile_plugin.py --deploy
```

See `BUILD.md` and `../QSYS_PLUGIN_BUILD.md` for details.

## Testing

Repeatable tests live under `tests/`; `scripts/` is reserved for build and deployment tooling. The current live emulator acceptance tests are:

```bash
python3 tests/qrc/validate_week_patterns.py
python3 tests/qrc/validate_overrides.py
python3 tests/qrc/validate_override_dates.py
python3 tests/qrc/validate_execution.py
python3 tests/qrc/validate_logging.py
```

These tests require the expected active Designer emulator design and restore the original `ScheduleData` byte-for-byte. See `tests/README.md` and `PHASE1_VALIDATION.md`.
