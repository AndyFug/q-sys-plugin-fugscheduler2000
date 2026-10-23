# FugScheduler 2000 Conceptual Model

This document defines the scheduler's shared terminology and conceptual behavior. It is the canonical product model for schedule configuration and resolution. Implementation details such as Q-SYS control counts, banked editors, and serialization are intentionally separate.

## Nomenclature

### Action

An **Action** is a named operation that the scheduler can execute. Actions are supplied by trusted external Lua through `GetFugSchedulerActions()`.

Examples:

- `MusicMorning`
- `MusicOff`
- `PlayClosingAnnouncement`
- `EnableDeIcer`

Each Action has a stable ID, an operator-facing label, a callback, and optional metadata/default behavior. Schedule configuration stores the stable Action ID, never the callback function or display label.

### Action Registry

The **Action Registry** is the runtime list of valid Actions currently supplied by the external Action Provider.

An Event Action that references an ID absent from the Action Registry is invalid and must not execute. Updating the registry must not delete persisted schedule configuration.

### Event Action

An **Event Action** is an assignment of a registered Action to an Event.

This distinction allows:

- one Action to be reused by many Events
- one Event to execute several Actions
- per-assignment behavior to override Action defaults in the future
- the execution order within an Event to remain explicit

Potential Event Action options include one-shot behavior, startup firing, repeat interval, enabled state, and future delay or guard settings. The exact inheritance rules between Action defaults and Event Action overrides remain to be defined.

### Event

An **Event** defines a time and an ordered list of Event Actions.

Example:

```text
Event: Morning Opening
Time: 09:00

1. Unmute Site
2. Select Morning Music
3. Enable Public Areas
```

At the Event's scheduled edge, Event Actions execute in their configured order. Each callback is isolated with `pcall`; a failed Action is logged and does not prevent later Actions in the same Event from running.

Events retain stable row identity for editing even when the runtime sorts them by normalized time. Scheduler IDs are unique in the persisted root; Day Pattern, Week Pattern, Event, and Override IDs are unique within their owning Scheduler.

### Day Pattern

A **Day Pattern** is a reusable definition of one day's schedule. It contains zero or more Events.

Example:

```text
Day Pattern: Standard Weekday

09:00  Morning Opening
14:00  Afternoon Change
17:00  Evening Change
22:00  Site Closing
```

Other examples include `Standard Weekend`, `Closed`, `Build Day`, `Late Opening`, and `Christmas Day`.

### Week Pattern

A **Week Pattern** assigns a Day Pattern to each day of the week.

Example:

```text
Week Pattern: Normal Operating Week

Monday     -> Standard Weekday
Tuesday    -> Standard Weekday
Wednesday  -> Standard Weekday
Thursday   -> Standard Weekday
Friday     -> Standard Weekday
Saturday   -> Standard Weekend
Sunday     -> Standard Weekend
```

A Scheduler has a Default Week Pattern. Week Patterns can also be selected by Week Pattern Overrides.

### Override

An **Override** replaces normal pattern resolution for an inclusive date range. Every Override has:

- stable ID
- operator-facing name
- enabled state
- type
- start date
- end date
- selected pattern appropriate to its type
- precedence within the Override list

The initial Override types are Day Pattern Override and Week Pattern Override. The model may later add recurrence, exclusions, holiday imports, or other resolution rules without changing Day Patterns or Week Patterns.

### Day Pattern Override

A **Day Pattern Override** applies one Day Pattern to every date in its inclusive range.

Example:

```text
Name: Christmas Closure
Type: Day Pattern Override
Start: 2026-12-24
End: 2026-12-26
Day Pattern: Closed
```

A single-date override uses the same start and end date.

### Week Pattern Override

A **Week Pattern Override** applies one Week Pattern throughout an inclusive date range. For each date, the Scheduler uses the date's actual weekday to select a Day Pattern from that Week Pattern.

Example:

```text
Name: Christmas Operations
Type: Week Pattern Override
Start: 2026-12-21
End: 2027-01-03
Week Pattern: Christmas Week
```

The range does not need to begin on Monday or end on Sunday.

### Scheduler

A **Scheduler** is one independent scheduling system. It owns:

- identity and operator-facing label
- enabled/paused state
- Default Week Pattern
- Day Patterns
- Week Patterns
- Overrides
- runtime resolution state

Examples include `Site Music`, `Site Mute`, `Ice Rink Announcements`, `Big Wheel`, and `De-Icer`.

The plugin supports multiple independent Schedulers from the persisted root. Editors may display one selected Scheduler at a time, but validation, resolution, runtime state, and integration status remain independent for every configured Scheduler. Newly created Schedulers use opaque UUID-style stable IDs; normal operator UI displays Scheduler labels while status and persisted JSON retain the IDs for integration identity.

## Model hierarchy

