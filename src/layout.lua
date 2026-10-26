-- Q-SYS calls this to build the current page's layout and graphics tables.
function GetControlLayout(props)
  local ui = FugUi.new(FugSchedulerTheme)
  local page = currentPageName(props)

  ui:background()
  ui:header(page, "Version " .. tostring(PluginInfo.Version))
  ui:hiddenControl("code")
  ui:hiddenControl("ActionSource")
  ui:statusBar("Status")

  if page == "Overview" then
    ui:group("Scheduler Resolution", ui:rect(10, 44, 570, 400))
    ui:control("SchedulerSelect", "ComboBox", ui:rect(28, 70, 250, 26), {
      PrettyName = "Schedules~Selected Scheduler"
    })
    ui:button("SchedulerEnabled", ui:rect(292, 70, 130, 26), {
      ButtonStyle = "Toggle",
      Legend = "Scheduler Enabled",
      IsDisabled = true,
      Color = ui:color("accent")
    })
    ui:button("ReloadSchedule", ui:rect(436, 70, 124, 26), {
      ButtonStyle = "Momentary",
      Legend = "Reload Schedule",
      Color = ui:color("schedule")
    })

    FugSchedulerUi.statusField(ui, "Action registry", "RegistryStatus", ui:rect(28, 108, 532, 22))
    FugSchedulerUi.statusField(ui, "Schedule", "ScheduleStatus", ui:rect(28, 136, 532, 22))
    FugSchedulerUi.statusField(ui, "Resolution source", "ResolutionSource", ui:rect(28, 164, 532, 22))
    FugSchedulerUi.statusField(ui, "Day Pattern", "ResolvedDayPattern", ui:rect(28, 192, 532, 22))
    FugSchedulerUi.statusField(ui, "Previous Event", "PreviousEvent", ui:rect(28, 220, 532, 22))
    FugSchedulerUi.statusField(ui, "Current Event", "CurrentEvent", ui:rect(28, 248, 532, 22))
    FugSchedulerUi.statusField(ui, "Current Actions", "CurrentEventActions", ui:rect(28, 276, 532, 22))
    FugSchedulerUi.statusField(ui, "Next Event", "NextEvent", ui:rect(28, 304, 532, 22))
    FugSchedulerUi.statusField(ui, "Next Event Time", "NextEventTime", ui:rect(28, 332, 532, 22))
    FugSchedulerUi.statusField(ui, "Countdown", "Countdown", ui:rect(28, 360, 532, 22))

    ui:group("Execution Safety", ui:rect(590, 44, 300, 400))
    ui:label("Automatic callbacks", ui:rect(610, 76, 260, 28), {
      FontSize = 18,
      IsBold = true,
      Color = ui:color("text")
    })
    ui:button("AutomaticExecutionEnabled", ui:rect(610, 116, 260, 30), {
      ButtonStyle = "Toggle",
      Legend = "Automatic Execution Enabled",
      Color = ui:color("danger")
    })
    ui:label("Defaults off. When enabled, only enabled and unpaused Schedulers may execute registered callbacks.", ui:rect(610, 158, 258, 66), {
      VTextAlign = "Top",
      WordWrap = true,
      Color = ui:color("mutedText")
    })
    FugSchedulerUi.statusField(ui, "Execution", "ExecutionStatus", ui:rect(610, 242, 258, 44))
    FugSchedulerUi.statusField(ui, "Schedulers", "SchedulerCount", ui:rect(610, 304, 258, 22))
    FugSchedulerUi.statusField(ui, "Actions", "RegisteredActionCount", ui:rect(610, 332, 258, 22))

  elseif page == "Schedules" then
    ui:group("Scheduler Editor", ui:rect(10, 44, 570, 400))
    ui:label("Scheduler", ui:rect(28, 70, 140, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerSelect", "ComboBox", ui:rect(174, 68, 368, 26), {
      PrettyName = "Schedules~Selected Scheduler"
    })

    ui:label("Label", ui:rect(28, 108, 140, 22), {Color = ui:color("mutedText")})
    ui:textControl("SchedulerLabel", ui:rect(174, 106, 368, 26), {
      PrettyName = "Schedules~Label"
    })
    ui:label("Default Week Pattern", ui:rect(28, 146, 140, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerDefaultWeekPattern", "ComboBox", ui:rect(174, 144, 368, 26), {
      PrettyName = "Schedules~Default Week Pattern"
    })

    ui:button("SchedulerEditorEnabled", ui:rect(174, 184, 176, 28), {
      ButtonStyle = "Toggle",
      Legend = "Enabled",
      Color = ui:color("accent")
    })
    ui:button("SchedulerPaused", ui:rect(366, 184, 176, 28), {
      ButtonStyle = "Toggle",
      Legend = "Paused",
      Color = ui:color("warning")
    })

    ui:button("AddScheduler", ui:rect(28, 236, 154, 28), {
      ButtonStyle = "Momentary",
      Legend = "Add Scheduler",
      Color = ui:color("schedule")
    })
    ui:button("DuplicateScheduler", ui:rect(198, 236, 164, 28), {
      ButtonStyle = "Momentary",
      Legend = "Duplicate",
      Color = ui:color("accent")
    })
    ui:button("DeleteScheduler", ui:rect(378, 236, 164, 28), {
      ButtonStyle = "Momentary",
      Legend = "Delete",
      Color = ui:color("danger")
    })

    ui:label("Validation / transaction status", ui:rect(28, 284, 514, 20), {Color = ui:color("mutedText")})
    FugSchedulerUi.editorStatus(
      ui,
      "SchedulerEditorStatus",
      ui:rect(28, 306, 514, 54),
      "Schedules~Editor Status"
    )

    ui:group("Resolver / JSON", ui:rect(590, 44, 300, 400))
    ui:label("Test date/time", ui:rect(610, 70, 260, 20), {Color = ui:color("mutedText")})
    ui:textControl("TestDateTime", ui:rect(610, 92, 260, 26), {
      PrettyName = "Schedule~Test Date Time"
    })
    ui:button("ResolveTestTime", ui:rect(610, 128, 124, 26), {
      ButtonStyle = "Momentary",
      Legend = "Resolve All",
      Color = ui:color("accent")
    })
    ui:button("ReloadSchedule", ui:rect(746, 128, 124, 26), {
      ButtonStyle = "Momentary",
      Legend = "Validate JSON",
      Color = ui:color("schedule")
    })
    FugSchedulerUi.statusField(ui, "Schedule", "ScheduleStatus", ui:rect(610, 166, 260, 22))
    FugSchedulerUi.statusField(ui, "Source", "ResolutionSource", ui:rect(610, 194, 260, 22))
    FugSchedulerUi.statusField(ui, "Day Pattern", "ResolvedDayPattern", ui:rect(610, 222, 260, 22))
    ui:label("Canonical ScheduleData", ui:rect(610, 258, 260, 20), {Color = ui:color("mutedText")})
    FugSchedulerUi.dataViewer(
      ui,
      "ScheduleDataViewer",
      ui:rect(610, 280, 260, 134),
      "Schedule~JSON Data",
      false
    )

  elseif page == "Day Patterns" then
    ui:label("Scheduler", ui:rect(18, 48, 92, 22), {Color = ui:color("mutedText")})
    ui:control("SchedulerSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Day Patterns~Selected Scheduler"
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
    ui:label("Attach Action", ui:rect(608, 194, 82, 18), {Color = ui:color("mutedText"), FontSize = 9})
    ui:control("EventActionPicker", "ComboBox", ui:rect(692, 192, 184, 24), {
      PrettyName = "Day Patterns~Action to Attach"
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
    ui:control("SchedulerSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Week Patterns~Selected Scheduler"
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
    ui:control("SchedulerSelect", "ComboBox", ui:rect(112, 46, 420, 26), {
      PrettyName = "Overrides~Selected Scheduler"
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
    ui:group("Diagnostics", ui:rect(10, 44, 430, 400))
    FugSchedulerUi.dataViewer(
      ui,
      "DiagnosticLogViewer",
      ui:rect(28, 78, 394, 332),
      "Diagnostics~Log",
      true
    )
    ui:group("Global Scheduler Status JSON", ui:rect(450, 44, 440, 400))
    FugSchedulerUi.dataViewer(
      ui,
      "GlobalSchedulerStatusViewer",
      ui:rect(468, 78, 404, 332),
      "Diagnostics~Global Scheduler Status",
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
