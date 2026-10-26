# FugScheduler 2000 Stage and Commit Model

Status: **Deferred design proposal**. Do not implement this model until the basic editor, resolver, persistence, and execution behavior is sufficiently complete and the user explicitly confirms that the configuration-layer refactor should begin.

The current immediate-commit transaction architecture remains in use. As an interim safety measure, newly created Schedulers and Overrides are disabled by default so they can be configured before being activated.

## Decision summary

The proposed future workflow uses **Stage** and **Commit**, not Draft and Publish:

- Every valid structural editor change is saved immediately into a persistent **staged configuration**.
- Staged structural changes do not affect the **running configuration**.
- **Commit Changes** validates and atomically replaces the complete running structural configuration.
- **Discard Staged Changes** restores the staged configuration from the running configuration.
- Scheduler Enabled, Scheduler Paused, and Override Enabled are immediate **live operational controls**, not staged structural fields.
- Live operational controls are available only for entities whose stable IDs exist in the running configuration.
- New and duplicated Schedulers and Overrides start disabled when they first become live.
- Staged edits do not increment the running configuration revision. A successful commit increments it exactly once.

## Motivation

The current visual editors commit each valid field change directly to the active configuration:

1. copy the active configuration
2. apply one mutation
3. validate the complete candidate
4. increment the configuration revision
5. serialize it to `ScheduleData`
6. install it as the active runtime model
7. resolve all Schedulers again

This is atomic for each field and safely rejects invalid edits, but valid edits become active one field at a time. That is acceptable while automatic scheduled callback execution is disabled and new entities default to disabled, but it may be unsafe or surprising once the scheduler controls connected systems.

The future Stage and Commit model will let an operator complete and review a coherent set of structural edits before activating it as one transaction.

## Terminology

### Running configuration

The complete validated structural configuration currently used by live resolution and future scheduled execution.

### Staged configuration

A persistent editable copy of the structural configuration. Configuration pages edit this copy immediately, but it does not affect live resolution until committed.

There is no separate **Stage** button. A successful editor mutation is automatically staged and persisted.

### Commit

The explicit operation that validates the complete staged configuration and atomically replaces the running structural configuration.

### Live operational state

Immediate runtime controls keyed by stable entity ID. Initial live controls are:

- Scheduler Enabled
- Scheduler Paused
- Override Enabled

Live operational changes do not require a structural commit and do not increment the structural configuration revision.

## Proposed state layers

The future implementation should maintain three distinct persistent state layers.

### Running structural configuration

Provisional control:

- `ScheduleData`

This remains the schema-versioned configuration and existing integration boundary. It contains the committed Scheduler hierarchy, patterns, Events, Event Actions, Override definitions, labels, stable IDs, dates, references, and ordering.

### Staged structural configuration

Provisional control:

- `StagedScheduleData`

This is the persistent working copy used by structural editors. It must use the same structural schema and validation rules as the running configuration.

### Live operational state

Provisional control:

- `LiveOperationalState`

Conceptually:

```text
LiveOperationalState
├── schedulers
│   └── scheduler-id
│       ├── enabled
│       └── paused
└── overrides
    └── override-id
        └── enabled
```

The exact serialized format and control name remain implementation decisions. Operational state must be persistent if live enable/pause choices are expected to survive a design restart.

The current schema stores Scheduler Enabled, Scheduler Paused, and Override Enabled inside `ScheduleData`. Moving these fields into a live-state overlay will require an explicit migration and compatibility plan. This proposal must not be partially introduced into the current schema.

## Structural versus operational fields

Structural fields are staged and committed together. They include:

- Scheduler identity and label
- Scheduler ordering
- Default Week Pattern selection
- Day Patterns
- Events and Event Actions
- Week Patterns and weekday assignments
- Override identity, label, type, dates, selected pattern, and priority

Operational fields apply immediately to already-running entities:

- Scheduler Enabled
- Scheduler Paused
- Override Enabled

This separation allows external systems and UCIs to pause, enable, disable, or select an already-configured operating mode without rewriting the structural schedule.

## Editing workflow

1. A valid visual structural edit updates `StagedScheduleData`.
2. The running configuration, live resolver, and future execution engine remain unchanged.
3. The UI reports **Changes staged for commit**.
4. The operator may move between configuration pages without losing staged changes.
5. **Commit Changes…** validates the complete staged configuration and presents an activation summary.
6. **Confirm Commit** atomically replaces the running structural configuration.
7. The running revision increments once.
8. The staged configuration is synchronized to the newly committed running configuration.
9. **Discard Staged Changes…** restores the staged configuration from the running configuration after confirmation.

Suggested UI states:

```text
FugScheduler 2000     RUNNING r42     ● Changes staged for commit
                                       [Discard Staged Changes] [Commit Changes…]
```

```text
FugScheduler 2000     RUNNING r43     ✓ No staged changes
```

