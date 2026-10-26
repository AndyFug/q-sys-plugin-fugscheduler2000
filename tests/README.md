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
python3 tests/qrc/validate_logging.py
```

These tests manipulate the active plugin component. Before running them:

1. Confirm QRC reports `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test`.
2. Confirm the expected controls exist and both the plugin and runtime provider report `OK` with zero script errors.
3. Ensure the required design-time `.qplug` was deployed while emulation was stopped, then restart emulation before runtime deployment or testing.

`validate_execution.py` additionally requires the `ActionProvider` Text Controller connected to the plugin's `ActionSource` input. It refuses to begin when the master automatic-execution guard is already armed. The test snapshots the provider's complete `code` source byte-for-byte, temporarily installs safe print callbacks plus one deliberately failing callback, and restores and verifies the original provider source during guaranteed cleanup. It uses a genuine upcoming `HH:MM` edge, so allow up to roughly 95 seconds for the focused edge phase.

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
