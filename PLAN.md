# FugScheduler 2000 Plan

## Goal

Build a Q-SYS plugin that lets designers and operators define, edit, inspect, and run schedules without editing the scheduler engine or hard-coding site schedules in Lua.

The plugin should retain the useful behavior of `references/fugSchedulerTextController.lua` while separating three concerns:

1. **Actions** — named callbacks supplied by trusted site-specific Lua.
2. **Schedule configuration** — Day Patterns, timed Events with ordered Actions, Week Patterns, and dated Overrides edited in the plugin UI.
3. **Runtime engine** — time calculation, transitions, repeats, pause/resume, status, logging, and safe callback invocation.

## Reference behavior to preserve

The reference controller proves the following concepts in a real deployment:

- multiple independent scheduler instances
- named actions with operator-friendly labels
- daily patterns containing ordered timed entries, evolved here into Day Patterns containing Events
- a default pattern for each weekday, evolved here into reusable Week Patterns
- special-date overrides, evolved here into date-range Day Pattern and Week Pattern Overrides
- current, previous, and next timeline calculation across midnight
- scheduler enable/pause behavior
- one-shot actions that only fire at their scheduled edge
- `fireOnStartup` behavior for state-restoring actions
- optional repeated callback execution while an action remains current
- callback isolation with `pcall`
- current resolved Day Pattern and Event, next Event, timestamps, and countdown status
- event/debug logging levels

The plugin may improve these semantics, but changes should be explicit and documented.

## Initial external action model

### Preferred approach

Use an ordinary Text input control rather than Q-SYS's reserved runtime `code` control:

```lua
{Name = "ActionSource", ControlType = "Text", UserPin = true, PinStyle = "Input", Count = 1}
```

A separate Text Controller's built-in `code` output sends its source to this ordinary Text input. The source defines one agreed provider function and does not define schedules. Designer testing confirms that this connection preserves the plugin's bundled runtime while allowing it to evaluate and call the provider.

Proposed authoring shape:

```lua
function GetFugSchedulerActions()
  return {
    {
      id = "site-music-morning",
      label = "Site Music: Morning",
      description = "Recall the morning music snapshot.",
      defaults = {
        oneShot = false,
        fireOnStartup = true,
        fireOnResume = true,
        repeatSeconds = 300
      },
      callback = function()
        Component.New("SiteMusicSnapshots")["load.2"]:Trigger()
      end
    }
  }
end
```

Possible optional metadata:

- `category`
- `oneShotDefault`
- `fireOnStartupDefault`
- `fireOnResumeDefault`
- `repeatSecondsDefault`
- preferred nested `defaults = {...}` equivalents for those fields
- `testCallback`
- `available` or validation callback

### Important validation point

Official SDK documentation describes the reserved `code` control as supplying the complete runtime for a debug plugin, so it is not used as an action extension mechanism. The plugin exposes a separate hidden `code` input for live runtime development; when connected, a `SchedulerRuntimeProvider` Text Controller must provide the complete runtime. The Phase 1 evaluator spike must validate:

- whether `load` or `loadstring` is available in plugin runtime
- whether the evaluated provider can return callback functions
- whether callbacks can access supported Q-SYS globals such as `Component`
- how syntax, provider, validation, and callback errors are reported
- whether changing the ordinary Text source triggers a reliable registry refresh
- practical source length and persistence behavior

The plugin executes only trusted design code, compiles it in a dedicated environment with Q-SYS globals available by fallback, and replaces the active registry only after successful validation.

Validated in Designer and through QRC: a Text Controller `code` output connected to `ActionSource` supplied `GetFugSchedulerActions()`, populated action choices, and callbacks were invoked successfully from the plugin Actions page. Dynamic callbacks can access `Component.New`; syntax errors, provider failures, duplicate IDs, and callback failures are isolated without stopping the plugin; invalid updates preserve the previous registry. `SchedulerRuntimeProvider` also hot-reloads the complete plugin runtime through the reserved `code` input.

### Trust and safety boundary

The external callback source is trusted design code with the same practical privileges as other Q-SYS Lua in the design. Even so, the plugin should:

- expose a narrow registration API
- validate unique action IDs and required fields
- reject malformed registrations without stopping the scheduler
- wrap every callback in `pcall`
- surface registration and callback errors in status/log controls
- avoid storing callback functions in serialized schedule data

## Proposed data model

### Action registry

Runtime-only data supplied by external code:

