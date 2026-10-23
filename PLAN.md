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
- `repeatSecondsDefault`
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

## Scheduler semantics to define carefully

Before completing the engine, document and test:

- startup behavior when the current action is one-shot
- whether non-one-shot current actions fire immediately on startup by default
- whether an action repeats from scheduled start or plugin startup
- behavior after a clock jump, Core reboot, design restart, or long execution stall
- daylight-saving transitions and timezone assumptions
- duplicate Event times within a Day Pattern
- empty Day Patterns and missing Week Pattern day assignments
- an Override referencing a missing Day Pattern or Week Pattern
- overlapping Overrides and deterministic precedence
- an Event Action referencing an unregistered Action
- ordered execution and failure isolation when one Event contains multiple Actions
- changing schedule data while an action is active
- pause/resume behavior for repeat timers and missed one-shots
- whether manual action tests affect current scheduler state

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
- Implement pause/resume, one-shot, startup fire, and repeat behavior.
- Build functional Overview, Scheduler, Day Patterns, Week Patterns, Overrides, Actions, and Diagnostics pages.
- Add manual action testing with a guard/confirmation strategy.

Exit criterion: multiple Schedulers can resolve concurrently and one selected Scheduler can reproduce a representative subset of the reference controller without schedule definitions in Lua.

### Phase 3 — scalable editing

- Support configurable Scheduler, Day Pattern, Event, Event Action, Week Pattern, and Override soft capacities.
- Add banked table editors and drill-down selection controls.
- Add Scheduler-specific status and enable controls.
- Add validation for references, duplicate IDs, overlapping date ranges, invalid times, and capacity overflow.

Exit criterion: the reference controller's Site Music, Site Mute, Ice Rink, Big Wheel, and De-Icer examples can be represented and edited concurrently.

### Phase 4 — import/export and operational polish

- Add JSON import/export and schema versioning.
- Add copy/duplicate workflows for Day Patterns, Week Patterns, Overrides, and Schedulers.
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
- Should repeat/startup/one-shot options live primarily on Action definitions, Event Actions, or both through inherited defaults and overrides?
- Is Core-local time sufficient, or is an explicit timezone/DST policy required?
- What capacity defaults balance Day Pattern, Event, Event Action, Week Pattern, and Override usability against control count?
- What edit permissions/lockout controls are needed for operator-facing UCIs?
- Which features belong in the plugin UI versus UCI-oriented proxy controls?
