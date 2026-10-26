# AGENTS.md

FugScheduler 2000-specific instructions for AI coding agents.

This project inherits the shared Q-SYS plugin workspace guidance from `../AGENTS.md`. Read that first for general SDK, build, deploy, source layout, and commenting conventions.

## Read first

Before making non-trivial FugScheduler changes, read:

- `README.md` — project summary and current status.
- `PLAN.md` — proposed architecture, phases, open questions, and acceptance criteria.
- `SCHEDULER_MODEL.md` — canonical nomenclature, hierarchy, date resolution, Event execution, and Override precedence.
- `DRAFT_PUBLISH_MODEL.md` — deferred proposal for separating persistent edits from published/live configuration.
- `BUILD.md` — artifact name and local build wrapper.
- `PHASE1_VALIDATION.md` — active Q-SYS Designer validation checklist.
- `tests/README.md` — local test categories, QRC prerequisites, and restoration rules.
- `references/fugSchedulerTextController.lua` — the working text-controller implementation that defines the initial behavioral baseline.
- `../QSYS_PLUGIN_BUILD.md` — shared workspace build/deploy workflow.
- `../.agents/skills/qsys-plugin-sdk/SKILL.md` — portable Q-SYS SDK workflow, official references, and Designer-validated supplemental notes.
- `../docs/qsys/README.md` — shared workspace Q-SYS guidance and research notes.
- `../shared/qsys-ui/UI_MIGRATION.md` — shared FugUi usage and vendoring rules.

## Source and build flow

- Edit source files under `src/`.
- Treat `FugScheduler2000.qplug` as generated/deployable output.
- Compile from this directory:

```bash
python3 scripts/compile_plugin.py
```

- Deploy only when asked:

```bash
python3 scripts/compile_plugin.py --deploy
```

## Project-specific rules

- Preserve the scheduler concepts proven in the reference controller: actions, patterns, weekday defaults, special dates, current/previous/next events, pause, one-shot actions, startup firing, repeat intervals, status, countdowns, and logging.
- Do not couple the scheduler engine to site-specific Q-SYS components or actions. Actions must enter through a documented registration boundary.
- Treat external callback code as trusted design code but still isolate registration and callback execution with validation and `pcall` where Q-SYS permits it.
- Validate the official Q-SYS `code` control-pin behavior before implementing custom Lua string evaluation. Prefer the SDK-supported code-pin mechanism over `load`/`loadstring` unless testing proves a separate evaluator is necessary and supported.
- Keep persistent schedule data separate from runtime-derived state. Control values should be the initial persistence mechanism unless Designer testing supports a better option.
- Keep dynamic counts and generated control names centralized in `src/globals.lua`.
- Keep generic UI behavior in vendored `src/fug_ui.lua`; scheduler-specific widgets belong in `src/ui.lua` and page composition in `src/layout.lua`.
- The vendored FugUi file must remain self-contained; release builds must not include workspace-relative paths.
- Record Q-SYS Designer findings and any deviations from the plan in project documentation before relying on them.

## Logging strategy

- Route scheduler runtime messages through the centralized logger in `src/runtime.lua`; do not call `print`, `Log.Message`, or `Log.Error` directly elsewhere in the plugin runtime.
- Use the normalized numeric levels `DEBUG = 7`, `INFO = 6`, `ERROR = 3`, and `OFF = 0`. Structured preference choices persist these numeric IDs rather than relying on display labels.
- Keep the two external destination thresholds independent: Debug Output uses `print` and defaults to Info; the Q-SYS Event Log uses `Log.Message`/`Log.Error` and defaults to Off.
- Keep logging preferences in their own persistent controls, separate from `ScheduleData`.
- Always send Debug, Info, and Error entries to the in-plugin `DiagnosticLog`, regardless of external destination settings. Retain only the newest 12,000 characters and trim complete oldest lines where possible.
- Use concise, consistent severity/context formatting. Include Scheduler, Event, Action, and execution reason labels/IDs when available. Add plugin identity and Code Name only where useful for the shared Q-SYS Event Log; Debug Output does not need redundant plugin metadata.
- Log successful initial Event Action execution at Info. Log subsequent repeat execution at Debug. Log missing Actions, callback failures, validation failures, resolver failures, and unexpected execution-engine failures at Error.
- Continue updating `ExecutionStatus` with the latest execution result independently of destination filtering. Callback failures must remain isolated and must not prevent later Event Actions.
- Never emit routine messages from the one-second execution poll. Any new debug logging must be event-driven and respect configured thresholds to avoid flooding Debug Output or the Event Log.
