# FugScheduler 2000 Tests

Repeatable verification belongs under `tests/`; build and deployment utilities remain under `scripts/`.

## Test categories

- `qrc/` — live Q-SYS Designer emulator integration and acceptance tests using QRC.
- Future offline/unit tests should use a separate directory such as `unit/` and must not require Designer or a Core.

## QRC acceptance tests

Run from the plugin repository root:

```bash
python3 tests/qrc/validate_week_patterns.py
python3 tests/qrc/validate_overrides.py
python3 tests/qrc/validate_override_dates.py
python3 tests/qrc/validate_execution.py
python3 tests/qrc/validate_execution_plan_lifecycle.py
python3 tests/qrc/validate_execution_resolution.py
python3 tests/qrc/validate_execution_scale.py
# Run shortly before local midnight; this intentionally waits for 00:00.
python3 tests/qrc/validate_execution_midnight.py
python3 tests/qrc/validate_logging.py
```

These tests manipulate the active plugin component. Before running them:

1. Confirm QRC reports `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test`.
2. Confirm the expected controls exist and both the plugin and runtime provider report `OK` with zero script errors.
3. Ensure the required design-time `.qplug` was deployed while emulation was stopped, then restart emulation before runtime deployment or testing.

`validate_execution.py` additionally requires the `ActionProvider` Text Controller connected to the plugin's `ActionSource` input. It refuses to begin when the master automatic-execution guard is already armed. The test snapshots the provider's complete `code` source byte-for-byte, temporarily installs safe print callbacks plus one deliberately failing callback, and restores and verifies the original provider source during guaranteed cleanup. It uses a genuine upcoming `HH:MM` edge, so allow up to roughly 95 seconds for the focused edge phase.

The execution test also inspects runtime-plan diagnostics in `GlobalSchedulerStatus`: one plan per Scheduler, distinct stagger phases, independent timer poll counts, Scheduler/Event/Action counts, affected-plan generation replacement, and unrelated plan/timer preservation after a scoped edit. These fields are runtime-only and must remain absent from `ScheduleData`.

`validate_execution_scale.py` replaces the schedule temporarily with disabled synthetic fixtures at 5 Schedulers × 10 Events and 20 × 20. It measures QRC install elapsed time plus the runtime's average/maximum poll, delayed-poll, and rebuild diagnostics. All synthetic Event Actions use a safe callback ID, but every Scheduler remains disabled and the master guard must remain off. The test restores `ScheduleData` and `TestDateTime` byte-for-byte.

`validate_execution_plan_lifecycle.py` explicitly adds and removes a Scheduler plan, verifies that its independent timer polls, waits through multiple former timer periods after deletion, and confirms that an unaffected plan retains its generation and timer phase while continuing to poll.

`validate_execution_resolution.py` keeps execution disabled while exercising detached `TestDateTime` resolution across midnight, an inclusive Override boundary, and a 121-day empty Day Pattern range. It verifies dated occurrence identity and restores both changed persistent controls byte-for-byte.

`validate_execution_midnight.py` is a long-running acceptance test that must start 20 seconds to 25 minutes before the emulator's local midnight. It installs one safe temporary Scheduler, arms execution, and waits for genuine 23:59 and 00:00 Events without changing any clock. Do not interrupt it after fixture installation; if the harness is forcibly killed, immediately disable `AutomaticExecutionEnabled` and restore the saved fixture controls before any further testing.

An exploratory 50 × 20 phase is available with `FUGSCHEDULER_SCALE_50=1`. Current Designer testing shows that writing and synchronously decoding/validating that approximately 1,000-Event schema can exceed the Q-SYS script transaction budget before plan installation. It is excluded from the normal acceptance run until large external `ScheduleData` validation is given a separately approved staged/deferred design.

`TestDateTime` affects deterministic resolver display only; live execution polling uses Core-local `os.time()`. The current design has no validated clock-discontinuity injection mechanism. Do not change the host/emulator/Core clock to test jumps. Backward and forward discontinuity acceptance remains blocked unless a dedicated test seam is proposed and approved.

`validate_logging.py` checks normalized numeric preference IDs, basic Debug Output filtering through `log.history`, unconditional bounded DiagnosticLog routing, and preference handlers. Core Event Log visibility still requires a brief Designer observation because the current test design does not expose an Event Log component through QRC.

Each stateful QRC test must:

- save the original persistent control text before mutation, including presentation preferences used by the test
- create temporary Scheduler-scoped test data rather than altering user configuration in place
- use `try/finally` restoration
- restore `ScheduleData` and any changed persistent preference controls byte-for-byte, not merely to equivalent decoded values
- verify restoration before reporting success
- leave momentary controls false and automatic callback execution disabled unless execution is explicitly under test
- fail clearly if the expected active emulator design cannot be identified

Record completed acceptance findings and assertion counts in `PHASE1_VALIDATION.md`.
