# FugScheduler 2000 Runtime Status Model

This document defines the machine-readable runtime status published by FugScheduler 2000. It is separate from persisted schedule configuration: configuration describes what should happen, while status describes how every configured Scheduler currently resolves.

## Integration boundary

The plugin maintains the latest snapshot in the global Lua table `FugSchedulerStatus` (also referenced by `FugSchedulerRuntime.globalStatus`) and publishes the same structure as JSON through the `GlobalSchedulerSlotStatus` Text output control.

Third-party integrations should address runnable schedulers by stable Slot number. Each assigned Slot status also reports the assigned Scheduler Definition's stable `schedulerId`; definition labels and library array positions are not runtime identity.

The public control-pin contract exposes the global Master Enable, Action source/reload controls, aggregate JSON, and stable counted Scheduler Slot controls. Counted pins use Q-SYS hierarchical pretty names grouped by control, for example `SchedulerSlotEnabled~Slot 01` and `SchedulerSlotCurrentEvent~Slot 01`. Page-only status bars, diagnostics, selected-Slot mirrors, and viewer controls remain internal to avoid duplicate display-only pins.

The initial status schema is:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-12-25 12:00:00",
  "resolvedFor": "2026-12-25 12:00:00",
  "configurationRevision": 1,
  "automaticExecutionEnabled": false,
  "oneShotPolicy": {
    "lateToleranceSeconds": 0,
    "receiptCount": 0,
    "receiptRetentionSeconds": 14400,
    "receiptMaximumCount": 1024
  },
  "health": {
    "state": "OK",
    "configurationValid": true,
    "actionRegistryValid": true,
    "warningCount": 0
  },
  "slots": []
}
```

`generatedAt` is when the snapshot was built. `resolvedFor` is the Core-local date/time used by the resolver and may differ during deterministic testing through `TestDateTime`.

## Scheduler Slot status

Each assigned Scheduler Slot receives an independent entry:

```json
{
  "slot": 3,
  "schedulerId": "site-music",
  "label": "Site Music",
  "enabled": true,
  "paused": false,
  "pause": {
    "mode": "NextEvent",
    "modeLabel": "Next Event",
    "abbreviation": "NE",
    "active": false,
    "durationMinutes": 60,
    "untilTime": "",
    "intent": null,
    "status": "Ready — Next Event",
    "target": "None"
  },
  "health": {
    "state": "OK",
    "message": ""
  },
  "resolution": {
    "date": "2026-12-25",
    "source": "Day Override: Christmas Day Closure",
    "sourceType": "DayPatternOverride",
    "sourceId": "christmas-day",
    "dayPatternId": "closed",
    "dayPatternLabel": "Closed"
  },
  "execution": {
    "allowed": false,
    "initialized": true,
    "activeOccurrence": {},
    "activeRepeatCount": 0,
    "lastObservedTime": "2026-12-25 12:00:00",
    "lastTransitionReason": "Master Enable is off",
    "lastCallbackResult": "None",
    "planGeneration": 12,
    "configurationRevision": 42,
    "timerPhaseSeconds": 0.35,
    "performance": {
      "pollCount": 1200,
      "averagePollDurationSeconds": 0.0004,
      "maximumPollDurationSeconds": 0.003,
      "delayedPollCount": 0,
      "planRebuildDurationSeconds": 0.002,
      "eventCount": 10,
      "actionCount": 14
    }
  },
  "resolvedDayPattern": {
    "id": "closed",
    "label": "Closed",
    "events": [
      {
        "id": "closed-state",
        "label": "Closed State",
        "time": "00:00",
        "actionIds": ["site-mute"]
      }
    ]
  },
  "previousEvent": {},
  "currentEvent": {},
  "nextEvent": {},
  "nextTransitionSeconds": 79200,
  "nextTransitionCountdown": "22:00:00"
}
```

`resolvedDayPattern.events` preserves the old Text Controller's ability to inspect the active pattern while using stable Event and Action IDs from the new model.

The `pause` object reports the Slot's saved mode/configuration and its active persisted intent. Active intents contain `requestedAt` plus either `expiresAt`, `notBeforeDate`, or a dated target occurrence with timestamp, Event ID, Day Pattern ID, and equal-time sequence. The legacy top-level `paused` Boolean remains the concise active-state field.

A failure resolving one Scheduler sets that Scheduler's health to `Error` without removing the status entries for other Schedulers. The root health is also set to `Error` when any Scheduler resolution fails.

## Event occurrence status

Previous, current, and next Event fields are either absent or contain an occurrence with its stable identity and absolute resolved time:

```json
{
  "id": "morning-opening",
  "label": "Morning Opening",
  "date": "2026-12-25",
  "time": "09:00",
  "scheduledTime": "2026-12-25 09:00:00",
  "timestamp": 1798189200,
  "dayPatternId": "standard-weekday",
  "dayPatternLabel": "Standard Weekday",
  "actions": []
}
```

## Event Action status

Event Actions remain ordered and report whether their registered Action is currently available:

```json
{
  "order": 1,
  "actionId": "site-music-morning",
  "actionLabel": "Site Music: Morning",
  "available": true,
  "enabled": true,
  "oneShot": false,
  "fireOnStartup": true,
  "fireOnResume": true,
  "repeatSeconds": 300
}
```

These fields reflect the explicit persisted Event Action values. New assignments copy validated Action defaults once when attached; later Action Registry reloads do not rewrite schedule configuration.

The root status also reports whether the plugin-wide automatic-execution safety control is enabled, the active global one-shot late tolerance and bounded persistent receipt count, and a `performance` summary containing Scheduler/Event/Action counts, total poll count, average and maximum measured poll duration, delayed-poll count, and total plan-rebuild duration. `Timer.Now()` supplies elapsed measurements only; these values are diagnostics rather than scheduling timestamps.

Each Scheduler status includes its plan generation, configuration revision, stagger phase, per-plan performance counters, active occurrence, last transition reason, and most recent callback result. Plan generations and timer phases are runtime diagnostics and are not stable integration identity. Resolver status remains available while execution is disabled, while a Scheduler is disabled, and while it is paused.

## Human-readable selected status

The banked Scheduler Slots page displays eight fixed numbered Slots at a time. Each row provides a filtered Scheduler Definition assignment selector plus live Enable/Pause controls. The compact Pause button legend reports `M`, `NE`, `DUR`, `UT`, or `TD` for the configured mode. Definitions assigned to another Slot are excluded from the selector. Slot Inspector selects a Slot independently and provides the same runtime controls with detailed resolution and Event status. Live Status begins with Scheduler name and a bold Enable status (`Enabled — Master Enable on`, `Inhibited — Master Enable off`, `Disabled — Slot Enable off`, or `Unassigned`). It uses the same theme-safe text colour as the other Live Status values. Live Status then shows resolution source, Day Pattern, followed by pause status/request/target/remaining details. Its Current and Next Event groups show bold Event names, scrollable one-Action-per-row type summaries (`Stateful`, repeating interval, or `One Shot`) while retaining comma-separated output-pin summaries, and once-per-second live countdowns sourced from the selected Slot's existing execution poll. Scheduler Definition editors use a separate stable-ID selector; unassigned Definitions are inert and absent from `GlobalSchedulerSlotStatus.slots`.

`TestDateTime` is a developer-only Diagnostics aid. Blank means live time; a non-empty value deliberately pins Slot Inspector and aggregate JSON output until the developer presses Use Live Time. It never changes live execution cursors. The runtime clears it on plugin start, when Master Enable is turned on, and when any Scheduler Slot is enabled so normal operational views cannot retain a stale preview timeline.
