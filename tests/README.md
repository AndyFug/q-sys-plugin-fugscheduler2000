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
```

These tests manipulate the active plugin component. Before running them:

1. Confirm QRC reports `Platform = Emulator`, `State = Active`, and `DesignName = fugscheduler2000_test`.
2. Confirm the expected controls exist and both the plugin and runtime provider report `OK` with zero script errors.
3. Ensure the required design-time `.qplug` was deployed while emulation was stopped, then restart emulation before runtime deployment or testing.

`validate_execution.py` additionally requires the safe `Callback1` and `Callback2` provider from `references/action_source_test.lua`. It refuses to begin when the master automatic-execution guard is already armed, uses only callbacks that print test messages, and restores the guard off afterward.

Each stateful QRC test must:

- save the original persistent control text before mutation, including presentation preferences used by the test
- create temporary Scheduler-scoped test data rather than altering user configuration in place
- use `try/finally` restoration
- restore `ScheduleData` and any changed persistent preference controls byte-for-byte, not merely to equivalent decoded values
- verify restoration before reporting success
- leave momentary controls false and automatic callback execution disabled unless execution is explicitly under test
- fail clearly if the expected active emulator design cannot be identified

Record completed acceptance findings and assertion counts in `PHASE1_VALIDATION.md`.