```text
Scheduler
├── Default Week Pattern
├── Week Patterns
│   └── Monday-Sunday Day Pattern assignments
├── Day Patterns
│   └── Events
│       ├── Time
│       └── Ordered Event Actions
│           └── Action ID
├── Overrides
│   ├── Day Pattern Overrides
│   └── Week Pattern Overrides
└── Action Registry (runtime-only)
```

## Date resolution

For any calendar date, the Scheduler resolves the Day Pattern in this order:

1. Find the first matching enabled Day Pattern Override. If found, use its Day Pattern directly.
2. Otherwise, find the first matching enabled Week Pattern Override. If found, use that Week Pattern and select the Day Pattern assigned to the date's actual weekday.
3. Otherwise, use the Scheduler's Default Week Pattern and select the Day Pattern assigned to the date's weekday.

Start and end dates are inclusive.

### Override precedence

The initial precedence rules are:

1. Day Pattern Overrides take priority over Week Pattern Overrides.
2. Within the same type, Overrides are evaluated in explicit UI priority order.
3. The first matching enabled Override wins.
4. The UI warns about overlapping ranges so precedence is visible rather than accidental.

This permits a broad Week Pattern Override with a more specific Day Pattern Override inside it, such as a Christmas operating period containing a Christmas Day closure.

## Timeline resolution

After resolving the applicable Day Pattern, the Scheduler sorts its Events by normalized time.

At any moment it determines:

- **Current Event**: the most recent applicable Event at or before now
- **Previous Event**: the Event before the Current Event
- **Next Event**: the next applicable Event after now

Resolution crosses midnight. Before today's first Event, the Current Event may come from yesterday's resolved Day Pattern. After today's last Event, the Next Event comes from tomorrow's resolved Day Pattern. Yesterday, today, and tomorrow are each resolved independently through the Override and Week Pattern rules.

If multiple Events share the same time, they retain their persisted array order as the deterministic tie-break order. The editor permits this configuration but warns the operator and recommends combining simultaneous operations into one Event with ordered Event Actions where practical. Scheduled execution must process every Event at the shared edge in that same order.

## Event execution

When time crosses an Event's scheduled edge:

1. The Event becomes current.
2. Its enabled Event Actions are processed in configured order.
3. Each Action ID is looked up in the current Action Registry.
4. Each callback is invoked independently with `pcall`.
5. Missing Actions and callback failures are logged and surfaced without stopping the Scheduler.
6. Runtime status is updated with current, previous, and next information.

Manual Action testing does not change the Scheduler's current Event or timeline state.

## State-restoring and one-shot behavior

An Event Action may represent either state or a momentary occurrence.

### State-restoring Action

Examples include selecting a music mode, muting a site, or enabling a de-icer. On startup or resume, the current state-restoring Event Action may execute immediately so the physical system matches the schedule. It may optionally repeat while its Event remains current.

### One-shot Action

Examples include playing an announcement or sending a pulse. A one-shot Event Action executes only when the Scheduler observes its scheduled edge. Starting or resuming after that edge must not replay it automatically.

Whether these behaviors are primarily Action defaults, Event Action settings, or inherited defaults with overrides remains an implementation decision.

## Pause behavior

While paused, the Scheduler continues resolving dates, Day Patterns, Events, and status, but it does not execute scheduled callbacks.

On resume, the recommended behavior is:

- execute applicable current state-restoring Event Actions
- do not replay missed one-shot Event Actions
- restart repeat behavior from a defined resume policy

The exact repeat timing policy must be specified and tested before engine completion.

## Persisted versus runtime data

Persisted configuration is a versioned root containing an ordered `schedulers` array. Array order is used for display; each Scheduler's stable ID is its identity.

Persisted configuration includes:

- Scheduler settings
- Day Patterns
- Events
- Event Action assignments and options
- Week Patterns
- Overrides
- stable IDs and labels

Runtime-only data includes:

- callback functions
- Action Registry generation
- resolved Day Pattern
- current, previous, and next Events
- timestamps and countdowns
- active repeat timers
- validation and callback errors

## Worked example

```text
Default Week Pattern: Normal Operating Week
Friday assignment: Standard Weekday

Week Pattern Override:
  Christmas Operations
  2026-12-21 through 2027-01-03
  Pattern: Christmas Week

Day Pattern Override:
  Christmas Day Closure
  2026-12-25 through 2026-12-25
  Pattern: Closed
```

For Friday 2026-12-25:

1. `Christmas Day Closure` matches as a Day Pattern Override.
2. `Closed` becomes the resolved Day Pattern.
3. The broader `Christmas Operations` Week Pattern Override is not used for that date.

For Saturday 2026-12-26:

1. No Day Pattern Override matches.
2. `Christmas Operations` matches as a Week Pattern Override.
3. Saturday's assignment in `Christmas Week` selects the applicable Day Pattern.

For a date outside both ranges:

1. No Override matches.
2. The Scheduler uses `Normal Operating Week`.
3. The date's weekday selects its Day Pattern.
