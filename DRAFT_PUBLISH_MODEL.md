# FugScheduler 2000 Draft and Publish Model

Status: **Deferred design proposal**. Do not implement until the intervening requested features are complete and the user confirms this work should begin.

## Motivation

The current visual editors commit each valid field change immediately:

1. copy the active configuration
2. apply one mutation
3. validate the complete candidate
4. increment the configuration revision
5. serialize it to `ScheduleData`
6. install it as the active runtime model
7. resolve all Schedulers again

This is atomic for each field and safely rejects invalid edits, but valid edits become active one field at a time. For example, a newly created enabled Override whose date includes today can immediately change resolver output. Automatic scheduled callback execution is currently disabled, so this does not yet operate connected systems, but the behavior would be unsafe or surprising once execution is enabled.

## Proposed model

Separate editable configuration from the configuration used by the live resolver and future execution engine:

- **Published configuration** — the complete validated configuration currently used by live resolution and execution.
- **Working configuration** — a persistent draft edited by the configuration pages.

Editors save valid changes to the working configuration immediately, but those changes do not affect live resolution until the operator explicitly publishes the complete draft.

Conceptual persistence controls:

- `ScheduleData` — published/live schema-v1 configuration and existing integration boundary.
- `DraftScheduleData` — persistent working configuration used by visual editors.

The exact control names and compatibility strategy must be confirmed before implementation.

## Proposed UI

Use **Publish** rather than **Save**. Draft edits are already persistently saved; “Save” could incorrectly imply that the schedule is live.

A compact common configuration bar could appear on editor pages:

```text
FugScheduler 2000     LIVE r42     ● Unpublished changes
                                    [Discard Draft] [Publish Changes…]
```

When the draft matches the published configuration:

```text
FugScheduler 2000     LIVE r43     ✓ Published
```

Editor pages should also identify their context as **Editing Draft**. Overview and runtime status should identify their context as **Live Schedule**.

Because Q-SYS plugin UI does not provide ordinary modal dialogs, destructive or activating operations can use an armed confirmation area:

```text
Publishing will activate changes across 4 Schedulers.
[Confirm Publish] [Cancel]
```

## Editing workflow

1. A valid visual edit updates persistent draft data.
2. The published model, live resolver, and future execution engine remain unchanged.
3. A global amber **Unpublished changes** indicator appears.
4. The operator may move between editor pages without losing draft changes.
5. **Publish Changes…** validates the entire draft and presents an activation summary.
6. **Confirm Publish** atomically replaces the published model.
7. **Discard Draft** restores the working configuration from the published configuration after confirmation.

Publication should increment the live configuration revision once. Individual draft edits should not increment the published revision; they may use a separate draft generation counter if useful.

## Scheduler selection contexts

Published and draft Scheduler collections can differ when Schedulers are added or deleted in the draft. A single shared selector would therefore be ambiguous.

Recommended separation:

- a **Live Scheduler selector** for Overview, runtime status, and immediate operational controls
- a **Draft Scheduler selector** for Schedules, Day Patterns, Week Patterns, Overrides, and other configuration editors

A Scheduler that exists only in the draft must not appear as live or expose live operational controls until publication.

## Immediate operational controls

Current discussion preference: **Scheduler Pause and Scheduler Enable remain immediate operational controls** for already-published Schedulers.

These controls should be treated separately from structural draft configuration, likely as a live operational-state overlay keyed by stable Scheduler ID. Publishing or discarding structural changes must not unexpectedly reset an operator's current Pause/Enable state.

Important distinctions:

- Scheduler Pause: immediate live operation.
- Scheduler Enable: immediate live operation.
- Override enabled state: structural scheduling configuration and therefore staged until publication.
- A draft-only new Scheduler has no live Pause/Enable state until it is published.

The persistence and restart behavior of the operational-state overlay must be designed explicitly.

## New entity defaults

A draft prevents new entities from affecting the live schedule before publication. Even with this protection, new Overrides should probably default to disabled as an additional safeguard against accidental publication.

Before implementation, confirm defaults for:

- new Scheduler enabled state
- new Override enabled state
- publication behavior when a draft introduces a currently applicable Override