Because Q-SYS plugin UI does not provide ordinary modal dialogs, commit and discard can use an armed confirmation area:

```text
Committing will activate structural changes across 4 Schedulers.
[Confirm Commit] [Cancel]
```

Configuration pages should identify their context as **Editing Staged Configuration**. Overview, runtime status, and operational controls should identify their context as **Running Configuration**.

## Scheduler selection contexts

Running and staged Scheduler collections can differ when Schedulers are added or deleted in staged changes. A single shared selector would therefore be ambiguous.

Recommended separation:

- a **Running Scheduler selector** for Overview, runtime status, and operational controls
- a **Staged Scheduler selector** for Schedules, Day Patterns, Week Patterns, Overrides, and other configuration editors

A Scheduler that exists only in staged configuration must not appear as running or in running integration status before commit.

## Live-control availability in editors

Stable-ID membership determines whether a staged entity has live operational controls:

- If the selected staged Scheduler ID also exists in running configuration, Scheduler Enabled and Paused are active live controls.
- If the selected staged Override ID also exists in running configuration, Override Enabled is an active live control.
- If an entity exists only in staged configuration, its live controls are frozen and show the future default state, normally Off.
- Frozen controls should explain **Available after commit** rather than appearing broken.

This does not require comparing the entire staged and running documents. It is a direct lookup of the selected stable ID in the running model.

An existing running entity may also have staged structural edits. Its live control continues to operate the currently running definition until commit. The editor should make that distinction clear. For example, enabling an Override before committing its staged date changes enables the old running date definition, not the staged one.

A staged deletion removes the entity from staged editors, but the entity remains live until commit. Running Overview or operational interfaces may continue to expose it until the deletion is committed.

## Operational-state reconciliation on commit

A successful commit must reconcile live operational state by stable ID:

- Entities present before and after commit retain their current live operational state.
- A new Scheduler receives `enabled = false` and a defined initial paused state, provisionally `paused = false`.
- A new Override receives `enabled = false`.
- A duplicated Scheduler or Override has a new stable ID and therefore starts disabled.
- Operational entries for structurally deleted entities are removed after a successful commit.
- A failed commit leaves all running structure and live operational state unchanged.
- Discarding staged structural changes does not alter live operational state.

Preserving live state for an existing entity means that committing structural changes to an enabled Override can immediately change live resolution. The commit review should warn when staged structural changes affect currently enabled Schedulers or Overrides, especially when they alter today's resolved Day Pattern or Event.

The system should not silently disable existing entities on every commit unless later testing identifies a clear safety requirement.

## Revision semantics

Only the running structural configuration has a public configuration revision.

- Staged field edits do not increment or reserve a running revision.
- A successful commit sets the new running revision to the previous running revision plus one.
- A failed commit does not increment the revision.
- Discarding staged changes does not increment the revision.
- Live Scheduler or Override state changes do not increment the structural revision.
- The same next revision number may be used after any number of discarded staged edits.

A runtime-only staged-generation counter may be useful for refreshing UI or caches, but it is not part of the persisted configuration contract. A persistent staged revision should be added only if a concrete synchronization or concurrency requirement is identified.

## Detecting staged changes

Conceptually, the staged configuration is simply an editable copy of the running structural configuration. The plugin still needs a reliable way to reconstruct whether changes are staged after runtime or Designer restart.

Raw JSON string comparison is insufficient because equivalent JSON may differ in whitespace or object-key order. Dirty/clean state should therefore compare normalized structural models or their canonical serialization.

The comparison must ignore data that is not part of structural equality, including:

- running revision
- Scheduler Enabled and Paused live state
- Override Enabled live state
- runtime `_...` indexes
- editor selections
- resolver state
- callback functions and Action Registry state

Canonical structural equality answers only whether any structural changes are staged. Stable-ID membership separately determines whether a selected staged entity has active live controls.

## External writes and conflict handling

An external write means any operation that replaces running `ScheduleData` without using the staged editor and commit workflow. Possible examples include:

- QRC writing `ScheduleData`
- another Lua component writing an exposed control
- a commissioning or backup utility restoring JSON
- a future compatibility path for legacy integrations

If direct external writes remain supported, use this policy:

- When no staged changes exist, accept the new running configuration and synchronize the staged configuration to it.
- When staged changes exist, preserve them, update the running configuration only if the external-write contract permits it, and report a conflict.
- Never silently overwrite staged work.
- Never attempt an automatic structural merge.
- Require the operator to explicitly discard/reload staged changes before editing can continue normally.

A cleaner future API may make `ScheduleData` an output/inspection boundary and route imports explicitly into staged configuration. The compatibility impact must be evaluated before making that change.

## Commit and execution semantics

Before automatic Event execution is enabled, define what commit means when it changes the current resolved Event or Day Pattern.

Questions still requiring a later decision include:

