-- Q-SYS calls this to define persistent controls, UI bindings, and control pins.
function GetControls(_props)
  local ctrls = {}

  -- Allow a Control Script to supply the complete runtime during live debugging.
  -- When connected, Q-SYS uses this reserved control instead of the bundled runtime.
  table.insert(ctrls, {
    Name = "code",
    ControlType = "Text",
    UserPin = true,
    PinStyle = "Input",
    Count = 1
  })

  -- Receive trusted Lua source that defines the agreed action-provider function.
  -- Unlike `code`, this is an ordinary Text input interpreted by the active runtime.
  table.insert(ctrls, {
    Name = "ActionSource",
    ControlType = "Text",
    UserPin = true,
    PinStyle = "Input",
    Count = 1
  })

  -- Select which Scheduler the banked human-readable status controls and editor display.
  table.insert(ctrls, {Name = "SchedulerSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "SchedulerEnabled", ControlType = "Button", ButtonType = "Toggle", UserPin = true, PinStyle = "Output", Count = 1})

  -- Edit the selected Scheduler through the runtime's validated transaction layer.
  table.insert(ctrls, {Name = "SchedulerLabel", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "SchedulerEditorEnabled", ControlType = "Button", ButtonType = "Toggle", Count = 1})
  table.insert(ctrls, {Name = "SchedulerPaused", ControlType = "Button", ButtonType = "Toggle", Count = 1})
  table.insert(ctrls, {Name = "SchedulerDefaultWeekPattern", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "AddScheduler", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DuplicateScheduler", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DeleteScheduler", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "SchedulerEditorStatus", ControlType = "Text", Count = 1})

  -- Build Day Patterns by selecting nested Events and attaching registered Actions.
  table.insert(ctrls, {Name = "DayPatternSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "DayPatternLabel", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "DayPatternSummary", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "DayPatternReferences", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "AddDayPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DuplicateDayPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DeleteDayPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "EventSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "EventLabel", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "EventTime", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "EventSummary", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "AddEvent", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DuplicateEvent", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DeleteEvent", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "EventActionSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "EventActionPicker", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "AddEventAction", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DeleteEventAction", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "MoveEventActionUp", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "MoveEventActionDown", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DayPatternEditorStatus", ControlType = "Text", Count = 1})

  -- Edit Week Patterns and their seven Day Pattern assignments in the selected Scheduler.
  table.insert(ctrls, {Name = "WeekPatternSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "WeekPatternLabel", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "WeekPatternReferences", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "AddWeekPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DuplicateWeekPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "DeleteWeekPattern", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  for _, weekday in ipairs(FugSchedulerWeekdays) do
    table.insert(ctrls, {Name = weekday.controlName, ControlType = "Text", Count = 1})
  end
  table.insert(ctrls, {Name = "WeekPatternEditorStatus", ControlType = "Text", Count = 1})

  table.insert(ctrls, {Name = "ReloadActions", ControlType = "Button", ButtonType = "Momentary", UserPin = true, PinStyle = "Input", Count = 1})
  table.insert(ctrls, {Name = "ActionSelect", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "TestAction", ControlType = "Button", ButtonType = "Momentary", Count = 1})

  -- Persist the canonical versioned multi-Scheduler configuration as JSON.
  table.insert(ctrls, {Name = "ScheduleData", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "ScheduleDataViewer", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "ReloadSchedule", ControlType = "Button", ButtonType = "Momentary", Count = 1})
  table.insert(ctrls, {Name = "TestDateTime", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "ResolveTestTime", ControlType = "Button", ButtonType = "Momentary", Count = 1})

  -- Display build metadata formatted in the Core or emulator's local timezone.
  table.insert(ctrls, {Name = "BuildDateDisplay", ControlType = "Text", Count = 1})

  table.insert(ctrls, {Name = "Status", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "RegistryStatus", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "RegisteredActionCount", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "ScheduleStatus", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "SchedulerCount", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "GlobalSchedulerStatus", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "GlobalSchedulerStatusViewer", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "ResolutionSource", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "ResolvedDayPattern", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "PreviousEvent", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "CurrentEvent", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "CurrentEventActions", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "NextEvent", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "NextEventTime", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "Countdown", ControlType = "Text", UserPin = true, PinStyle = "Output", Count = 1})
  table.insert(ctrls, {Name = "DiagnosticLog", ControlType = "Text", Count = 1})
  table.insert(ctrls, {Name = "DiagnosticLogViewer", ControlType = "Text", Count = 1})

  return ctrls
end