## Publication and execution semantics

Before automatic Event execution is enabled, define what publication means when it changes the current resolved Event or Day Pattern.

Questions include:

- Should publishing immediately execute current state-restoring Event Actions?
- Should one-shot Actions never run merely because a configuration was published after their edge?
- Should publication while paused update resolution but defer callbacks?
- Should the operator be warned when publication changes today's active Override or current Event?
- Is scheduled publication at a future date/time required later?

The first draft/publish implementation may update live resolution only while automatic execution remains disabled, but the eventual activation policy must be documented and tested before callback execution is enabled.

## Import, export, and reset integration

The draft model aligns with the import/export/reset roadmap:

- **Import All Configuration** loads and validates into the draft, then requires publication.
- **Import Scheduler** adds to the draft without changing live Schedulers.
- **Reset All Configuration** changes the draft to a minimal valid root, then requires publication.
- **Reset Selected Scheduler** changes only the selected draft Scheduler, then requires publication.
- Export should distinguish **Export Published** from **Export Draft** when they differ.

Destructive draft replacement and draft discard operations still require explicit confirmation.

## Validation and conflict handling

- Every draft edit must remain schema-valid through the existing atomic transaction layer.
- Publication must validate the complete draft again before changing live data.
- Failed draft edits must preserve the previous valid draft.
- Failed publication must preserve both the previous published model and the current draft.
- Runtime `_...` indexes, selection maps, callbacks, and resolver state must not enter either serialized configuration.
- External writes to `ScheduleData` while a dirty draft exists need an explicit conflict policy; they must not silently overwrite draft work.
- Runtime-only selections should remain separate for live and draft contexts where necessary.

## Proposed initial controls

Names are provisional:

- `DraftScheduleData` — persistent hidden Text control.
- `ConfigurationState` — Published / Unpublished Changes / Validation Error status.
- `PublishChanges` — begins publication confirmation.
- `ConfirmPublishChanges` — atomically activates the validated draft.
- `CancelPublishChanges` — cancels an armed publication.
- `DiscardDraft` — begins discard confirmation.
- `ConfirmDiscardDraft` — restores draft from published data.

A review summary may report Scheduler, Day Pattern, Week Pattern, Event, Event Action, and Override counts plus validation warnings. A detailed semantic diff can be deferred.

## Testing requirements

Add QRC acceptance coverage for:

1. Valid editor changes update draft JSON but not published JSON, live revision, resolver output, or execution state.
2. Draft changes survive runtime and Designer reloads.
3. Dirty/clean indicators track canonical draft-versus-published equality.
4. Publish validates and activates the complete draft atomically.
5. Published revision increments once per publication rather than once per draft field edit.
6. Failed publication preserves published JSON, live revision, resolver output, operational state, and draft data.
7. Discard restores the draft from the published model.
8. Forced Publish/Discard confirmation presses are harmless when not armed.
9. Draft-only Scheduler additions do not appear in live status before publication.
10. Immediate Pause/Enable changes affect published Schedulers without publishing structural draft changes.
11. Publishing and discarding do not unexpectedly reset live Pause/Enable state.
12. Import and reset operations alter only the draft until publication.
13. Runtime-only indexes and selections remain absent from both serialized controls.
14. Tests restore original published data, draft data, and operational state byte-for-byte in guaranteed cleanup.

## Open design decisions

- Final UI placement and wording for the common configuration-state bar.
- Whether draft persistence belongs in one JSON control or another supported Q-SYS persistence mechanism.
- Exact live operational-state persistence model for Scheduler Pause and Enable.
- Whether new Overrides default disabled in the draft.
- How external `ScheduleData` writes interact with a dirty draft.
- Whether publication offers only immediate activation or later supports scheduled activation.
- Whether the first review UI shows only counts/warnings or a field-level diff.
- Migration behavior for existing designs that have only `ScheduleData`.

## Implementation boundary

Do not partially mix this model into the current immediate-commit architecture. When implementation begins, plan it as a dedicated configuration-layer refactor with explicit compatibility and QRC validation phases.
