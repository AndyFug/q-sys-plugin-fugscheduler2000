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

Event Action execution options are persisted on each assignment:

- `enabled` — whether the assignment participates in automatic execution
- `oneShot` — execute only when its scheduled edge is observed
- `fireOnStartup` — restore the Action when the engine starts while its Event is current
- `fireOnResume` — restore the Action when a paused Scheduler resumes while its Event is current
- `repeatSeconds` — optional interval while the Event remains current

New assignments copy any validated defaults supplied by the registered Action. The copied values then belong to the Event Action and do not change when the Action Registry is reloaded. When no defaults are supplied, assignments are enabled, stateful, do not restore automatically, and do not repeat.

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

## Runtime occurrence cursor

Live execution compiles each validated Scheduler into runtime-only Event order and date-resolution caches. The authoritative cursor retains Previous, Current, and Next occurrences rather than rebuilding and sorting a multi-day timeline on every poll.

Each occurrence includes its Core-local timestamp, calendar date, configured time, stable Event and Day Pattern references/IDs, and persisted Event ordering sequence. When positioned around a timestamp, Current is the final occurrence at or before that timestamp, Previous is immediately before Current, and Next is the first occurrence after Current. Equal-time Events therefore advance one-by-one in persisted Event array order.

The occurrence window grows date-by-date near its future boundary and discards obsolete history while retaining Previous for status. Empty dates and long gaps are resolved incrementally. Re-anchor and detached resolver searches use a 400-calendar-day safety horizon in each direction; a live cursor with no Event inside that horizon extends the search by another horizon as wall time reaches the cached boundary. A Scheduler with no configured Events bypasses horizon scanning entirely.

Compiled Event order, date caches, occurrence windows/indexes, timer objects, generation tokens, callback functions, repeat deadlines, performance counters, and lifecycle state are runtime-only and never enter `ScheduleData`.

## Event execution

When time crosses an Event's scheduled edge:

1. The Event becomes current.
2. Every enabled Event Action executes in configured order, whether stateful or one-shot.
3. Each Action ID is looked up in the current Action Registry.
4. Each callback is invoked independently with `pcall`.
5. Missing Actions and callback failures are logged and surfaced without stopping later Actions.
6. Non-one-shot repeat intervals begin from the observed transition time.
7. Runtime status is updated with current, previous, and next information.

The engine detects ordinary edges over the interval `lastObservedTime < occurrenceTime <= currentTime`. Events sharing one timestamp execute in persisted Event order, with each Event's Actions retaining their configured order.

When an immediate configuration change alters which Event is current, the newly current Event's enabled stateful Actions execute immediately with reason `schedule change`; its one-shot Actions do not execute. Repeat intervals restart from the reconciliation time. This applies consistently to Event time/deletion edits, pattern assignment changes, Default Week Pattern changes, and Override changes. No reconciliation callback occurs while the master guard is off or the Scheduler is disabled or paused.

Manual Action testing does not change Scheduler timeline or execution state.

## State-restoring and one-shot behavior

An Event Action may represent either state or a momentary occurrence.

### State-restoring Action

Examples include selecting a music mode, muting a site, or enabling a de-icer. It always executes at its normal Event edge. When `fireOnStartup` or `fireOnResume` is enabled, it also executes when the already-current Event is activated through the corresponding lifecycle transition. It may optionally repeat while its Event remains current.

### One-shot Action

Examples include playing an announcement or sending a pulse. A one-shot Event Action executes only when the Scheduler observes its scheduled edge. Starting, enabling, or resuming after that edge must not replay it automatically. One-shot assignments cannot use startup firing, resume firing, or repeat intervals.

## Pause behavior

While paused, the Scheduler continues resolving dates, Day Patterns, Events, and status, but it does not execute scheduled callbacks. Event edges crossed during the pause are missed rather than queued.

On resume:

- execute current non-one-shot Event Actions whose `fireOnResume` option is enabled
- never replay missed one-shot Event Actions
- restart repeat intervals from the resume time without catch-up bursts

The initial pause remains active until manually cleared. Planned operational extensions include pause until the next Event, pause for a duration or until a date/time, and a later next-day convenience policy.

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
- compiled per-Day-Pattern Event order
- date-resolution caches and rolling occurrence windows
- previous/current/next occurrence indexes and references
- per-Scheduler timer objects, phases, and plan generation tokens
- resolved Day Pattern
- current, previous, and next Events
- timestamps and countdowns
- last-observed timestamps and active occurrence keys
- active repeat deadlines
- poll/rebuild performance measurements
- validation and callback errors

Automatic execution is additionally protected by a persistent plugin-wide safety toggle that defaults off. A Scheduler must be enabled, unpaused, and covered by that master toggle before callbacks can execute.

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