```lua
Action = {
  id = "stable-id",
  label = "Operator label",
  category = "Music",
  description = "Optional details",
  callback = function() end,
  defaults = {
    oneShot = false,
    fireOnStartup = true,
    fireOnResume = true,
    repeatSeconds = 300
  }
}
```

Schedules persist action IDs, not function values or labels.

### Scheduler configuration

The canonical nomenclature, hierarchy, resolution rules, and worked examples are defined in `SCHEDULER_MODEL.md`.

The persisted root contains an ordered array of independently resolved Schedulers. Array order is used for display while stable Scheduler IDs provide identity and integration lookup:

```lua
ScheduleData = {
  schemaVersion = 1,
  revision = 1,
  schedulers = {
    {
      id = "site-music",
      label = "Site Music",
      enabled = true,
      paused = false,
      timezoneMode = "Core Local",
      defaultWeekPatternId = "normal-week",
      dayPatterns = {},
      weekPatterns = {},
      overrides = {}
    }
  }
}
```

A Day Pattern contains Events. An Event defines a time and an ordered list of Event Actions:

```lua
DayPattern = {
  id = "standard-weekday",
  label = "Standard Weekday",
  events = {
    {
      id = "morning-opening",
      time = "09:40",
      label = "Morning Opening",
      actions = {
        {actionId = "site-unmute", options = {}},
        {actionId = "site-music-morning", options = {}}
      }
    }
  }
}
```

A Week Pattern assigns one Day Pattern to each weekday:

```lua
WeekPattern = {
  id = "normal-week",
  label = "Normal Operating Week",
  days = {
    Mon = "standard-weekday",
    Tue = "standard-weekday",
    Wed = "standard-weekday",
    Thu = "standard-weekday",
    Fri = "standard-weekday",
    Sat = "standard-weekend",
    Sun = "standard-weekend"
  }
}
```

Overrides apply either a Day Pattern or Week Pattern over an inclusive date range:

```lua
Override = {
  id = "christmas-closure",
  label = "Christmas Closure",
  type = "DayPattern",
  startDate = "2026-12-24",
  endDate = "2026-12-26",
  patternId = "closed",
  enabled = true
}
```

Events are sorted by normalized time for execution while retaining stable identity and explicit Event Action order for editing.

## Persistence strategy

Initial preference: store user-editable schedule fields in persistent Q-SYS plugin controls because control values are saved with the design.

Questions to validate:

- practical control-count limits for configured Scheduler, Day Pattern, Event, Event Action, Week Pattern, and Override capacities
- behavior when capacity properties are reduced and later increased
- whether JSON held in one or more Text controls is robust and editable enough
- whether a row-oriented control model is preferable for UI binding and UCIs
- maximum reliable text length for JSON import/export controls

Likely approach:

- fixed capacities selected through plugin properties
- stable counted controls for editable rows
- a compact serialized representation for backup/import/export
- runtime indexes derived from persistent controls

## Proposed UI

Use the vendored FugUi framework and separate operator status from configuration.

### Overview

- aggregate multi-Scheduler health and action-registry status
- selected Scheduler enabled/paused state
- selected Scheduler, resolved Day Pattern, Event, and Event Actions
- previous and next Events
- next-action timestamp and live countdown
- quick pause/resume and manual refresh controls

### Schedulers

- select/add/rename/disable Scheduler
- select the Default Week Pattern
- inspect the currently resolved Day Pattern and the rule that selected it
- manage multiple independent Schedulers in persisted display order

### Day Patterns

- select/add/rename/copy/delete Day Pattern
- edit timed Events
- edit each Event's ordered Event Actions
- configure one-shot, startup fire, and repeat behavior at the appropriate Event Action level
- row ordering and validation feedback

### Week Patterns

- select/add/rename/copy/delete Week Pattern
- assign a Day Pattern to Monday through Sunday
- preview the resulting week

### Overrides

- select Day Pattern Override or Week Pattern Override
- configure name, enabled state, inclusive start/end dates, and selected pattern
- explicit priority ordering and overlap warnings
- upcoming Override list
- later: recurrence, exclusions, and holiday import

### Actions

- read-only list of registered actions
- ID, label, category, description, and availability
- registration errors
- optional guarded test button

### Diagnostics

- current/previous/next resolved Events and timestamps
- scheduler logs
- callback errors
- raw persisted configuration/export
- code-source/registry generation status

Large lists should use banked editor rows with stable backing controls rather than dynamically changing control names.

