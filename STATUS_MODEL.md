# FugScheduler 2000 Runtime Status Model

This document defines the machine-readable runtime status published by FugScheduler 2000. It is separate from persisted schedule configuration: configuration describes what should happen, while status describes how every configured Scheduler currently resolves.

## Integration boundary

The plugin maintains the latest snapshot in the global Lua table `FugSchedulerStatus` (also referenced by `FugSchedulerRuntime.globalStatus`) and publishes the same structure as JSON through the `GlobalSchedulerStatus` Text output control.

Third-party integrations should identify Schedulers by stable `id`, never by array position or operator-facing label. The `schedulers` array preserves the configured display order, but that order is not identity.

The initial status schema is:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-12-25 12:00:00",
  "resolvedFor": "2026-12-25 12:00:00",
  "configurationRevision": 1,
  "automaticExecutionEnabled": false,
  "health": {
    "state": "OK",
    "configurationValid": true,
    "actionRegistryValid": true,
    "warningCount": 0
  },
  "schedulers": []
}
```

`generatedAt` is when the snapshot was built. `resolvedFor` is the Core-local date/time used by the resolver and may differ during deterministic testing through `TestDateTime`.

## Scheduler status

Each configured Scheduler receives an independent entry:

```json
{
  "id": "site-music",
  "label": "Site Music",
  "enabled": true,
  "paused": false,
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
    "lastTransitionReason": "Automatic execution disabled",
    "lastCallbackResult": "None"
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

The root status also reports whether the plugin-wide automatic-execution safety control is enabled. Each Scheduler status may include runtime execution state such as its active occurrence, last transition reason, and most recent callback result. Resolver status remains available while execution is disabled, while a Scheduler is disabled, and while it is paused.

## Human-readable selected status

The Overview and Schedules pages use `SchedulerSelect` to choose one Scheduler for the existing human-readable status controls such as `CurrentEvent`, `NextEvent`, and `Countdown`. This selection does not limit global resolution: every configured Scheduler is resolved and included in `GlobalSchedulerStatus`.
