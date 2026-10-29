-- Q-SYS calls this to build the current page's layout and graphics tables.
function GetControlLayout(props)
  local ui = FugUi.new(FugSchedulerTheme)
  local page = currentPageName(props)

  ui:background()
  ui:header(page, "Version " .. tostring(PluginInfo.Version))
  ui:hiddenControl("code")
  ui:hiddenControl("ActionSource")
  ui:statusBar("Status")

  if page == "Scheduler Slots" then
    local slotCount = propValue(props, "Scheduler Slot Count", 8)
    local toolbar = FugUi.box(ui, ui:rect(10, 44, 880, 46), {padding = 6})
    toolbar:group("", {Fill = ui:color("panel"), StrokeColor = ui:color("stroke"), CornerRadius = 5})
    local master, execution = toolbar:splitRow({{width = 178}, {grow = 1}}, {gap = 6})
    ui:button("AutomaticExecutionEnabled", master:fill(), {
      ButtonStyle = "Toggle", Legend = "Master Enable", Color = ui:color("danger")
    })
    ui:textControl("ExecutionStatus", execution:fill(), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
      HTextAlign = "Left", VTextAlign = "Center", FontSize = 9
    })

    FugSchedulerUi.slotHeader(ui, ui:rect(10, 96, 880, 22))
    local slotRows = ui:rows(ui:rect(10, 122, 880, 310), FugSchedulerSlotRowsPerBank, 3)
    for slotNumber = 1, slotCount do
      local rowIndex = ((slotNumber - 1) % FugSchedulerSlotRowsPerBank) + 1
      FugSchedulerUi.slotRow(ui, slotRows[rowIndex], slotNumber)
    end
    ui:button("SchedulerSlotsPreviousBank", ui:rect(582, 442, 28, 22), {
      ButtonStyle = "Momentary", Legend = "◀", Color = ui:color("statusBackground"),
      TextColor = {255, 255, 255}, FontSize = 9
    })
    ui:textControl("SchedulerSlotsBankStatus", ui:rect(616, 442, 240, 22), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
      HTextAlign = "Center", VTextAlign = "Center", FontSize = 9
    })
    ui:button("SchedulerSlotsNextBank", ui:rect(862, 442, 28, 22), {
      ButtonStyle = "Momentary", Legend = "▶", Color = ui:color("statusBackground"),
      TextColor = {255, 255, 255}, FontSize = 9
    })

  elseif page == "Slot Inspector" then
    ui:label("Slot", ui:rect(18, 50, 40, 20), {Color = ui:color("mutedText")})
    ui:control("InspectorSlotSelect", "ComboBox", ui:rect(64, 46, 214, 26), {
      PrettyName = "Slot Inspector~Selected Scheduler Slot"
    })
    ui:button("InspectorSlotEnabled", ui:rect(286, 46, 54, 26), {
      ButtonStyle = "Toggle", Legend = "Enable", Color = ui:color("ok")
    })

    ui:group("Pause Controls", ui:rect(10, 82, 330, 362))
    ui:label("Paused", ui:rect(28, 112, 82, 22), {Color = ui:color("mutedText")})
    ui:button("InspectorSlotPaused", ui:rect(112, 108, 76, 26), {
      ButtonStyle = "Toggle", Legend = "Pause", Color = ui:color("warning")
    })
    ui:label("Mode", ui:rect(28, 150, 82, 22), {Color = ui:color("mutedText")})
    ui:control("InspectorPauseMode", "ComboBox", ui:rect(112, 146, 160, 26), {
      PrettyName = "Slot Inspector~Pause Mode"
    })
    ui:label("Duration", ui:rect(28, 188, 82, 22), {Color = ui:color("mutedText")})
    ui:textControl("InspectorPauseDurationMinutes", ui:rect(112, 184, 72, 26), {
      PrettyName = "Slot Inspector~Pause Duration Minutes"
    })
    ui:label("minutes", ui:rect(190, 188, 64, 22), {Color = ui:color("mutedText")})
    ui:label("Until", ui:rect(28, 226, 82, 22), {Color = ui:color("mutedText")})
    ui:textControl("InspectorPauseUntilTime", ui:rect(112, 222, 190, 26), {
      PrettyName = "Slot Inspector~Pause Until Time"
    })
    ui:label("Use Core-local YYYY-MM-DD HH:MM. Editing an active pause re-arms it immediately.",
      ui:rect(28, 264, 274, 54), {Color = ui:color("mutedText"), WordWrap = true, VTextAlign = "Top"})

    ui:group("Live Status", ui:rect(350, 44, 540, 400))
    FugSchedulerUi.statusField(ui, "Scheduler", "InspectorSchedulerName", ui:rect(368, 68, 504, 18))
    FugSchedulerUi.statusField(ui, "Enable status", "InspectorEnableStatus", ui:rect(368, 90, 504, 18), {
      IsBold = true
    })
    FugSchedulerUi.statusField(ui, "Resolution source", "ResolutionSource", ui:rect(368, 112, 504, 18))
    FugSchedulerUi.statusField(ui, "Day Pattern", "ResolvedDayPattern", ui:rect(368, 134, 504, 18))
    FugSchedulerUi.statusField(ui, "Pause status", "InspectorPauseStatus", ui:rect(368, 156, 504, 18))
    FugSchedulerUi.statusField(ui, "Pause request at", "InspectorPauseRequested", ui:rect(368, 178, 504, 18))
    FugSchedulerUi.statusField(ui, "Pause target", "InspectorPauseTarget", ui:rect(368, 200, 504, 18))
    FugSchedulerUi.statusField(ui, "Pause remaining", "InspectorPauseRemaining", ui:rect(368, 222, 504, 18))

    ui:group("Current Event", ui:rect(362, 250, 250, 190))
    ui:textControl("CurrentEvent", ui:rect(374, 274, 226, 22), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
      HTextAlign = "Left", VTextAlign = "Center", IsBold = true, FontSize = 9, WordWrap = true,
      PrettyName = "Slot Inspector~Current Event"
    })
    ui:label("Actions", ui:rect(374, 302, 226, 16), {Color = ui:color("mutedText"), FontSize = 8})
    FugSchedulerUi.actionViewer(ui, "CurrentEventActionsViewer", ui:rect(374, 320, 226, 64),
      "Slot Inspector~Current Event Actions")

    ui:group("Next Event", ui:rect(618, 250, 260, 190))
    ui:textControl("NextEvent", ui:rect(630, 274, 236, 22), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
      HTextAlign = "Left", VTextAlign = "Center", IsBold = true, FontSize = 9, WordWrap = true,
      PrettyName = "Slot Inspector~Next Event"
    })
    ui:label("Actions", ui:rect(630, 302, 236, 16), {Color = ui:color("mutedText"), FontSize = 8})
    FugSchedulerUi.actionViewer(ui, "NextEventActionsViewer", ui:rect(630, 320, 236, 64),
      "Slot Inspector~Next Event Actions")
    FugSchedulerUi.statusField(ui, "Starts", "NextEventTime", ui:rect(630, 390, 236, 18), {
      labelWidth = 70, FontSize = 8
    })
    FugSchedulerUi.statusField(ui, "Time until", "Countdown", ui:rect(630, 414, 236, 18), {
      labelWidth = 70, IsBold = true, FontSize = 9
    })

  elseif page == "Scheduler Definitions" then
    ui:group("Scheduler Definition Editor", ui:rect(10, 44, 570, 400))
    ui:label("Definition", ui:rect(28, 70, 140, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefinitionSelect", "ComboBox", ui:rect(174, 68, 368, 26), {
      PrettyName = "Scheduler Definitions~Selected Definition"
    })
    ui:label("Label", ui:rect(28, 108, 140, 22), {Color = ui:color("mutedText")})
    ui:textControl("SchedulerDefinitionLabel", ui:rect(174, 106, 368, 26), {
      PrettyName = "Scheduler Definitions~Label"
    })
    ui:label("Default Week Pattern", ui:rect(28, 146, 140, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefinitionDefaultWeekPattern", "ComboBox", ui:rect(174, 144, 368, 26), {
      PrettyName = "Scheduler Definitions~Default Week Pattern"
    })
    ui:button("AddSchedulerDefinition", ui:rect(28, 214, 154, 28), {
      ButtonStyle = "Momentary", Legend = "Add Definition", Color = ui:color("schedule")
    })
    ui:button("DuplicateSchedulerDefinition", ui:rect(198, 214, 164, 28), {
      ButtonStyle = "Momentary", Legend = "Duplicate", Color = ui:color("accent")
    })
    ui:button("DeleteSchedulerDefinition", ui:rect(378, 214, 164, 28), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })
    ui:label("Validation / transaction status", ui:rect(28, 278, 514, 20), {Color = ui:color("mutedText")})
    FugSchedulerUi.editorStatus(ui, "SchedulerDefinitionEditorStatus", ui:rect(28, 300, 514, 60),
      "Scheduler Definitions~Editor Status")

    ui:group("Slot Assignment", ui:rect(590, 44, 300, 400))
    ui:label("Assigned slot", ui:rect(610, 76, 260, 20), {Color = ui:color("mutedText")})
    ui:textControl("SchedulerDefinitionAssignedSlot", ui:rect(610, 102, 260, 30), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", HTextAlign = "Left",
      TextColor = ui:color("controlText"), FontSize = 11, IsBold = true
    })
    ui:button("UnassignSchedulerDefinition", ui:rect(610, 148, 260, 28), {
      ButtonStyle = "Momentary", Legend = "Unassign from Slot", Color = ui:color("warning")
    })
    ui:label("Definitions are inert until assigned to a runnable Scheduler Slot.",
      ui:rect(610, 198, 260, 60), {Color = ui:color("mutedText"), WordWrap = true, VTextAlign = "Top"})

  elseif page == "Day Patterns" then
    ui:label("Scheduler", ui:rect(18, 48, 92, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefinitionSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Day Patterns~Selected Definition"
    })

    ui:group("Day Patterns", ui:rect(10, 82, 282, 356))
    ui:control("DayPatternSelect", "ListBox", ui:rect(24, 110, 254, 142), {
      PrettyName = "Day Patterns~Selected Day Pattern",
      FontSize = 10
    })
    ui:label("Label", ui:rect(24, 260, 54, 22), {Color = ui:color("mutedText")})
    ui:textControl("DayPatternLabel", ui:rect(80, 258, 198, 26), {
      PrettyName = "Day Patterns~Label"
    })
    ui:textControl("DayPatternSummary", ui:rect(24, 292, 254, 22), {
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      HTextAlign = "Left",
      TextColor = ui:color("controlText")
    })
    ui:textControl("DayPatternReferences", ui:rect(24, 316, 254, 38), {
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      HTextAlign = "Left",
      VTextAlign = "Top",
      WordWrap = true,
      TextColor = ui:color("mutedText"),
      FontSize = 9
    })
    ui:button("AddDayPattern", ui:rect(24, 366, 72, 28), {
      ButtonStyle = "Momentary", Legend = "Add", Color = ui:color("schedule")
    })
    ui:button("DuplicateDayPattern", ui:rect(102, 366, 92, 28), {
      ButtonStyle = "Momentary", Legend = "Duplicate", Color = ui:color("accent")
    })
    ui:button("DeleteDayPattern", ui:rect(200, 366, 78, 28), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })

    ui:group("Events", ui:rect(302, 82, 282, 356))
    ui:control("EventSelect", "ListBox", ui:rect(316, 110, 254, 142), {
      PrettyName = "Day Patterns~Selected Event",
      FontSize = 10
    })
    ui:label("Label", ui:rect(316, 260, 48, 22), {Color = ui:color("mutedText")})
    ui:textControl("EventLabel", ui:rect(366, 258, 204, 26), {
      PrettyName = "Day Patterns~Event Label"
    })
    ui:label("Time", ui:rect(316, 294, 48, 22), {Color = ui:color("mutedText")})
    ui:textControl("EventTime", ui:rect(366, 292, 92, 26), {
      PrettyName = "Day Patterns~Event Time",
      HTextAlign = "Center"
    })
    ui:textControl("EventSummary", ui:rect(466, 292, 104, 26), {
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      HTextAlign = "Right",
      TextColor = ui:color("mutedText"),
      FontSize = 9
    })
    ui:button("AddEvent", ui:rect(316, 366, 72, 28), {
      ButtonStyle = "Momentary", Legend = "Add", Color = ui:color("schedule")
    })
    ui:button("DuplicateEvent", ui:rect(394, 366, 92, 28), {
      ButtonStyle = "Momentary", Legend = "Duplicate", Color = ui:color("accent")
    })
    ui:button("DeleteEvent", ui:rect(492, 366, 78, 28), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })

    ui:group("Event Actions", ui:rect(594, 82, 296, 356))
    ui:control("EventActionSelect", "ListBox", ui:rect(608, 106, 268, 82), {
      PrettyName = "Day Patterns~Selected Event Action",
      FontSize = 9
    })
    ui:label("Attached Action", ui:rect(608, 194, 82, 18), {Color = ui:color("mutedText"), FontSize = 9})
    ui:control("EventActionPicker", "ComboBox", ui:rect(692, 192, 184, 24), {
      PrettyName = "Day Patterns~Attached Action"
    })
    ui:button("EventActionEnabled", ui:rect(608, 224, 82, 24), {
      ButtonStyle = "Toggle", Legend = "Enabled", Color = ui:color("accent")
    })
    ui:control("EventActionMode", "ComboBox", ui:rect(698, 224, 178, 24), {
      PrettyName = "Day Patterns~Event Action Mode"
    })
    ui:button("EventActionFireOnStartup", ui:rect(608, 256, 128, 24), {
      ButtonStyle = "Toggle", Legend = "Restore on Start", Color = ui:color("schedule")
    })
    ui:button("EventActionFireOnResume", ui:rect(748, 256, 128, 24), {
      ButtonStyle = "Toggle", Legend = "Restore on Resume", Color = ui:color("schedule")
    })
    ui:label("Repeat seconds", ui:rect(608, 290, 104, 20), {Color = ui:color("mutedText"), FontSize = 9})
    ui:textControl("EventActionRepeatSeconds", ui:rect(718, 286, 158, 24), {
      PrettyName = "Day Patterns~Repeat Seconds",
      HTextAlign = "Center"
    })
    ui:button("AddEventAction", ui:rect(608, 320, 128, 24), {
      ButtonStyle = "Momentary", Legend = "Add Action", Color = ui:color("action", ui:color("warning"))
    })
    ui:button("DeleteEventAction", ui:rect(748, 320, 128, 24), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })
    ui:button("MoveEventActionUp", ui:rect(608, 354, 128, 24), {
      ButtonStyle = "Momentary", Legend = "Move Up", Color = ui:color("accent")
    })
    ui:button("MoveEventActionDown", ui:rect(748, 354, 128, 24), {
      ButtonStyle = "Momentary", Legend = "Move Down", Color = ui:color("accent")
    })

    FugSchedulerUi.editorStatus(
      ui,
      "DayPatternEditorStatus",
      ui:rect(10, 448, 880, 34),
      "Day Patterns~Editor Status"
    )

  elseif page == "Week Patterns" then
    ui:label("Scheduler", ui:rect(18, 48, 92, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefinitionSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Week Patterns~Selected Definition"
    })

    ui:group("Week Patterns", ui:rect(10, 82, 300, 356))
    ui:control("WeekPatternSelect", "ListBox", ui:rect(24, 110, 272, 142), {
      PrettyName = "Week Patterns~Selected Week Pattern",
      FontSize = 10
    })
    ui:label("Label", ui:rect(24, 262, 54, 22), {Color = ui:color("mutedText")})
    ui:textControl("WeekPatternLabel", ui:rect(80, 260, 216, 26), {
      PrettyName = "Week Patterns~Label"
    })
    ui:label("References", ui:rect(24, 296, 272, 18), {Color = ui:color("mutedText")})
    ui:textControl("WeekPatternReferences", ui:rect(24, 316, 272, 38), {
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      HTextAlign = "Left",
      VTextAlign = "Top",
      WordWrap = true,
      TextColor = ui:color("controlText"),
      FontSize = 9
    })
    ui:button("AddWeekPattern", ui:rect(24, 366, 76, 28), {
      ButtonStyle = "Momentary", Legend = "Add", Color = ui:color("schedule")
    })
    ui:button("DuplicateWeekPattern", ui:rect(106, 366, 104, 28), {
      ButtonStyle = "Momentary", Legend = "Duplicate", Color = ui:color("accent")
    })
    ui:button("DeleteWeekPattern", ui:rect(216, 366, 80, 28), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })

    ui:group("Weekday Assignments", ui:rect(320, 82, 570, 356))
    for index, weekday in ipairs(FugSchedulerWeekdays) do
      FugSchedulerUi.weekdayAssignment(ui, weekday, 110 + ((index - 1) * 36))
    end
    ui:label("Assignments store stable Day Pattern IDs; labels are display-only.", ui:rect(340, 370, 530, 30), {
      Color = ui:color("mutedText"),
      HTextAlign = "Center",
      WordWrap = true,
      FontSize = 9
    })

    FugSchedulerUi.editorStatus(
      ui,
      "WeekPatternEditorStatus",
      ui:rect(10, 448, 880, 34),
      "Week Patterns~Editor Status"
    )

  elseif page == "Overrides" then
    ui:label("Scheduler", ui:rect(18, 48, 92, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefinitionSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Overrides~Selected Definition"
    })

    ui:group("Overrides", ui:rect(10, 82, 280, 356))
    ui:control("OverrideSelect", "ListBox", ui:rect(24, 110, 252, 190), {
      PrettyName = "Overrides~Selected Override",
      FontSize = 10
    })
    ui:button("AddOverride", ui:rect(24, 312, 68, 28), {
      ButtonStyle = "Momentary", Legend = "Add", Color = ui:color("schedule")
    })
    ui:button("DuplicateOverride", ui:rect(98, 312, 88, 28), {
      ButtonStyle = "Momentary", Legend = "Duplicate", Color = ui:color("accent")
    })
    ui:button("DeleteOverride", ui:rect(192, 312, 84, 28), {
      ButtonStyle = "Momentary", Legend = "Delete", Color = ui:color("danger")
    })
    ui:button("MoveOverrideUp", ui:rect(24, 354, 120, 28), {
      ButtonStyle = "Momentary", Legend = "Move Up", Color = ui:color("accent")
    })
    ui:button("MoveOverrideDown", ui:rect(156, 354, 120, 28), {
      ButtonStyle = "Momentary", Legend = "Move Down", Color = ui:color("accent")
    })

    ui:group("Override Details", ui:rect(300, 82, 590, 356))
    ui:label("Label", ui:rect(314, 106, 88, 22), {Color = ui:color("mutedText")})
    ui:textControl("OverrideLabel", ui:rect(406, 104, 270, 26), {PrettyName = "Overrides~Label"})
    ui:button("OverrideEnabled", ui:rect(690, 104, 180, 28), {
      ButtonStyle = "Toggle", Legend = "Enabled", Color = ui:color("accent")
    })
    ui:label("Type", ui:rect(314, 144, 88, 22), {Color = ui:color("mutedText")})
    ui:control("OverrideType", "ComboBox", ui:rect(406, 142, 270, 26), {PrettyName = "Overrides~Type"})
    ui:label("Pattern", ui:rect(314, 178, 88, 22), {Color = ui:color("mutedText")})
    ui:control("OverridePattern", "ComboBox", ui:rect(406, 176, 270, 26), {PrettyName = "Overrides~Pattern"})

    FugSchedulerUi.overrideDateField(ui, "Start Date", "OverrideStartDate", "OverrideStartDateLongForm", "OverrideStartDateValidation", 222)
    FugSchedulerUi.overrideDateButton(ui, "SetOverrideRangeToday", "Today", 576, 223)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideStartBackDay", "-1 Day", 634, 223)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideStartForwardDay", "+1 Day", 692, 223)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideStartBackWeek", "-1 Wk", 750, 223)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideStartForwardWeek", "+1 Wk", 808, 223)

    FugSchedulerUi.overrideDateField(ui, "End Date", "OverrideEndDate", "OverrideEndDateLongForm", "OverrideEndDateValidation", 275)
    FugSchedulerUi.overrideDateButton(ui, "SetOverrideRangeOneDay", "1 Day", 576, 276)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideRangeBack", "-1 Day", 634, 276)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideRangeForward", "+1 Day", 692, 276)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideEndBackWeek", "-1 Wk", 750, 276)
    FugSchedulerUi.overrideDateButton(ui, "ShiftOverrideEndForwardWeek", "+1 Wk", 808, 276)

    ui:textControl("OverrideRangeSummary", ui:rect(314, 325, 556, 38), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", HTextAlign = "Center", VTextAlign = "Center",
      WordWrap = true, TextColor = ui:color("controlText"), FontSize = 10
    })
    ui:textControl("OverrideSummary", ui:rect(314, 367, 556, 24), {
      IsReadOnly = true, TextBoxStyle = "NoBackground", HTextAlign = "Center", VTextAlign = "Center",
      WordWrap = true, TextColor = ui:color("mutedText"), FontSize = 9
    })

    FugSchedulerUi.editorStatus(
      ui,
      "OverrideEditorStatus",
      ui:rect(10, 448, 880, 34),
      "Overrides~Editor Status"
    )

  elseif page == "Actions" then
    ui:group("External Action Registry", ui:rect(10, 44, 880, 400))
    ui:label("Connect trusted Lua source to ActionSource. The source defines GetFugSchedulerActions(), which returns Action definitions used by Event Actions.", ui:rect(28, 78, 844, 62), {
      VTextAlign = "Top",
      WordWrap = true,
      Color = ui:color("mutedText")
    })
    ui:button("ReloadActions", ui:rect(28, 132, 130, 26), {
      ButtonStyle = "Momentary",
      Legend = "Reload Actions",
      Color = ui:color("action", ui:color("warning"))
    })
    ui:label("Registered Action", ui:rect(28, 176, 130, 24), {Color = ui:color("mutedText")})
    ui:control("ActionSelect", "ComboBox", ui:rect(164, 176, 360, 26), {PrettyName = "Actions~Selected Action"})
    ui:button("TestAction", ui:rect(540, 176, 120, 26), {
      ButtonStyle = "Momentary",
      Legend = "Test Action",
      Color = ui:color("action", ui:color("warning"))
    })
    FugSchedulerUi.statusField(ui, "Registry status", "RegistryStatus", ui:rect(28, 224, 632, 24))
    FugSchedulerUi.statusField(ui, "Action count", "RegisteredActionCount", ui:rect(28, 256, 632, 24))

  elseif page == "Preferences" then
    ui:group("Presentation Preferences", ui:rect(10, 44, 430, 236))
    ui:label("Date format", ui:rect(32, 82, 160, 24), {Color = ui:color("mutedText")})
    ui:control("DateFormatPreference", "ComboBox", ui:rect(202, 80, 216, 28), {
      PrettyName = "Preferences~Date Format"
    })
    ui:label("Controls how Override dates are entered and displayed. Persisted ScheduleData always uses ISO YYYY-MM-DD.", ui:rect(32, 132, 386, 72), {
      VTextAlign = "Top", WordWrap = true, Color = ui:color("mutedText")
    })

    ui:group("Logging Preferences", ui:rect(450, 44, 440, 236))
    ui:label("Debug Output level", ui:rect(472, 82, 170, 24), {Color = ui:color("mutedText")})
    ui:control("DebugLogLevel", "ComboBox", ui:rect(652, 80, 216, 28), {
      PrettyName = "Preferences~Debug Output Level"
    })
    ui:label("Event Log level", ui:rect(472, 124, 170, 24), {Color = ui:color("mutedText")})
    ui:control("EventLogLevel", "ComboBox", ui:rect(652, 122, 216, 28), {
      PrettyName = "Preferences~Event Log Level"
    })
    ui:label("Debug Output uses print. Event Log uses Log.Message and Log.Error. The bounded DiagnosticLog always records every severity.", ui:rect(472, 172, 396, 74), {
      VTextAlign = "Top", WordWrap = true, Color = ui:color("mutedText")
    })

    ui:group("Preference Status", ui:rect(10, 292, 880, 92))
    FugSchedulerUi.editorStatus(ui, "PreferencesStatus", ui:rect(32, 326, 836, 40), "Preferences~Status")

  elseif page == "Diagnostics" then
    ui:group("Resolution Preview", ui:rect(10, 44, 880, 92))
    ui:label("Test date/time", ui:rect(28, 74, 96, 22), {Color = ui:color("mutedText")})
    ui:textControl("TestDateTime", ui:rect(126, 70, 274, 28), {
      PrettyName = "Diagnostics~Test Date Time"
    })
    ui:button("ResolveTestTime", ui:rect(414, 70, 138, 28), {
      ButtonStyle = "Momentary", Legend = "Preview Test Time", Color = ui:color("accent")
    })
    ui:button("UseLiveTime", ui:rect(564, 70, 138, 28), {
      ButtonStyle = "Momentary", Legend = "Use Live Time", Color = ui:color("schedule")
    })
    ui:label("Blank means live time. A test value pins Slot Inspector and JSON status until Use Live Time is pressed.", ui:rect(714, 62, 158, 54), {
      VTextAlign = "Top", WordWrap = true, FontSize = 9, Color = ui:color("mutedText")
    })

    ui:group("Diagnostics", ui:rect(10, 146, 430, 298))
    FugSchedulerUi.dataViewer(
      ui,
      "DiagnosticLogViewer",
      ui:rect(28, 180, 394, 230),
      "Diagnostics~Log",
      true
    )
    ui:group("Global Scheduler Slot Status JSON", ui:rect(450, 146, 440, 298))
    FugSchedulerUi.dataViewer(
      ui,
      "GlobalSchedulerSlotStatusViewer",
      ui:rect(468, 180, 404, 230),
      "Diagnostics~Global Scheduler Slot Status",
      true
    )

  elseif page == "About" then
    ui:group("FugScheduler 2000", ui:rect(10, 44, 880, 400))
    ui:label(PluginInfo.Description, ui:rect(32, 76, 836, 54), {
      FontSize = 13,
      VTextAlign = "Top",
      WordWrap = true,
      Color = ui:color("text")
    })

    ui:label("Q-SYS Version", ui:rect(32, 154, 180, 24), {Color = ui:color("mutedText")})
    ui:label(tostring(PluginInfo.Version), ui:rect(222, 154, 646, 24), {
      FontSize = 13,
      IsBold = true,
      Color = ui:color("text")
    })
    ui:label("Build Version", ui:rect(32, 190, 180, 24), {Color = ui:color("mutedText")})
    ui:label(tostring(PluginInfo.BuildVersion), ui:rect(222, 190, 646, 24), {
      FontSize = 13,
      Color = ui:color("text")
    })
    ui:label("Build Date (Local)", ui:rect(32, 226, 180, 24), {Color = ui:color("mutedText")})
    ui:textControl("BuildDateDisplay", ui:rect(222, 226, 646, 24), {
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      TextColor = ui:color("controlText"),
      Font = "Roboto",
      FontSize = 10,
      HTextAlign = "Left",
      VTextAlign = "Center",
      PrettyName = "About~Build Date"
    })
    ui:label("Plugin ID", ui:rect(32, 262, 180, 24), {Color = ui:color("mutedText")})
    ui:label(tostring(PluginInfo.Id), ui:rect(222, 262, 646, 24), {
      Font = "Roboto",
      FontSize = 10,
      Color = ui:color("text")
    })
    ui:label("Author", ui:rect(32, 298, 180, 24), {Color = ui:color("mutedText")})
    ui:label(tostring(PluginInfo.Author), ui:rect(222, 298, 646, 24), {
      Font = "Roboto",
      FontSize = 10,
      Color = ui:color("text")
    })

    ui:label("Release commits are identified by Semantic Versioning Git tags. The build version identifies the specific development build being tested.", ui:rect(32, 350, 836, 58), {
      VTextAlign = "Top",
      WordWrap = true,
      Color = ui:color("mutedText")
    })
  end

  if propValue(props, "Layout Debug", false) then
    ui:label(page .. " | canvas " .. ui.theme.pageW .. "x" .. ui.theme.pageH, ui:rect(10, 470, 880, 16), {
      FontSize = 9,
      Color = ui:color("warning")
    })
  end

  return ui:result()
end