## Scalable live execution architecture

The accepted Phase 2 execution design uses reference-style stateful Scheduler cursors without rebuilding multi-day timelines during each one-second poll.

Each validated Scheduler owns one runtime-only compiled plan containing:

- the configuration revision and a runtime generation token
- each Day Pattern's Events sorted once by normalized time with persisted array order as the equal-time tie-break
- cached date-to-Day-Pattern resolution and resolved occurrence lists
- a rolling ordered occurrence window with authoritative Previous, Current, and Next indexes/references
- the last observed Core-local wall-clock timestamp, active occurrence identity, repeat deadlines, lifecycle state, and latest callback result
- one retained Q-SYS poll timer, deliberately phase-staggered across the one-second interval
- non-spamming `Timer.Now()` measurements for rebuild, average/maximum poll duration, delayed polls, and configured Event/Action counts

An occurrence is identified by its absolute Core-local timestamp, date, Event ID/reference, Day Pattern ID/reference, and persisted Event sequence. Normal polls advance the cached cursor through `lastObservedTimestamp < occurrence.timestamp <= now`; they do not parse JSON, validate the schema, sort Events, rebuild broad timelines, refresh unrelated editors, or log routine activity.

The rolling resolver extends dates only as the cursor approaches its cached boundary, retains the Previous occurrence for status, and prunes obsolete history. Re-anchoring and arbitrary `TestDateTime` resolution search incrementally with a documented 400-calendar-day safety horizon per direction rather than eagerly expanding a fixed ±31-day timeline. Empty Schedulers are handled without scanning the horizon. `TestDateTime` uses a detached resolver plan and never mutates live execution cursors.

Configuration installation compares Scheduler-scoped persisted models. Unchanged Schedulers retain their plan, cursor, generation, timer, phase, metrics, and runtime status. Added or changed Schedulers receive new generation-tokened plans; replaced/deleted timers are stopped, and obsolete callbacks verify the current generation before doing work. When a changed plan's Current occurrence changes, only eligible stateful Actions reconcile; one-shots remain edge-only and repeats restart from reconciliation time.

Backward wall-clock movement repositions the cursor and clears repeat state without replay. Forward discontinuities or delayed runtime beyond the ordinary-edge threshold re-anchor directly, skip historical one-shots, restore only eligible Current stateful Actions under the existing startup policy, and restart repeats without catch-up bursts. `Timer.Now()` is used only for elapsed performance measurements; `os.time()` remains the Core-local scheduling clock.

## Deferred Stage and Commit model

A persistent staged-versus-running structural configuration model with separate live Scheduler and Override operational controls is proposed in `DRAFT_PUBLISH_MODEL.md`. It is intentionally deferred until the basic editor, resolver, persistence, and execution behavior is sufficiently complete. It must not be partially introduced into the current immediate-commit transaction architecture.

## Import, export, and reset roadmap

Configuration portability and destructive reset workflows should be available at both the complete-plugin and individual-Scheduler scopes.

### Proposed operator actions

Global actions:

- **Export All Configuration** — expose the complete persisted schema root, including every Scheduler, as JSON suitable for backup and transfer.
- **Import All Configuration** — stage, validate, and atomically replace the complete configuration from JSON.
- **Reset All Configuration** — replace the current root with a minimal valid default configuration after explicit confirmation.

Selected-Scheduler actions:

- **Export Selected Scheduler** — expose one Scheduler and all of its nested Day Patterns, Week Patterns, Events, Event Actions, and Overrides in a documented transfer envelope.
- **Import Scheduler** — stage and validate one Scheduler for addition to the existing root without replacing unrelated Schedulers.
- **Reset Selected Scheduler** — clear the selected Scheduler's nested schedule configuration to a minimal valid Day Pattern and Week Pattern while leaving other Schedulers unchanged.

Use **Reset** rather than **Factory Reset** unless the product later defines a stable, meaningful factory schedule. “Clear Configuration” may be used as explanatory text, but the operation must still produce a schema-valid model rather than an invalid empty root.

### Safety and transaction requirements

