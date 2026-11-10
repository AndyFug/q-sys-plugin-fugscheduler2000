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

New Event Action rows use the first registered Action, copy its validated execution defaults, and are always created disabled so the operator can review them before enabling execution. The copied option values then belong to the Event Action and do not change when the Action Registry is reloaded. Changing the attached Action later replaces only the stable Action ID; it preserves the row's current execution options and order. When no defaults are supplied, new rows are disabled, stateful, do not restore automatically, and do not repeat.

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

### Scheduler Definition

A **Scheduler Definition** is a reusable library object. It owns:

- stable identity and operator-facing label
- Default Week Pattern
- Day Patterns
- Week Patterns
- Overrides

A definition is inert: it has no enabled, paused, transport, cursor, or execution state until assigned to a Scheduler Slot. Newly created and duplicated definitions remain unassigned and use opaque UUID-style stable IDs.

### Scheduler Slot

A **Scheduler Slot** is one fixed numbered runnable endpoint. The design-time `Scheduler Slot Count` property creates 1-32 stable slots; the default is eight. A slot owns:

- its fixed slot number
- zero or one assigned Scheduler Definition ID
- enabled and paused operational state
- runtime resolution, cursor, timer, and execution state

One Scheduler Definition may be assigned to at most one slot. Unassigned slots do not resolve or execute. Slot deletion/compaction does not exist: unassigning Slot 2 leaves Slot 2 empty and does not change any other slot's remote-control identity.

## Model hierarchy