- Should commit immediately execute current state-restoring Event Actions?
- Should one-shot Actions never run merely because configuration was committed after their edge?
- Should commit while paused update resolution but defer callbacks?
- Which warnings are required when commit changes today's active Override, Day Pattern, or current Event?
- Is scheduled commit at a future date/time required later?

The first Stage and Commit implementation may update live resolution only while automatic execution remains disabled. Callback activation semantics must be documented and tested before scheduled execution is enabled.

## Import, export, and reset integration

The Stage and Commit model aligns with the import/export/reset roadmap:

- **Import All Configuration** loads and validates into staged configuration, then requires commit.
- **Import Scheduler** adds to staged configuration without changing running Schedulers.
- **Reset All Configuration** changes staged configuration to a minimal valid root, then requires commit.
- **Reset Selected Scheduler** changes only the selected staged Scheduler, then requires commit.
- Export should distinguish **Export Running Configuration** from **Export Staged Configuration** when they differ.

Destructive staged replacement and discard operations still require explicit confirmation.

## Migration requirements

Existing designs currently have only `ScheduleData`, and operational fields are embedded in that structure. A future implementation must define a one-time migration that:

1. validates the existing `ScheduleData`
2. installs it as running structural configuration
3. initializes `StagedScheduleData` from the same structure without reporting staged changes
4. initializes live Scheduler and Override state from the existing embedded enabled/paused values
5. preserves stable IDs and current behavior
6. leaves the previous valid model active if migration fails

The migration must also define whether compatibility exports continue to include effective operational state or expose it as a separate status document.

## Proposed controls

Names are provisional:

- `StagedScheduleData` — persistent hidden Text control
- `LiveOperationalState` — persistent hidden Text control or equivalent supported storage
- `ConfigurationState` — No Staged Changes / Changes Staged for Commit / Conflict / Validation Error
- `CommitChanges` — begins commit confirmation
- `ConfirmCommitChanges` — atomically activates validated staged structure
- `CancelCommitChanges` — cancels an armed commit
- `DiscardStagedChanges` — begins discard confirmation
- `ConfirmDiscardStagedChanges` — restores staged structure from running structure

A commit review may report Scheduler, Day Pattern, Week Pattern, Event, Event Action, and Override counts plus validation and activation warnings. A detailed field-level diff can be deferred.

## Testing requirements

Add QRC acceptance coverage for:

1. Valid structural editor changes update staged JSON but not running JSON, running revision, resolver output, or execution state.
2. Staged changes survive runtime and Designer reloads.
3. Dirty/clean state tracks canonical staged-versus-running structural equality.
4. Commit validates and activates the complete staged configuration atomically.
5. Running revision increments once per successful commit rather than once per staged field edit.
6. Failed commit preserves running JSON, running revision, resolver output, live operational state, and staged data.
7. Discard restores staged structure from the running model.
8. Forced Commit/Discard confirmation presses are harmless when not armed.
9. Staged-only Scheduler additions do not appear in running status before commit.
10. Live controls are frozen for staged-only Schedulers and Overrides.
11. Newly committed and duplicated Schedulers and Overrides start disabled.
12. Immediate Scheduler Enabled, Scheduler Paused, and Override Enabled changes do not require commit.
13. Existing entities retain live operational state across commit and discard.
14. Staged structural edits to an existing Override do not affect its running definition before commit.
15. Import and reset operations alter only staged structure until commit.
16. Runtime-only indexes and selections remain absent from both serialized structural controls.
17. External running writes with a clean staged copy synchronize both models.
18. External running writes with staged changes preserve the staged copy and report the chosen conflict state.
19. Tests restore original running data, staged data, and operational state byte-for-byte in guaranteed cleanup.

## Remaining design decisions

- Final UI placement and exact wording for the common configuration-state bar.
- Exact live operational-state persistence format.
- Initial paused state for a newly committed Scheduler.
- Compatibility representation of operational fields in exports and integrations.
- Whether direct external writes to `ScheduleData` remain supported.
- Whether commit offers only immediate activation or later supports scheduled activation.
- Whether the first commit review shows counts/warnings or a field-level diff.
- Exact migration behavior for schema-v1 designs containing embedded operational fields.
- Commit-time callback behavior once automatic Event execution is implemented.

## Current interim behavior

This proposal is deliberately deferred. Until it is implemented:

- visual edits continue to use the current immediate atomic transaction path
- valid changes continue to update `ScheduleData` and resolver output immediately
- newly created Schedulers are disabled by default
- newly created and duplicated Overrides are disabled by default
- users can configure these disabled entities before explicitly enabling them
- automatic scheduled callback execution remains disabled

## Implementation boundary

Do not partially mix Stage and Commit into the current immediate-commit architecture. When implementation begins, treat it as a dedicated configuration-layer refactor with explicit schema migration, live-state separation, compatibility decisions, and QRC validation phases.