- Import text must be staged separately from active `ScheduleData`; typing or pasting incomplete JSON must not disturb the current model.
- Validate the complete candidate before changing `ScheduleData`, revision, resolver output, or editor selections.
- Apply imports and resets through the same atomic transaction/install path used by visual editors.
- Keep the previous valid model active after malformed JSON, schema errors, missing references, duplicate IDs, or failed writes.
- Show a summary of the staged import before Apply, including Scheduler and nested entity counts plus validation warnings.
- Require explicit confirmation for global replacement, global reset, selected-Scheduler replacement, and selected-Scheduler reset.
- Encourage or offer an export immediately before destructive replacement/reset operations.
- Never serialize runtime callback functions, `_...` indexes, resolver state, or editor selections.
- Preserve Event Action option fields and disabled Override references during export/import.
- Keep automatic scheduled callback execution disabled during import validation unless engine behavior has been implemented and explicitly tested.

### Identity and conflict policy to define

Initial implementation should make these choices explicit rather than silently guessing:

- whether importing a Scheduler with an existing Scheduler ID is rejected, added with regenerated Scheduler-scoped IDs, or offered as an explicit Replace Selected operation
- whether Reset Selected Scheduler retains its stable Scheduler ID, label, enabled state, and paused state; the recommended default is to retain Scheduler identity and operator settings while replacing nested patterns and Overrides
- whether Import All preserves the imported root revision or creates a new local revision; the recommended default is a new local revision recording the successful transaction
- whether export text preserves the current serialized bytes or emits canonical pretty JSON
- whether the initial interface is clipboard-oriented Text controls or later gains file transfer through an external commissioning tool

### Planned validation

Import/export/reset acceptance tests should cover:

- complete-root export and byte-for-byte backup restoration
- complete-root import round trips with unchanged resolver results
- selected-Scheduler export/import without changing unrelated Schedulers
- stable-ID collision rejection or the chosen explicit collision policy
- malformed JSON and schema-invalid import rejection
- global and selected-Scheduler reset confirmation guards, including forced QRC presses
- reset output being immediately schema-valid and editor-selectable
- runtime reload persistence after import
- absence of runtime-only keys in every export
- original `ScheduleData` restoration in guaranteed cleanup after every QRC test

## Scheduler semantics to define carefully

Before completing the engine, document and test:

- validate that a current one-shot never replays on startup, enable, resume, or clock discontinuity
- validate explicit `fireOnStartup` and `fireOnResume` state-restoration options
- validate repeats beginning at a scheduled edge and restarting from startup/resume activation time without catch-up bursts
- behavior after a clock jump, Core reboot, design restart, or long execution stall
- daylight-saving transitions and timezone assumptions
- duplicate Event times within a Day Pattern
- empty Day Patterns and missing Week Pattern day assignments
- an Override referencing a missing Day Pattern or Week Pattern
- overlapping Overrides and deterministic precedence
- an Event Action referencing an unregistered Action
- ordered execution and failure isolation when one Event contains multiple Actions
- validate immediate stateful reconciliation when schedule edits change the current Event; one-shots remain edge-only and repeats restart from the edit time
- pause/resume behavior for repeat timers and missed one-shots
- pause expiry modes: manual, next Event, duration/until time, and a defined next-day policy
- advancing immediately to the next scheduled Event, including occurrence consumption and restart persistence
- whether manual action tests affect current scheduler state

### Core-local time and DST validation

Before enabling automatic scheduled callback execution, add explicit emulator/Core-local acceptance tests for:

- Override ranges and date-format convenience actions crossing spring and autumn daylight-saving boundaries while retaining the expected number of calendar days
- calendar-day shifting through month, year, leap-day, and DST boundaries using Q-SYS Lua `os.date`, `os.time`, and `os.difftime` behavior
- nonexistent local Event times during the spring-forward transition
- repeated local Event times during the autumn fallback transition, including whether an Event edge may execute once or twice
- previous/current/next Event resolution on both sides of each DST transition
- Core clock jumps forwards and backwards, including missed one-shot and state-restoring Action policy
- Designer emulator versus physical Core behavior where their local timezone settings differ

Record the Q-SYS version, configured local timezone, observed platform normalization, and chosen execution policy in validation documentation. Do not replace Q-SYS local-time handling with a custom calendar implementation; use the platform date/time functions and document any platform-specific edge behavior.

## Phases

### Phase 0 — repository and boilerplate

- Create an independent Git repository.
- Add standard `src/` layout and repo-local include compiler.
- Vendor the shared FugUi framework.
- Add project-specific docs and validation checklist.
- Generate a loadable skeleton `.qplug` with the hidden `ActionSource` Text input pin.

### Phase 1 — ActionSource evaluator and persistence spike