```text
Scheduler Slot
└── Assigned Scheduler Definition
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

Compiled Event order, date caches, occurrence windows/indexes, timer objects, generation tokens, callback functions, repeat deadlines, performance counters, and lifecycle state are runtime-only and never enter `ScheduleData`. The bounded one-shot receipt ledger is persistent but remains in its own control rather than becoming editable schedule configuration.

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

Examples include playing an announcement or sending a pulse. A one-shot Event Action normally executes when the Scheduler observes its scheduled edge. One-shot assignments cannot use startup firing, resume firing, or repeat intervals.

The global **One-shot late tolerance** preference optionally allows only the latest resolved Event's one-shot Actions to recover after startup, enable, or a detected forward clock discontinuity. The tolerance is expressed in seconds, defaults to `0`, and is limited to `14400` seconds (four hours). `0` disables late recovery. An occurrence is eligible only when its lateness is within the tolerance; earlier skipped Events are never replayed in a burst.

Before invoking an eligible one-shot callback, the runtime persistently records a receipt for that Scheduler Definition, dated ordered occurrence, and Event Action assignment. Receipts are retained for four hours, matching the maximum tolerance, and provide at-most-once execution across runtime/Core reloads and repeated edge crossings within that window after backward clock movement. A receipt is consumed even when the registered callback is unavailable or fails, because automatically retrying a potentially physical operation is less safe than reporting the failure.

## Pause behavior

While paused, the Scheduler continues resolving dates, Day Patterns, Events, and status, but it does not execute scheduled callbacks. Event edges crossed during the pause are missed rather than queued.

Each Scheduler Slot stores one configured pause mode:

- **Manual** — remain paused until the Pause control is cleared.
- **Next Event** — resume immediately before the resolved target Event so that Event executes normally, including eligible one-shot Actions.
- **Duration** — resume after a configured whole number of minutes.
- **Until Time** — resume at a configured Core-local `YYYY-MM-DD HH:MM` timestamp.
- **Through Day** — ignore the remaining Events on the request date and resume at the first Event on or after the following calendar date.

The Slot persists the configured mode and an active `pauseIntent` containing its request timestamp plus the applicable absolute expiry, calendar boundary, or dated Event target. This preserves the operator's intent across plugin, design, or Core restarts. Event-targeted intents are re-resolved when schedule edits change the affected Scheduler; target metadata updates without searching the schedule during every poll.

On a manual or time-based resume:

- execute current non-one-shot Event Actions whose `fireOnResume` option is enabled
- never replay missed one-shot Event Actions
- restart repeat intervals from the resume time without catch-up bursts

When Next Event or Through Day reaches its target, the engine clears the pause before processing that occurrence. The target Event therefore executes as a normal scheduled edge. If an automatic target passed while the Core or execution engine was unavailable, the pause expires without replaying historical one-shots; eligible current state may restore according to resume policy.

Changing the configured mode, duration, or until-time while paused immediately creates a new intent from the edit time. The ordinary Slot Pause toggle always activates whichever mode is currently configured.

## Advance to Next Event

An assigned, enabled Scheduler Slot may be advanced manually while the plugin-wide Master Enable is on. Advance to Next Event:

1. clears any active pause and pause intent
2. executes the resolved Next occurrence once with reason `manual advance`
3. makes that occurrence Current immediately and starts its eligible repeats from the advance time
4. persists the consumed occurrence identity on the Slot so a runtime restart retains the advanced state
5. suppresses that occurrence's later scheduled edge
6. clears the persisted marker after the original scheduled timestamp passes

The command is rejected when the Slot is unassigned or disabled, Master Enable is off, the runtime plan is unavailable, or no Next occurrence can be resolved. Both stateful and one-shot Event Actions execute during the manual transition; callback isolation and normal Action ordering still apply.

## Named configuration backups

The Admin backup catalogue stores named snapshots of the complete persisted `ScheduleData` root, including Scheduler Definitions, Scheduler Slot assignment and operational configuration, pause intents, and any active manual-advance marker. It deliberately excludes callback functions, Action Registry state, editor selections, diagnostics, and presentation/logging preferences.

The implementation keeps the complete catalogue in one persistent hidden Text control and attempts to mirror the same schema-versioned JSON document to `media/FugScheduler2000/configurations.json` on a physical Core. It creates the `media/FugScheduler2000` directory when required using the documented Q-SYS `dir` API. Q-SYS file writes are unavailable in Designer emulation, so the persistent control remains authoritative. Loading and deleting backups require explicit confirmation. Loading is rejected while Master Enable is on, validates the complete candidate, and assigns a new local configuration revision.

## Persisted versus runtime data

Persisted configuration is a versioned root containing an ordered `schedulers` Scheduler Definition library plus a fixed ordered `schedulerSlots` array. Definition array order is used for library display; each Definition's stable ID is its identity, while each Slot's number is its stable remote-control identity.

Persisted configuration includes:

- Scheduler Definition settings
- Scheduler Slot assignments, enabled state, configured pause mode/options, active pause intent, and any future manually advanced occurrence marker
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
- compiled pause-target comparison keys and deferred operational refresh state
- active repeat deadlines
- poll/rebuild performance measurements
- validation and callback errors

Automatic execution is additionally protected by the plugin-wide Master Enable safety toggle. New plugin instances default it off, while its saved control state is retained across Core and runtime restarts so the scheduler resumes the operator's previous intent. A Scheduler Slot must be assigned, enabled, unpaused, and covered by that master toggle before callbacks can execute.

## Clock discontinuities

A forward movement greater than the ordinary delayed-poll threshold repositions the occurrence cursor directly rather than iterating every historical Event. When the resolved Current occurrence changes, its enabled stateful Actions reconcile immediately and repeat deadlines restart from the new time without catch-up bursts. Only the latest Current Event's one-shots may recover, subject to the global tolerance and persistent receipt ledger.

A backward movement also repositions Previous/Current/Next. If Current changes, its stateful Actions reconcile immediately. The jump itself never executes one-shots. If wall time later crosses a previously observed edge again, persistent receipts suppress one-shot assignments that already executed.

These rules also cover daylight-saving changes. Spring-forward one-shots require a tolerance large enough to include their actual lateness; autumn fallback does not duplicate an already receipted one-shot occurrence.

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