- Validate plugin loading, pages, controls, and the `ActionSource` Text pin in Designer.
- Build a minimal external Control Script/Text Controller example.
- Prove evaluation and registration of two named callbacks.
- Show registered actions in a plugin combo/list.
- Validate callback execution and error reporting.
- Compare row-controls versus JSON-backed persistence.

Exit criterion: the plugin can discover trusted external actions reliably and retain a small schedule configuration across design save/reload.

### Phase 2 — multi-Scheduler vertical slice

- Persist and validate an ordered array of independent Schedulers from the outset.
- Implement Day Patterns, Week Patterns, Overrides, and ordered Event Actions for each Scheduler.
- Implement current/previous/next resolution across midnight independently for every Scheduler.
- Publish the aggregate integration contract defined in `STATUS_MODEL.md`.
- Implement ordered Event Action execution, pause/resume, one-shot, startup/resume fire, and repeat behavior behind a disabled-by-default master execution safety control.
- Track Event occurrences explicitly so duplicate-time ordering, missed edges, clock discontinuities, and a later Advance to Next Event command can be handled deterministically.
- Build functional Overview, Scheduler, Day Patterns, Week Patterns, Overrides, Actions, and Diagnostics pages.
- Add manual action testing with a guard/confirmation strategy.

Exit criterion: multiple Schedulers can resolve concurrently and one selected Scheduler can reproduce a representative subset of the reference controller without schedule definitions in Lua.

### Phase 2 follow-up — operational transport controls

- Add Pause Until Next Event, timed/until-time pause, and a documented next-day pause policy.
- Add Advance to Next Event as an explicit runtime transition that executes the next occurrence once, makes it current, and suppresses its later scheduled edge.
- Decide whether pause expiry and advanced occurrence state survive runtime or Core restart, then persist operational state if required.
- Keep Action testing separate from Scheduler transport state.

### Phase 3 — scalable editing

- Support configurable Scheduler, Day Pattern, Event, Event Action, Week Pattern, and Override soft capacities.
- Add banked table editors and drill-down selection controls.
- Add Scheduler-specific status and enable controls.
- Add validation for references, duplicate IDs, overlapping date ranges, invalid times, and capacity overflow.

Exit criterion: the reference controller's Site Music, Site Mute, Ice Rink, Big Wheel, and De-Icer examples can be represented and edited concurrently.

### Phase 4 — import/export, reset, and operational polish

- Add staged, validated global JSON export/import with explicit Apply and confirmation behavior.
- Add selected-Scheduler export/import with a documented transfer envelope and explicit stable-ID conflict handling.
- Add guarded Reset All Configuration and Reset Selected Scheduler operations that always produce schema-valid models.
- Add schema versioning for future transfer formats without changing the current persisted schema until a migration is actually required.
- Add copy/duplicate workflows for Day Patterns, Week Patterns, Overrides, and Schedulers.
- Add QRC round-trip, rejection, reset-guard, isolation, and byte-for-byte restoration tests.
- Improve logging, commissioning, and failure status.
- Validate official Plugin Compiler output and Designer performance.

### Future — built-in actions

Add optional built-in action types without removing callback extensibility, for example:

- named component control set/trigger
- snapshot recall
- control ramp/fade
- delayed or grouped actions
- HTTP request
- plugin control output pulse/state

Built-in Actions should use the same registry/ID model so Event Actions do not care whether an Action is external or native.

## Phase 1 acceptance criteria

- The generated plugin loads in Q-SYS Designer without design-time errors.
- The `ActionSource` Text pin can be exposed and connected to a Control Script/Text Controller.
- Trusted source can provide at least two uniquely identified callbacks through `GetFugSchedulerActions()`.
- Registered action labels populate a plugin UI selection control.
- A callback can be invoked through a guarded plugin test action.
- Callback errors are caught and displayed without stopping the plugin.
- A minimal persisted Day Pattern with Events and Event Actions survives save/reload and resolves current/next Events correctly.
- The generated `.qplug` contains no unresolved include directives.

## Open questions

- What practical source-size and persistence limits apply to the `ActionSource` Text control?
- Should future Action default changes ever offer an explicit bulk-update workflow for existing Event Actions? Current behavior copies defaults only when an assignment is attached.
- Is Core-local time sufficient, or is an explicit timezone/DST policy required?
- What capacity defaults balance Day Pattern, Event, Event Action, Week Pattern, and Override usability against control count?
- What edit permissions/lockout controls are needed for operator-facing UCIs?
- Which features belong in the plugin UI versus UCI-oriented proxy controls?
