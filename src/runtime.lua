-- Keep hot-deployed runtime code self-contained when it runs in SchedulerRuntimeProvider.
-- Use bundled PluginInfo when available, with matching metadata for raw runtime hot deployment.
local FugSchedulerPluginInfo = PluginInfo or {
  BuildDate = "2026-10-26T09:18:54Z",
  BuildTimestamp = 1793006334
}

FugSchedulerWeekdays = FugSchedulerWeekdays or {
  {key = "Mon", label = "Monday", controlName = "WeekPatternMon"},
  {key = "Tue", label = "Tuesday", controlName = "WeekPatternTue"},
  {key = "Wed", label = "Wednesday", controlName = "WeekPatternWed"},
  {key = "Thu", label = "Thursday", controlName = "WeekPatternThu"},
  {key = "Fri", label = "Friday", controlName = "WeekPatternFri"},
  {key = "Sat", label = "Saturday", controlName = "WeekPatternSat"},
  {key = "Sun", label = "Sunday", controlName = "WeekPatternSun"}
}

-- Hold the latest aggregate runtime snapshot for internal and debug-runtime consumers.
FugSchedulerStatus = nil

FugSchedulerRuntime = {
  json = require("rapidjson"),
  actionsById = {},
  orderedActions = {},
  providerEnvironment = nil,
  activeSchedule = nil,
  scheduleWarnings = {},
  scheduleInitialized = false,
  selectedSchedulerId = nil,
  resolutionResultsById = {},
  globalStatus = nil,
  writingScheduleData = false,
  updatingSchedulerEditor = false,
  updatingDayPatternEditor = false,
  updatingWeekPatternEditor = false,
  updatingOverrideEditor = false,
  updatingPreferences = false,
  overrideDateBuffer = nil,
  selectedDayPatternIds = {},
  selectedWeekPatternIds = {},
  selectedOverrideIds = {},
  selectedEventIds = {},
  selectedEventActionIndexes = {},
  uuidCounter = 0,
  uuidSeeded = false
}

-- Populate a scrollable ListBox mirror from the individual lines of a Text source.
function FugSchedulerRuntime.refreshLineViewer(viewerName, value)
  local viewer = Controls[viewerName]
  if not viewer then return end

  local lines = {}
  local source = tostring(value or "")
  for line in string.gmatch(source .. "\n", "(.-)\n") do table.insert(lines, line) end
  if #lines == 0 then table.insert(lines, "") end
  viewer.Choices = lines

  local current = viewer.String or ""
  local currentExists = false
  for _, line in ipairs(lines) do
    if line == current then currentExists = true break end
  end
  if not currentExists then viewer.String = lines[1] end
end

-- Set a Text control safely and refresh its scrollable viewer when one is declared.
function FugSchedulerRuntime.setText(name, value)
  local text = tostring(value)
  if Controls[name] then Controls[name].String = text end
  local viewers = {
    ScheduleData = "ScheduleDataViewer",
    GlobalSchedulerStatus = "GlobalSchedulerStatusViewer",
    DiagnosticLog = "DiagnosticLogViewer"
  }
  if viewers[name] then FugSchedulerRuntime.refreshLineViewer(viewers[name], text) end
end

-- Format a UTC Unix build timestamp in the Core or emulator's local timezone.
function FugSchedulerRuntime.formatBuildDate(timestamp)
  local numericTimestamp = tonumber(timestamp)
  if not numericTimestamp then return tostring(FugSchedulerPluginInfo.BuildDate or "Unknown") end

  local okParts, parts = pcall(os.date, "*t", numericTimestamp)
  local okMonth, month = pcall(os.date, "%B", numericTimestamp)
  if not okParts or type(parts) ~= "table" or not okMonth then
    return tostring(FugSchedulerPluginInfo.BuildDate or "Unknown")
  end

  return string.format(
    "%d %s %d %02d:%02d",
    parts.day,
    tostring(month),
    parts.year,
    parts.hour,
    parts.min
  )
end

-- Append a bounded line to the diagnostic display.
function FugSchedulerRuntime.logLine(message)
  local control = Controls.DiagnosticLog
  if not control then return end

  local existing = control.String or ""
  if existing ~= "" then existing = existing .. "\n" end
  existing = existing .. tostring(message)
  if #existing > 12000 then existing = string.sub(existing, #existing - 11999) end
  control.String = existing
  FugSchedulerRuntime.refreshLineViewer("DiagnosticLogViewer", existing)
end

-- Return the sample multi-Scheduler configuration used when ScheduleData is initially empty.
function FugSchedulerRuntime.sampleSchedule()
  return {
    schemaVersion = 1,
    revision = 1,
    schedulers = {
      {
        id = "demo-scheduler",
        label = "Demo Scheduler",
        enabled = true,
        paused = false,
        defaultWeekPatternId = "normal-week",
        dayPatterns = {
          {
            id = "standard-weekday",
            label = "Standard Weekday",
            events = {
              {id = "weekday-morning", label = "Morning", time = "09:00", actions = {{actionId = "Callback1"}}},
              {id = "weekday-afternoon", label = "Afternoon", time = "14:00", actions = {{actionId = "Callback2"}}},
              {id = "weekday-closing", label = "Closing", time = "22:00", actions = {{actionId = "Callback1"}, {actionId = "Callback2"}}}
            }
          },
          {
            id = "standard-weekend",
            label = "Standard Weekend",
            events = {
              {id = "weekend-opening", label = "Weekend Opening", time = "10:00", actions = {{actionId = "Callback1"}}},
              {id = "weekend-closing", label = "Weekend Closing", time = "20:00", actions = {{actionId = "Callback2"}}}
            }
          },
          {
            id = "holiday-weekday",
            label = "Holiday Weekday",
            events = {
              {id = "holiday-opening", label = "Holiday Opening", time = "11:00", actions = {{actionId = "Callback1"}}},
              {id = "holiday-closing", label = "Holiday Closing", time = "18:00", actions = {{actionId = "Callback2"}}}
            }
          },
          {
            id = "closed",
            label = "Closed",
            events = {
              {id = "closed-state", label = "Closed State", time = "00:00", actions = {{actionId = "Callback2"}}}
            }
          }
        },
        weekPatterns = {
          {
            id = "normal-week",
            label = "Normal Operating Week",
            days = {
              Mon = "standard-weekday", Tue = "standard-weekday", Wed = "standard-weekday",
              Thu = "standard-weekday", Fri = "standard-weekday",
              Sat = "standard-weekend", Sun = "standard-weekend"
            }
          },
          {
            id = "holiday-week",
            label = "Holiday Week",
            days = {
              Mon = "holiday-weekday", Tue = "holiday-weekday", Wed = "holiday-weekday",
              Thu = "holiday-weekday", Fri = "holiday-weekday",
              Sat = "standard-weekend", Sun = "standard-weekend"
            }
          }
        },
        overrides = {
          {
            id = "christmas-day",
            label = "Christmas Day Closure",
            type = "DayPattern",
            startDate = "2026-12-25",
            endDate = "2026-12-25",
            patternId = "closed",
            enabled = true
          },
          {
            id = "christmas-period",
            label = "Christmas Operations",
            type = "WeekPattern",
            startDate = "2026-12-21",
            endDate = "2027-01-03",
            patternId = "holiday-week",
            enabled = true
          }
        }
      },
      {
        id = "demo-announcements",
        label = "Demo Announcements",
        enabled = true,
        paused = false,
        defaultWeekPatternId = "announcement-week",
        dayPatterns = {
          {
            id = "announcement-day",
            label = "Announcement Day",
            events = {
              {id = "opening-announcement", label = "Opening Announcement", time = "10:30", actions = {{actionId = "Callback2"}}},
              {id = "closing-announcement", label = "Closing Announcement", time = "18:30", actions = {{actionId = "Callback1"}}}
            }
          }
        },
        weekPatterns = {
          {
            id = "announcement-week",
            label = "Announcement Week",
            days = {
              Mon = "announcement-day", Tue = "announcement-day", Wed = "announcement-day",
              Thu = "announcement-day", Fri = "announcement-day",
              Sat = "announcement-day", Sun = "announcement-day"
            }
          }
        },
        overrides = {}
      }
    }
  }
end

-- Encode a Lua table as readable JSON, falling back to compact JSON if needed.
function FugSchedulerRuntime.encodeJson(value)
  local prettyOk, prettyValue = pcall(FugSchedulerRuntime.json.encode, value, {pretty = true})
  if prettyOk and prettyValue then return prettyValue end

  local compactOk, compactValue = pcall(FugSchedulerRuntime.json.encode, value)
  if compactOk and compactValue then return compactValue end
  return ""
end

-- Deep-copy persisted configuration while omitting runtime-only keys prefixed with an underscore.
function FugSchedulerRuntime.copyPersisted(value)
  if type(value) ~= "table" then return value end

  local copy = {}
  local sourceMetatable = getmetatable(value)
  if type(sourceMetatable) == "table" then setmetatable(copy, sourceMetatable) end
  for key, item in pairs(value) do
    if type(key) ~= "string" or string.sub(key, 1, 1) ~= "_" then
      copy[FugSchedulerRuntime.copyPersisted(key)] = FugSchedulerRuntime.copyPersisted(item)
    end
  end
  return copy
end

-- Mark an empty Lua table with RapidJSON's array metatable.
function FugSchedulerRuntime.markJsonArray(value)
  if type(value) ~= "table" or next(value) ~= nil then return value end
  local decodeOk, emptyArray = pcall(FugSchedulerRuntime.json.decode, "[]")
  if decodeOk and type(emptyArray) == "table" then
    local arrayMetatable = getmetatable(emptyArray)
    if type(arrayMetatable) == "table" then setmetatable(value, arrayMetatable) end
  end
  return value
end

-- Mark schema collection fields so RapidJSON emits empty collections as [] rather than {}.
function FugSchedulerRuntime.normalizeScheduleArrays(root)
  FugSchedulerRuntime.markJsonArray(root.schedulers)
  for _, scheduler in ipairs(root.schedulers or {}) do
    FugSchedulerRuntime.markJsonArray(scheduler.dayPatterns)
    FugSchedulerRuntime.markJsonArray(scheduler.weekPatterns)
    FugSchedulerRuntime.markJsonArray(scheduler.overrides)
    for _, dayPattern in ipairs(scheduler.dayPatterns or {}) do
      FugSchedulerRuntime.markJsonArray(dayPattern.events)
      for _, event in ipairs(dayPattern.events or {}) do
        FugSchedulerRuntime.markJsonArray(event.actions)
      end
    end
  end
  return root
end

-- Encode one structured ComboBox choice containing a display label and stable ID.
function FugSchedulerRuntime.encodeChoice(text, id)
  local encodeOk, encoded = pcall(FugSchedulerRuntime.json.encode, {Text = text, Id = id})
  if encodeOk and encoded then return encoded end
  return tostring(id or "")
end

-- Decode a structured ComboBox selection, accepting legacy plain-ID strings as a fallback.
function FugSchedulerRuntime.choiceId(value)
  if type(value) ~= "string" or value == "" then return nil end
  local decodeOk, decoded = pcall(FugSchedulerRuntime.json.decode, value)
  if decodeOk and type(decoded) == "table" and type(decoded.Id) == "string" then
    return decoded.Id
  end
  return value
end

-- Generate a UUID-v4-shaped stable ID and retry if it already exists in the model.
function FugSchedulerRuntime.generateUuid(existing)
  if not FugSchedulerRuntime.uuidSeeded then
    local addressHex = string.match(tostring({}), "0x(%x+)")
    local addressValue = addressHex and tonumber(addressHex, 16) or 0
    math.randomseed((os.time() + addressValue) % 2147483647)
    math.random()
    math.random()
    FugSchedulerRuntime.uuidSeeded = true
  end

  while true do
    FugSchedulerRuntime.uuidCounter = FugSchedulerRuntime.uuidCounter + 1
    local uuid = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(character)
      local value = math.random(0, 15)
      if character == "y" then value = (value % 4) + 8 end
      return string.format("%x", value)
    end)
    if not existing[uuid] then return uuid end
  end
end

-- Return a new, immediately valid disabled Scheduler with one empty Day and Week Pattern.
function FugSchedulerRuntime.newScheduler(id, label)
  local dayPatternId = "default-day"
  local weekPatternId = "default-week"
  return {
    id = id,
    label = label or "New Scheduler",
    enabled = false,
    paused = false,
    defaultWeekPatternId = weekPatternId,
    dayPatterns = {
      {id = dayPatternId, label = "Default Day", events = {}}
    },
    weekPatterns = {
      {
        id = weekPatternId,
        label = "Default Week",
        days = {
          Mon = dayPatternId, Tue = dayPatternId, Wed = dayPatternId,
          Thu = dayPatternId, Fri = dayPatternId, Sat = dayPatternId, Sun = dayPatternId
        }
      }
    },
    overrides = {}
  }
end

-- Compile trusted Action Provider source in its own globals table with Q-SYS globals available by fallback.
function FugSchedulerRuntime.compileSource(source)
  local environment = {}
  environment._G = environment
  setmetatable(environment, {__index = _G})

  local chunk = nil
  local compileError = nil

  if type(load) == "function" then
    local callOk, compiled, loadError = pcall(load, source, "FugScheduler ActionSource", "t", environment)
    if not callOk then return nil, "load() failed: " .. tostring(compiled) end
    chunk = compiled
    compileError = loadError
  elseif type(loadstring) == "function" then
    local callOk, compiled, loadError = pcall(loadstring, source, "FugScheduler ActionSource")
    if not callOk then return nil, "loadstring() failed: " .. tostring(compiled) end
    chunk = compiled
    compileError = loadError
    if chunk and type(setfenv) == "function" then
      setfenv(chunk, environment)
    elseif chunk then
      return nil, "loadstring() is available, but setfenv() is unavailable"
    end
  else
    return nil, "Q-SYS runtime provides neither load() nor loadstring()"
  end

  if not chunk then return nil, "Compile error: " .. tostring(compileError) end

  local executed, runtimeError = pcall(chunk)
  if not executed then return nil, "Source error: " .. tostring(runtimeError) end

  return environment, nil
end

-- Validate the provider result and build an atomic Action Registry.
function FugSchedulerRuntime.buildRegistry(actionDefinitions)
  if type(actionDefinitions) ~= "table" then
    return nil, nil, "GetFugSchedulerActions() must return a table"
  end

  local actionsById = {}
  local orderedActions = {}

  for index, definition in ipairs(actionDefinitions) do
    if type(definition) ~= "table" then
      return nil, nil, "Action " .. index .. " must be a table"
    end

    local id = definition.id
    if type(id) ~= "string" or id == "" then
      return nil, nil, "Action " .. index .. " requires a non-empty string id"
    end
    if actionsById[id] then return nil, nil, "Duplicate Action ID: " .. id end
    if type(definition.callback) ~= "function" then
      return nil, nil, "Action " .. id .. " requires a callback function"
    end
    if definition.label ~= nil and type(definition.label) ~= "string" then
      return nil, nil, "Action " .. id .. " label must be a string"
    end

    local action = {
      id = id,
      label = definition.label or id,
      description = definition.description,
      callback = definition.callback
    }
    actionsById[id] = action
    table.insert(orderedActions, action)
  end

  if #orderedActions == 0 then return nil, nil, "GetFugSchedulerActions() returned no Actions" end
  return actionsById, orderedActions, nil
end

-- Update the Action selector after a valid registry has been installed.
function FugSchedulerRuntime.refreshActionChoices()
  if not Controls.ActionSelect then return end

  local choices = {}
  local structuredChoices = {}
  for _, action in ipairs(FugSchedulerRuntime.orderedActions) do
    table.insert(choices, action.id)
    table.insert(structuredChoices, {Text = action.label, Id = action.id})
  end

  local previous = Controls.ActionSelect.String or ""
  Controls.ActionSelect.Choices = choices
  Controls.ActionSelect.String = FugSchedulerRuntime.actionsById[previous] and previous or (choices[1] or "")

  if Controls.EventActionPicker then
    local previousId = FugSchedulerRuntime.choiceId(Controls.EventActionPicker.String)
    Controls.EventActionPicker.Choices = structuredChoices
    if not FugSchedulerRuntime.actionsById[previousId] then
      previousId = FugSchedulerRuntime.orderedActions[1] and FugSchedulerRuntime.orderedActions[1].id or nil
    end
    if previousId then
      local action = FugSchedulerRuntime.actionsById[previousId]
      Controls.EventActionPicker.String = FugSchedulerRuntime.encodeChoice(action.label, action.id)
    else
      Controls.EventActionPicker.String = ""
    end
  end
end

-- Compile ActionSource and replace the Action Registry only after complete validation succeeds.
function FugSchedulerRuntime.reloadActions()
  local source = Controls.ActionSource and Controls.ActionSource.String or ""
  if source == "" then
    FugSchedulerRuntime.setText("RegistryStatus", "Waiting for ActionSource text")
    FugSchedulerRuntime.setText("RegisteredActionCount", tostring(#FugSchedulerRuntime.orderedActions))
    return false
  end

  local environment, compileError = FugSchedulerRuntime.compileSource(source)
  if not environment then
    FugSchedulerRuntime.setText("RegistryStatus", compileError)
    FugSchedulerRuntime.logLine(compileError)
    return false
  end

  local provider = environment.GetFugSchedulerActions
  if type(provider) ~= "function" then
    local message = "ActionSource must define GetFugSchedulerActions()"
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end

  local providerOk, actionDefinitions = pcall(provider)
  if not providerOk then
    local message = "Provider error: " .. tostring(actionDefinitions)
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end

  local actionsById, orderedActions, validationError = FugSchedulerRuntime.buildRegistry(actionDefinitions)
  if not actionsById then
    FugSchedulerRuntime.setText("RegistryStatus", validationError)
    FugSchedulerRuntime.logLine(validationError)
    return false
  end

  FugSchedulerRuntime.actionsById = actionsById
  FugSchedulerRuntime.orderedActions = orderedActions
  FugSchedulerRuntime.providerEnvironment = environment
  FugSchedulerRuntime.refreshActionChoices()
  FugSchedulerRuntime.setText("RegistryStatus", "Loaded " .. #orderedActions .. " Actions")
  FugSchedulerRuntime.setText("RegisteredActionCount", tostring(#orderedActions))
  FugSchedulerRuntime.logLine("Loaded Action Registry with " .. #orderedActions .. " Actions.")

  if FugSchedulerRuntime.scheduleInitialized and Controls.ScheduleData and Controls.ScheduleData.String ~= "" then
    FugSchedulerRuntime.reloadSchedule()
  end
  return true
end

-- Invoke the selected Action without allowing callback failure to stop the plugin.
function FugSchedulerRuntime.testSelectedAction()
  local id = Controls.ActionSelect and Controls.ActionSelect.String or ""
  local action = FugSchedulerRuntime.actionsById[id]
  if not action then
    local message = "No registered Action selected"
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message)
    return
  end

  local callbackOk, callbackError = pcall(action.callback)
  if callbackOk then
    local message = "Test succeeded: " .. action.label .. " [" .. action.id .. "]"
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message)
  else
    local message = "Callback error for " .. action.id .. ": " .. tostring(callbackError)
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message)
  end
end

-- Parse and validate a YYYY-MM-DD date using Core-local calendar rules.
function FugSchedulerRuntime.parseDate(dateText)
  if type(dateText) ~= "string" then return nil, "date must be a string" end
  local year, month, day = string.match(dateText, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year then return nil, "expected YYYY-MM-DD" end

  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  local timestamp = os.time({year = year, month = month, day = day, hour = 12, min = 0, sec = 0})
  if not timestamp or os.date("%Y-%m-%d", timestamp) ~= dateText then return nil, "invalid calendar date" end
  return timestamp, nil
end

-- Return the selected persistent date presentation preference, defaulting to ISO.
function FugSchedulerRuntime.dateFormatPreference()
  local value = Controls.DateFormatPreference and FugSchedulerRuntime.choiceId(Controls.DateFormatPreference.String) or nil
  if value == "DMY" or value == "MDY" or value == "ISO" then return value end
  return "ISO"
end

-- Parse a preference-formatted date and return canonical ISO text plus its local-midday timestamp.
function FugSchedulerRuntime.parseDisplayDate(dateText, format)
  if type(dateText) ~= "string" then return nil, nil, "Invalid date" end
  dateText = string.match(dateText, "^%s*(.-)%s*$") or dateText
  local year, month, day
  if format == "DMY" then
    day, month, year = string.match(dateText, "^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
  elseif format == "MDY" then
    month, day, year = string.match(dateText, "^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
  else
    year, month, day = string.match(dateText, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  end
  if not year then return nil, nil, "Invalid date" end

  local canonical = string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))
  local timestamp, parseError = FugSchedulerRuntime.parseDate(canonical)
  if not timestamp then return nil, nil, parseError == "invalid calendar date" and "Invalid date" or tostring(parseError) end
  return canonical, timestamp, nil
end

-- Format one canonical ISO date for the selected entry/display preference.
function FugSchedulerRuntime.formatDisplayDate(dateText, format)
  local timestamp = FugSchedulerRuntime.parseDate(dateText)
  if not timestamp then return "" end
  if format == "DMY" then return os.date("%d/%m/%Y", timestamp) end
  if format == "MDY" then return os.date("%m/%d/%Y", timestamp) end
  return os.date("%Y-%m-%d", timestamp)
end

-- Format one canonical ISO date with fixed English names and Core-local calendar fields.
function FugSchedulerRuntime.formatLongDate(dateText)
  local timestamp = FugSchedulerRuntime.parseDate(dateText)
  if not timestamp then return "Invalid date" end
  local parts = os.date("*t", timestamp)
  local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
  local months = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  }
  return string.format("%s, %02d %s %04d", weekdays[parts.wday], parts.day, months[parts.month], parts.year)
end

-- Return whole calendar-day distance using local midday timestamps to limit DST ambiguity.
function FugSchedulerRuntime.calendarDayDifference(startDate, endDate)
  local startTimestamp = FugSchedulerRuntime.parseDate(startDate)
  local endTimestamp = FugSchedulerRuntime.parseDate(endDate)
  if not startTimestamp or not endTimestamp then return nil end
  local elapsedDays = os.difftime(endTimestamp, startTimestamp) / 86400
  if elapsedDays >= 0 then return math.floor(elapsedDays + 0.5) end
  return math.ceil(elapsedDays - 0.5)
end

-- Parse and validate an HH:MM Event time and return hour, minute, and normalized minutes.
function FugSchedulerRuntime.parseEventTime(timeText)
  if type(timeText) ~= "string" then return nil, nil, nil, "time must be a string" end
  local hour, minute = string.match(timeText, "^(%d%d):(%d%d)$")
  if not hour then return nil, nil, nil, "expected HH:MM" end

  hour, minute = tonumber(hour), tonumber(minute)
  if hour > 23 or minute > 59 then return nil, nil, nil, "time is outside 00:00-23:59" end
  return hour, minute, (hour * 60) + minute, nil
end

-- Parse a test timestamp in YYYY-MM-DD HH:MM form, or return the current time when blank.
function FugSchedulerRuntime.parseDateTime(dateTimeText)
  if dateTimeText == nil or dateTimeText == "" then return os.time(), nil end
  if type(dateTimeText) ~= "string" then return nil, "date/time must be a string" end

  local dateText, timeText = string.match(dateTimeText, "^(%d%d%d%d%-%d%d%-%d%d) (%d%d:%d%d)$")
  if not dateText then return nil, "expected YYYY-MM-DD HH:MM" end

  local dateTimestamp, dateError = FugSchedulerRuntime.parseDate(dateText)
  if not dateTimestamp then return nil, dateError end
  local hour, minute, _, timeError = FugSchedulerRuntime.parseEventTime(timeText)
  if timeError then return nil, timeError end

  local parts = os.date("*t", dateTimestamp)
  return os.time({year = parts.year, month = parts.month, day = parts.day, hour = hour, min = minute, sec = 0}), nil
end

-- Shift a YYYY-MM-DD calendar date by whole local days.
function FugSchedulerRuntime.shiftDate(dateText, dayOffset)
  local timestamp = FugSchedulerRuntime.parseDate(dateText)
  if not timestamp then return nil end
  local parts = os.date("*t", timestamp)
  parts.day = parts.day + dayOffset
  parts.hour, parts.min, parts.sec = 12, 0, 0
  return os.date("%Y-%m-%d", os.time(parts))
end

-- Return the inclusive number of calendar dates in one valid canonical range.
function FugSchedulerRuntime.inclusiveRangeDays(startDate, endDate)
  local difference = FugSchedulerRuntime.calendarDayDifference(startDate, endDate)
  return difference and (difference + 1) or nil
end

-- Return true when two inclusive date ranges overlap.
function FugSchedulerRuntime.dateRangesOverlap(first, second)
  return first.startDate <= second.endDate and second.startDate <= first.endDate
end

-- Validate one Scheduler and build its private lookup indexes used by the resolver.
function FugSchedulerRuntime.validateScheduler(scheduler, schedulerIndex)
  local prefix = "Scheduler " .. schedulerIndex
  local warnings = {}
  local dayPatternsById = {}
  local weekPatternsById = {}
  local eventIds = {}
  local dayPatternLabels = {}
  local weekPatternLabels = {}

  if type(scheduler) ~= "table" then return nil, nil, prefix .. " must be an object" end
  if type(scheduler.id) ~= "string" or scheduler.id == "" then return nil, nil, prefix .. " requires a non-empty ID" end
  prefix = "Scheduler " .. scheduler.id
  if type(scheduler.dayPatterns) ~= "table" then return nil, nil, prefix .. " requires dayPatterns" end
  if type(scheduler.weekPatterns) ~= "table" then return nil, nil, prefix .. " requires weekPatterns" end
  if type(scheduler.overrides) ~= "table" then scheduler.overrides = {} end

  if type(scheduler.label) ~= "string" or scheduler.label == "" then
    return nil, nil, prefix .. " requires a non-empty label"
  end
  scheduler.enabled = scheduler.enabled ~= false
  scheduler.paused = scheduler.paused == true

  for dayIndex, dayPattern in ipairs(scheduler.dayPatterns) do
    if type(dayPattern) ~= "table" then return nil, nil, prefix .. " Day Pattern " .. dayIndex .. " must be an object" end
    if type(dayPattern.id) ~= "string" or dayPattern.id == "" then return nil, nil, prefix .. " Day Pattern " .. dayIndex .. " requires an ID" end
    if dayPatternsById[dayPattern.id] then return nil, nil, prefix .. " has duplicate Day Pattern ID: " .. dayPattern.id end
    if type(dayPattern.events) ~= "table" then return nil, nil, prefix .. " Day Pattern " .. dayPattern.id .. " requires Events" end
    if dayPattern.label == nil then dayPattern.label = dayPattern.id end
    if type(dayPattern.label) ~= "string" or dayPattern.label == "" then
      return nil, nil, prefix .. " Day Pattern " .. dayPattern.id .. " requires a non-empty label"
    end

    dayPatternLabels[dayPattern.label] = (dayPatternLabels[dayPattern.label] or 0) + 1
    if dayPatternLabels[dayPattern.label] == 2 then
      table.insert(warnings, prefix .. " has duplicate Day Pattern label: " .. dayPattern.label)
    end
    dayPattern._eventIds = {}
    dayPattern._eventsById = {}
    dayPatternsById[dayPattern.id] = dayPattern

    local times = {}
    for eventIndex, event in ipairs(dayPattern.events) do
      if type(event) ~= "table" then return nil, nil, prefix .. " Event " .. eventIndex .. " in " .. dayPattern.id .. " must be an object" end
      if type(event.id) ~= "string" or event.id == "" then return nil, nil, prefix .. " Event " .. eventIndex .. " in " .. dayPattern.id .. " requires an ID" end
      if eventIds[event.id] then return nil, nil, prefix .. " has duplicate Event ID: " .. event.id end
      eventIds[event.id] = true
      dayPattern._eventIds[event.id] = true
      dayPattern._eventsById[event.id] = event

      local _, _, minutes, timeError = FugSchedulerRuntime.parseEventTime(event.time)
      if timeError then return nil, nil, prefix .. " Event " .. event.id .. " has invalid time: " .. timeError end
      event._minutes = minutes
      event._order = eventIndex
      if event.label == nil then event.label = event.id end
      if type(event.label) ~= "string" or event.label == "" then
        return nil, nil, prefix .. " Event " .. event.id .. " requires a non-empty label"
      end
      if times[event.time] then table.insert(warnings, prefix .. " has duplicate Event time " .. event.time .. " in " .. dayPattern.id) end
      times[event.time] = true

      if type(event.actions) ~= "table" then event.actions = {} end
      if #event.actions == 0 then
        table.insert(warnings, prefix .. " Event " .. event.id .. " contains no Event Actions")
      else
        local assignedActionIds = {}
        for actionIndex, eventAction in ipairs(event.actions) do
          if type(eventAction) ~= "table" or type(eventAction.actionId) ~= "string" or eventAction.actionId == "" then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " in Event " .. event.id .. " requires an actionId"
          end
          if assignedActionIds[eventAction.actionId] then
            table.insert(warnings, prefix .. " Event " .. event.id .. " assigns Action " .. eventAction.actionId .. " more than once")
          end
          assignedActionIds[eventAction.actionId] = true
          if not FugSchedulerRuntime.actionsById[eventAction.actionId] then
            table.insert(warnings, prefix .. " Event " .. event.id .. " references unavailable Action " .. eventAction.actionId)
          end
        end
      end
    end
  end

  if next(dayPatternsById) == nil then return nil, nil, prefix .. " requires at least one Day Pattern" end

  for weekIndex, weekPattern in ipairs(scheduler.weekPatterns) do
    if type(weekPattern) ~= "table" then return nil, nil, prefix .. " Week Pattern " .. weekIndex .. " must be an object" end
    if type(weekPattern.id) ~= "string" or weekPattern.id == "" then return nil, nil, prefix .. " Week Pattern " .. weekIndex .. " requires an ID" end
    if weekPatternsById[weekPattern.id] then return nil, nil, prefix .. " has duplicate Week Pattern ID: " .. weekPattern.id end
    if type(weekPattern.days) ~= "table" then return nil, nil, prefix .. " Week Pattern " .. weekPattern.id .. " requires day assignments" end

    weekPattern.label = weekPattern.label or weekPattern.id
    if type(weekPattern.label) ~= "string" or weekPattern.label == "" then
      return nil, nil, prefix .. " Week Pattern " .. weekPattern.id .. " requires a non-empty label"
    end
    weekPatternLabels[weekPattern.label] = (weekPatternLabels[weekPattern.label] or 0) + 1
    if weekPatternLabels[weekPattern.label] == 2 then
      table.insert(warnings, prefix .. " has duplicate Week Pattern label: " .. weekPattern.label)
    end
    weekPatternsById[weekPattern.id] = weekPattern
    for _, weekday in ipairs(FugSchedulerWeekdays) do
      local dayPatternId = weekPattern.days[weekday.key]
      if type(dayPatternId) ~= "string" or not dayPatternsById[dayPatternId] then
        return nil, nil, prefix .. " Week Pattern " .. weekPattern.id .. " has invalid " .. weekday.key .. " Day Pattern"
      end
    end
  end

  if not weekPatternsById[scheduler.defaultWeekPatternId] then
    return nil, nil, prefix .. " Default Week Pattern does not exist: " .. tostring(scheduler.defaultWeekPatternId)
  end

  local overrideIds = {}
  local overrideLabels = {}
  for overrideIndex, override in ipairs(scheduler.overrides) do
    if type(override) ~= "table" then return nil, nil, prefix .. " Override " .. overrideIndex .. " must be an object" end
    if type(override.id) ~= "string" or override.id == "" then return nil, nil, prefix .. " Override " .. overrideIndex .. " requires an ID" end
    if overrideIds[override.id] then return nil, nil, prefix .. " has duplicate Override ID: " .. override.id end
    overrideIds[override.id] = true
    override.label = override.label or override.id
    if type(override.label) ~= "string" or override.label == "" then
      return nil, nil, prefix .. " Override " .. override.id .. " requires a non-empty label"
    end
    overrideLabels[override.label] = (overrideLabels[override.label] or 0) + 1
    if overrideLabels[override.label] == 2 then
      table.insert(warnings, prefix .. " has duplicate Override label: " .. override.label)
    end
    override.enabled = override.enabled ~= false

    local _, startError = FugSchedulerRuntime.parseDate(override.startDate)
    if startError then return nil, nil, prefix .. " Override " .. override.id .. " start date: " .. startError end
    local _, endError = FugSchedulerRuntime.parseDate(override.endDate)
    if endError then return nil, nil, prefix .. " Override " .. override.id .. " end date: " .. endError end
    if override.startDate > override.endDate then return nil, nil, prefix .. " Override " .. override.id .. " starts after it ends" end

    if override.type == "DayPattern" then
      if not dayPatternsById[override.patternId] then return nil, nil, prefix .. " Override " .. override.id .. " references a missing Day Pattern" end
    elseif override.type == "WeekPattern" then
      if not weekPatternsById[override.patternId] then return nil, nil, prefix .. " Override " .. override.id .. " references a missing Week Pattern" end
    else
      return nil, nil, prefix .. " Override " .. override.id .. " type must be DayPattern or WeekPattern"
    end
  end

  for firstIndex = 1, #scheduler.overrides do
    local first = scheduler.overrides[firstIndex]
    if first.enabled ~= false then
      for secondIndex = firstIndex + 1, #scheduler.overrides do
        local second = scheduler.overrides[secondIndex]
        if second.enabled ~= false and first.type == second.type and FugSchedulerRuntime.dateRangesOverlap(first, second) then
          table.insert(warnings, prefix .. " has overlapping " .. first.type .. " Overrides: " .. first.id .. " and " .. second.id)
        end
      end
    end
  end

  scheduler._dayPatternsById = dayPatternsById
  scheduler._weekPatternsById = weekPatternsById
  return scheduler, warnings, nil
end

-- Validate the multi-Scheduler root and build stable ID lookup indexes for runtime use.
function FugSchedulerRuntime.validateSchedule(root)
  if type(root) ~= "table" then return nil, nil, "ScheduleData must decode to an object" end
  if root.schemaVersion ~= 1 then return nil, nil, "ScheduleData schemaVersion must be 1" end
  if type(root.schedulers) ~= "table" or #root.schedulers == 0 then return nil, nil, "ScheduleData requires at least one Scheduler" end

  local warnings = {}
  local schedulersById = {}
  for schedulerIndex, scheduler in ipairs(root.schedulers) do
    local validatedScheduler, schedulerWarnings, schedulerError = FugSchedulerRuntime.validateScheduler(scheduler, schedulerIndex)
    if not validatedScheduler then return nil, nil, schedulerError end
    if schedulersById[validatedScheduler.id] then return nil, nil, "Duplicate Scheduler ID: " .. validatedScheduler.id end
    schedulersById[validatedScheduler.id] = validatedScheduler
    for _, warning in ipairs(schedulerWarnings) do table.insert(warnings, warning) end
  end

  root.revision = tonumber(root.revision) or 1
  root._schedulersById = schedulersById
  return root, warnings, nil
end

-- Resolve the Day Pattern and resolution source for one calendar date.
function FugSchedulerRuntime.resolveDayPattern(scheduler, dateText)
  local dateTimestamp = FugSchedulerRuntime.parseDate(dateText)
  local weekday = os.date("%a", dateTimestamp)

  for _, override in ipairs(scheduler.overrides) do
    if override.enabled ~= false and override.type == "DayPattern" and dateText >= override.startDate and dateText <= override.endDate then
      return scheduler._dayPatternsById[override.patternId], "Day Override: " .. override.label, {
        type = "DayPatternOverride", id = override.id, label = override.label
      }
    end
  end

  for _, override in ipairs(scheduler.overrides) do
    if override.enabled ~= false and override.type == "WeekPattern" and dateText >= override.startDate and dateText <= override.endDate then
      local weekPattern = scheduler._weekPatternsById[override.patternId]
      return scheduler._dayPatternsById[weekPattern.days[weekday]], "Week Override: " .. override.label, {
        type = "WeekPatternOverride", id = override.id, label = override.label, weekPatternId = weekPattern.id
      }
    end
  end

  local weekPattern = scheduler._weekPatternsById[scheduler.defaultWeekPatternId]
  return scheduler._dayPatternsById[weekPattern.days[weekday]], "Default Week Pattern: " .. weekPattern.label, {
    type = "DefaultWeekPattern", id = weekPattern.id, label = weekPattern.label
  }
end

-- Build an absolute Core-local timestamp for one Event on one date.
function FugSchedulerRuntime.eventTimestamp(dateText, timeText)
  local dateTimestamp = FugSchedulerRuntime.parseDate(dateText)
  local dateParts = os.date("*t", dateTimestamp)
  local hour, minute = FugSchedulerRuntime.parseEventTime(timeText)
  return os.time({year = dateParts.year, month = dateParts.month, day = dateParts.day, hour = hour, min = minute, sec = 0})
end

-- Collect and sort resolved Events around a target date for cross-midnight lookup.
function FugSchedulerRuntime.collectTimeline(scheduler, targetDate, radiusDays)
  local timeline = {}
  local sequence = 0

  for offset = -radiusDays, radiusDays do
    local dateText = FugSchedulerRuntime.shiftDate(targetDate, offset)
    local dayPattern = FugSchedulerRuntime.resolveDayPattern(scheduler, dateText)
    for _, event in ipairs(dayPattern.events) do
      sequence = sequence + 1
      table.insert(timeline, {
        timestamp = FugSchedulerRuntime.eventTimestamp(dateText, event.time),
        date = dateText,
        time = event.time,
        event = event,
        dayPattern = dayPattern,
        sequence = sequence
      })
    end
  end

  table.sort(timeline, function(first, second)
    if first.timestamp == second.timestamp then return first.sequence < second.sequence end
    return first.timestamp < second.timestamp
  end)
  return timeline
end

-- Resolve previous, current, and next Events for an explicit timestamp without executing Actions.
function FugSchedulerRuntime.resolveAt(scheduler, timestamp)
  local targetDate = os.date("%Y-%m-%d", timestamp)
  local resolvedDayPattern, resolutionSource, resolutionRule = FugSchedulerRuntime.resolveDayPattern(scheduler, targetDate)
  local timeline = FugSchedulerRuntime.collectTimeline(scheduler, targetDate, 31)
  local currentIndex = nil

  for index, item in ipairs(timeline) do
    if item.timestamp <= timestamp then currentIndex = index else break end
  end

  local previous = currentIndex and timeline[currentIndex - 1] or nil
  local current = currentIndex and timeline[currentIndex] or nil
  local nextEvent = currentIndex and timeline[currentIndex + 1] or timeline[1]

  return {
    timestamp = timestamp,
    targetDate = targetDate,
    resolvedDayPattern = resolvedDayPattern,
    resolutionSource = resolutionSource,
    resolutionRule = resolutionRule,
    previous = previous,
    current = current,
    next = nextEvent
  }
end

-- Format an Event occurrence for compact status display.
function FugSchedulerRuntime.formatEvent(item)
  if not item then return "None" end
  return item.event.label .. " [" .. item.date .. " " .. item.time .. "]"
end

-- Format the ordered Action IDs attached to an Event occurrence.
function FugSchedulerRuntime.formatEventActions(item)
  if not item or type(item.event.actions) ~= "table" or #item.event.actions == 0 then return "None" end
  local labels = {}
  for _, eventAction in ipairs(item.event.actions) do
    local action = FugSchedulerRuntime.actionsById[eventAction.actionId]
    table.insert(labels, action and action.label or (eventAction.actionId .. " (unavailable)"))
  end
  return table.concat(labels, " -> ")
end

-- Format a non-negative countdown from the resolved timestamp to the next Event.
function FugSchedulerRuntime.formatCountdown(fromTimestamp, nextTimestamp)
  if not nextTimestamp then return "N/A" end
  local seconds = math.max(0, math.floor(nextTimestamp - fromTimestamp))
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local remainingSeconds = seconds % 60
  if days > 0 then return string.format("%d days %02d:%02d:%02d", days, hours, minutes, remainingSeconds) end
  return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

-- Return the currently selected Scheduler, falling back to the first configured Scheduler.
function FugSchedulerRuntime.selectedScheduler()
  if not FugSchedulerRuntime.activeSchedule then return nil end
  local selectedId = FugSchedulerRuntime.selectedSchedulerId
  if not selectedId and Controls.SchedulerSelect then
    selectedId = FugSchedulerRuntime.choiceId(Controls.SchedulerSelect.String)
  end
  local scheduler = FugSchedulerRuntime.activeSchedule._schedulersById[selectedId]
  if scheduler then return scheduler end
  return FugSchedulerRuntime.activeSchedule.schedulers[1]
end

-- Populate the Scheduler selector from the persisted array while preserving stable ID selection.
function FugSchedulerRuntime.refreshSchedulerChoices()
  if not Controls.SchedulerSelect or not FugSchedulerRuntime.activeSchedule then return end

  local choices = {}
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
    table.insert(choices, {Text = scheduler.label, Id = scheduler.id})
  end
  Controls.SchedulerSelect.Choices = choices

  local selectedId = FugSchedulerRuntime.selectedSchedulerId
  if not selectedId then selectedId = FugSchedulerRuntime.choiceId(Controls.SchedulerSelect.String) end
  if not FugSchedulerRuntime.activeSchedule._schedulersById[selectedId] then
    selectedId = FugSchedulerRuntime.activeSchedule.schedulers[1].id
  end
  FugSchedulerRuntime.selectedSchedulerId = selectedId
  local selected = FugSchedulerRuntime.activeSchedule._schedulersById[selectedId]
  Controls.SchedulerSelect.String = FugSchedulerRuntime.encodeChoice(selected.label, selected.id)
end

-- Refresh all controls in the visual Scheduler editor from the selected valid model.
function FugSchedulerRuntime.refreshSchedulerEditor(message)
  if not FugSchedulerRuntime.activeSchedule then return end
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return end

  FugSchedulerRuntime.updatingSchedulerEditor = true
  if Controls.SchedulerLabel then Controls.SchedulerLabel.String = scheduler.label end
  if Controls.SchedulerEditorEnabled then Controls.SchedulerEditorEnabled.Boolean = scheduler.enabled end
  if Controls.SchedulerPaused then Controls.SchedulerPaused.Boolean = scheduler.paused end

  if Controls.SchedulerDefaultWeekPattern then
    local choices = {}
    for _, weekPattern in ipairs(scheduler.weekPatterns) do
      table.insert(choices, {Text = weekPattern.label, Id = weekPattern.id})
    end
    Controls.SchedulerDefaultWeekPattern.Choices = choices
    local selected = scheduler._weekPatternsById[scheduler.defaultWeekPatternId]
    Controls.SchedulerDefaultWeekPattern.String = FugSchedulerRuntime.encodeChoice(selected.label, selected.id)
  end
  if Controls.DeleteScheduler then Controls.DeleteScheduler.IsDisabled = #FugSchedulerRuntime.activeSchedule.schedulers <= 1 end
  FugSchedulerRuntime.updatingSchedulerEditor = false

  if message then FugSchedulerRuntime.setText("SchedulerEditorStatus", message) end
end

-- Return aggregate counts used by load and commit status messages.
function FugSchedulerRuntime.scheduleSummary(schedule, warningCount)
  local dayPatternCount, weekPatternCount, overrideCount = 0, 0, 0
  for _, scheduler in ipairs(schedule.schedulers) do
    dayPatternCount = dayPatternCount + #scheduler.dayPatterns
    weekPatternCount = weekPatternCount + #scheduler.weekPatterns
    overrideCount = overrideCount + #scheduler.overrides
  end
  return string.format(
    "%d Schedulers, %d Day Patterns, %d Week Patterns, %d Overrides; %d warnings",
    #schedule.schedulers,
    dayPatternCount,
    weekPatternCount,
    overrideCount,
    warningCount
  )
end

-- Atomically install a completely validated model and rebuild every derived view.
function FugSchedulerRuntime.installValidatedSchedule(validated, warnings, selectedId, statusPrefix)
  FugSchedulerRuntime.activeSchedule = validated
  FugSchedulerRuntime.scheduleWarnings = warnings or {}
  FugSchedulerRuntime.selectedSchedulerId = selectedId
  FugSchedulerRuntime.refreshSchedulerChoices()

  local summary = (statusPrefix or "Loaded") .. " " .. FugSchedulerRuntime.scheduleSummary(validated, #FugSchedulerRuntime.scheduleWarnings)
  FugSchedulerRuntime.setText("ScheduleStatus", summary)
  FugSchedulerRuntime.logLine(summary)
  for _, warning in ipairs(FugSchedulerRuntime.scheduleWarnings) do
    FugSchedulerRuntime.logLine("Schedule warning: " .. warning)
  end

  FugSchedulerRuntime.resolveSelectedTime()
  FugSchedulerRuntime.refreshSchedulerEditor(summary)
  FugSchedulerRuntime.refreshDayPatternEditor(summary)
  FugSchedulerRuntime.refreshWeekPatternEditor(summary)
  FugSchedulerRuntime.refreshOverrideEditor(summary)
  FugSchedulerRuntime.refreshStatus()
end

-- Apply one editor mutation to a clean candidate, then validate, serialize, persist, and install it.
function FugSchedulerRuntime.commitScheduleEdit(description, editFunction, selectedId, feedbackControl)
  feedbackControl = feedbackControl or "SchedulerEditorStatus"
  if not FugSchedulerRuntime.activeSchedule then
    FugSchedulerRuntime.setText(feedbackControl, "Edit rejected: no valid Schedule is loaded")
    return false
  end

  -- Restore every editor before publishing a transaction failure message.
  local function reject(message)
    FugSchedulerRuntime.logLine(message)
    FugSchedulerRuntime.refreshSchedulerEditor()
    FugSchedulerRuntime.refreshDayPatternEditor()
    FugSchedulerRuntime.refreshWeekPatternEditor()
    FugSchedulerRuntime.refreshOverrideEditor()
    FugSchedulerRuntime.setText(feedbackControl, message)
    return false
  end

  local candidate = FugSchedulerRuntime.copyPersisted(FugSchedulerRuntime.activeSchedule)
  local editOk, editResult, editError = pcall(editFunction, candidate)
  if not editOk then return reject("Edit rejected: " .. tostring(editResult)) end
  if editResult == false then return reject("Edit rejected: " .. tostring(editError or description)) end

  candidate.schemaVersion = 1
  candidate.revision = (tonumber(candidate.revision) or 0) + 1
  local validated, warnings, validationError = FugSchedulerRuntime.validateSchedule(candidate)
  if not validated then return reject("Edit rejected: " .. tostring(validationError)) end

  local persisted = FugSchedulerRuntime.copyPersisted(validated)
  FugSchedulerRuntime.normalizeScheduleArrays(persisted)
  local serialized = FugSchedulerRuntime.encodeJson(persisted)
  if serialized == "" then return reject("Edit rejected: schema-v1 JSON serialization failed") end

  FugSchedulerRuntime.writingScheduleData = true
  local writeOk, writeError = pcall(function() Controls.ScheduleData.String = serialized end)
  FugSchedulerRuntime.writingScheduleData = false
  if not writeOk then return reject("Edit rejected: ScheduleData write failed: " .. tostring(writeError)) end
  FugSchedulerRuntime.refreshLineViewer("ScheduleDataViewer", serialized)

  local targetId = selectedId or FugSchedulerRuntime.selectedSchedulerId
  FugSchedulerRuntime.installValidatedSchedule(validated, warnings, targetId, "Committed")
  local commitMessage = description .. " committed at revision " .. validated.revision
  if feedbackControl == "DayPatternEditorStatus" then
    FugSchedulerRuntime.refreshDayPatternEditor(commitMessage)
  elseif feedbackControl == "WeekPatternEditorStatus" then
    FugSchedulerRuntime.refreshWeekPatternEditor(commitMessage)
  elseif feedbackControl == "OverrideEditorStatus" then
    FugSchedulerRuntime.refreshOverrideEditor(commitMessage)
  else
    FugSchedulerRuntime.setText(feedbackControl, commitMessage)
  end
  return true
end

-- Return the selected Scheduler's array index in a persisted candidate model.
function FugSchedulerRuntime.selectedSchedulerIndex(candidate)
  local selectedId = FugSchedulerRuntime.selectedSchedulerId
  for index, scheduler in ipairs(candidate.schedulers) do
    if scheduler.id == selectedId then return index end
  end
  return nil
end

-- Return the item with a stable ID from an ordered schema collection.
function FugSchedulerRuntime.itemById(items, id)
  for _, item in ipairs(items or {}) do
    if item.id == id then return item end
  end
  return nil
end

-- Return a unique operator-facing label by adding a numeric suffix when needed.
function FugSchedulerRuntime.uniqueLabel(items, baseLabel)
  local used = {}
  for _, item in ipairs(items or {}) do used[item.label] = true end
  if not used[baseLabel] then return baseLabel end

  local suffix = 2
  while used[baseLabel .. " " .. suffix] do suffix = suffix + 1 end
  return baseLabel .. " " .. suffix
end

-- Return the selected Day Pattern in the current Scheduler, falling back to its first pattern.
function FugSchedulerRuntime.selectedDayPattern()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return nil, nil end

  local selectedId = FugSchedulerRuntime.selectedDayPatternIds[scheduler.id]
  if not selectedId and Controls.DayPatternSelect then
    selectedId = FugSchedulerRuntime.choiceId(Controls.DayPatternSelect.String)
  end
  local dayPattern = scheduler._dayPatternsById[selectedId]
  if not dayPattern then dayPattern = scheduler.dayPatterns[1] end
  if dayPattern then FugSchedulerRuntime.selectedDayPatternIds[scheduler.id] = dayPattern.id end
  return scheduler, dayPattern
end

-- Return the selected Event in the current Day Pattern, falling back to its first Event.
function FugSchedulerRuntime.selectedEvent()
  local scheduler, dayPattern = FugSchedulerRuntime.selectedDayPattern()
  if not dayPattern then return scheduler, nil, nil end

  local selectedId = FugSchedulerRuntime.selectedEventIds[scheduler.id]
  if not selectedId and Controls.EventSelect then
    selectedId = FugSchedulerRuntime.choiceId(Controls.EventSelect.String)
  end
  local event = dayPattern._eventsById[selectedId]
  if not event then event = dayPattern.events[1] end
  if event then FugSchedulerRuntime.selectedEventIds[scheduler.id] = event.id end
  return scheduler, dayPattern, event
end

-- Build a runtime-only key for the selected Event Action row.
function FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  if not scheduler or not event then return nil end
  return scheduler.id .. "\31" .. event.id
end

-- Return the currently selected Event Action row index when it still exists.
function FugSchedulerRuntime.selectedEventActionIndex()
  local scheduler, _, event = FugSchedulerRuntime.selectedEvent()
  if not event then return scheduler, event, nil end

  local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  local index = FugSchedulerRuntime.selectedEventActionIndexes[key]
  if not index and Controls.EventActionSelect then
    index = tonumber(FugSchedulerRuntime.choiceId(Controls.EventActionSelect.String))
  end
  if #event.actions == 0 then index = nil end
  if index and (index < 1 or index > #event.actions) then index = nil end
  if not index and #event.actions > 0 then index = 1 end
  FugSchedulerRuntime.selectedEventActionIndexes[key] = index
  return scheduler, event, index
end

-- Count every Week Pattern weekday and Override reference to one Day Pattern.
function FugSchedulerRuntime.dayPatternReferences(scheduler, dayPatternId)
  local weekdayCount = 0
  local weekPatternIds = {}
  local overrideCount = 0

  for _, weekPattern in ipairs(scheduler.weekPatterns or {}) do
    for _, weekday in ipairs({"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}) do
      if weekPattern.days[weekday] == dayPatternId then
        weekdayCount = weekdayCount + 1
        weekPatternIds[weekPattern.id] = true
      end
    end
  end
  for _, override in ipairs(scheduler.overrides or {}) do
    if override.type == "DayPattern" and override.patternId == dayPatternId then
      overrideCount = overrideCount + 1
    end
  end

  local weekPatternCount = 0
  for _ in pairs(weekPatternIds) do weekPatternCount = weekPatternCount + 1 end
  return {
    weekdayCount = weekdayCount,
    weekPatternCount = weekPatternCount,
    overrideCount = overrideCount,
    total = weekdayCount + overrideCount
  }
end

-- Return Events in chronological display order while preserving persisted row order for ties.
function FugSchedulerRuntime.sortedEventRows(dayPattern)
  local rows = {}
  for index, event in ipairs(dayPattern.events or {}) do
    table.insert(rows, {event = event, persistedIndex = index})
  end
  table.sort(rows, function(first, second)
    if first.event._minutes == second.event._minutes then
      return first.persistedIndex < second.persistedIndex
    end
    return first.event._minutes < second.event._minutes
  end)
  return rows
end

-- Enable or disable a declared control when it exists.
function FugSchedulerRuntime.setDisabled(name, disabled)
  if Controls[name] then Controls[name].IsDisabled = disabled == true end
end

-- Return warnings specific to the selected Day Pattern and Event editor context.
function FugSchedulerRuntime.dayPatternContextWarning(scheduler, dayPattern, event)
  local warnings = {}
  local labelMatches = 0
  for _, candidate in ipairs(scheduler.dayPatterns or {}) do
    if candidate.label == dayPattern.label then labelMatches = labelMatches + 1 end
  end
  if labelMatches > 1 then table.insert(warnings, "Duplicate Day Pattern label") end

  if event then
    local timeMatches = 0
    for _, candidate in ipairs(dayPattern.events or {}) do
      if candidate.time == event.time then timeMatches = timeMatches + 1 end
    end
    if timeMatches > 1 then
      table.insert(warnings, timeMatches .. " Events occur at " .. event.time .. "; persisted row order breaks ties")
    end
    if #event.actions == 0 then table.insert(warnings, "Selected Event has no Event Actions") end
  end
  return table.concat(warnings, " | ")
end

-- Refresh the three-column Day Pattern, Event, and Event Action editor.
function FugSchedulerRuntime.refreshDayPatternEditor(message)
  if not FugSchedulerRuntime.activeSchedule then return end
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return end

  FugSchedulerRuntime.updatingDayPatternEditor = true

  local dayPatternChoices = {}
  local labelCounts = {}
  local labelSeen = {}
  for _, dayPattern in ipairs(scheduler.dayPatterns) do
    labelCounts[dayPattern.label] = (labelCounts[dayPattern.label] or 0) + 1
  end
  for _, dayPattern in ipairs(scheduler.dayPatterns) do
    labelSeen[dayPattern.label] = (labelSeen[dayPattern.label] or 0) + 1
    local text = dayPattern.label
    if labelCounts[dayPattern.label] > 1 then text = text .. " (" .. labelSeen[dayPattern.label] .. ")" end
    table.insert(dayPatternChoices, {Text = text, Id = dayPattern.id})
  end
  if Controls.DayPatternSelect then Controls.DayPatternSelect.Choices = dayPatternChoices end

  local _, dayPattern = FugSchedulerRuntime.selectedDayPattern()
  if dayPattern and Controls.DayPatternSelect then
    local selectedText = dayPattern.label
    if labelCounts[dayPattern.label] > 1 then
      local ordinal = 0
      for _, candidate in ipairs(scheduler.dayPatterns) do
        if candidate.label == dayPattern.label then ordinal = ordinal + 1 end
        if candidate.id == dayPattern.id then break end
      end
      selectedText = selectedText .. " (" .. ordinal .. ")"
    end
    Controls.DayPatternSelect.String = FugSchedulerRuntime.encodeChoice(selectedText, dayPattern.id)
  end

  if Controls.DayPatternLabel then Controls.DayPatternLabel.String = dayPattern and dayPattern.label or "" end
  local eventActionCount = 0
  for _, event in ipairs(dayPattern and dayPattern.events or {}) do eventActionCount = eventActionCount + #event.actions end
  FugSchedulerRuntime.setText("DayPatternSummary", dayPattern and string.format("%d Events, %d Event Actions", #dayPattern.events, eventActionCount) or "No Day Pattern")

  local references = dayPattern and FugSchedulerRuntime.dayPatternReferences(scheduler, dayPattern.id) or {total = 0}
  if dayPattern then
    FugSchedulerRuntime.setText("DayPatternReferences", string.format(
      "Used by %d weekdays in %d Week Patterns; %d Overrides",
      references.weekdayCount,
      references.weekPatternCount,
      references.overrideCount
    ))
  else
    FugSchedulerRuntime.setText("DayPatternReferences", "")
  end

  local eventChoices = {}
  local eventTextCounts = {}
  local eventTextSeen = {}
  for _, row in ipairs(dayPattern and FugSchedulerRuntime.sortedEventRows(dayPattern) or {}) do
    local text = row.event.time .. "  " .. row.event.label
    eventTextCounts[text] = (eventTextCounts[text] or 0) + 1
  end
  for _, row in ipairs(dayPattern and FugSchedulerRuntime.sortedEventRows(dayPattern) or {}) do
    local text = row.event.time .. "  " .. row.event.label
    eventTextSeen[text] = (eventTextSeen[text] or 0) + 1
    if eventTextCounts[text] > 1 then text = text .. " (" .. eventTextSeen[text] .. ")" end
    table.insert(eventChoices, {Text = text, Id = row.event.id})
  end
  if Controls.EventSelect then Controls.EventSelect.Choices = eventChoices end

  local _, _, event = FugSchedulerRuntime.selectedEvent()
  if event and Controls.EventSelect then
    local selectedText = event.time .. "  " .. event.label
    if eventTextCounts[selectedText] and eventTextCounts[selectedText] > 1 then
      local ordinal = 0
      for _, row in ipairs(FugSchedulerRuntime.sortedEventRows(dayPattern)) do
        local text = row.event.time .. "  " .. row.event.label
        if text == selectedText then ordinal = ordinal + 1 end
        if row.event.id == event.id then break end
      end
      selectedText = selectedText .. " (" .. ordinal .. ")"
    end
    Controls.EventSelect.String = FugSchedulerRuntime.encodeChoice(selectedText, event.id)
  elseif Controls.EventSelect then
    Controls.EventSelect.String = ""
  end

  if Controls.EventLabel then Controls.EventLabel.String = event and event.label or "" end
  if Controls.EventTime then Controls.EventTime.String = event and event.time or "" end
  FugSchedulerRuntime.setText("EventSummary", event and (#event.actions .. " Actions") or "No Event")

  local actionChoices = {}
  if event then
    for index, eventAction in ipairs(event.actions) do
      local action = FugSchedulerRuntime.actionsById[eventAction.actionId]
      local label = action and action.label or (eventAction.actionId .. " (unavailable)")
      table.insert(actionChoices, {Text = index .. "  " .. label, Id = tostring(index)})
    end
  end
  if Controls.EventActionSelect then Controls.EventActionSelect.Choices = actionChoices end

  local _, _, actionIndex = FugSchedulerRuntime.selectedEventActionIndex()
  if event and actionIndex and Controls.EventActionSelect then
    local eventAction = event.actions[actionIndex]
    local action = FugSchedulerRuntime.actionsById[eventAction.actionId]
    local label = action and action.label or (eventAction.actionId .. " (unavailable)")
    Controls.EventActionSelect.String = FugSchedulerRuntime.encodeChoice(actionIndex .. "  " .. label, tostring(actionIndex))
  elseif Controls.EventActionSelect then
    Controls.EventActionSelect.String = ""
  end

  FugSchedulerRuntime.setDisabled("DayPatternLabel", not dayPattern)
  FugSchedulerRuntime.setDisabled("DuplicateDayPattern", not dayPattern)
  FugSchedulerRuntime.setDisabled("DeleteDayPattern", not dayPattern or references.total > 0 or #scheduler.dayPatterns <= 1)
  FugSchedulerRuntime.setDisabled("EventSelect", not dayPattern or #dayPattern.events == 0)
  FugSchedulerRuntime.setDisabled("EventLabel", not event)
  FugSchedulerRuntime.setDisabled("EventTime", not event)
  FugSchedulerRuntime.setDisabled("AddEvent", not dayPattern)
  FugSchedulerRuntime.setDisabled("DuplicateEvent", not event)
  FugSchedulerRuntime.setDisabled("DeleteEvent", not event)
  FugSchedulerRuntime.setDisabled("EventActionSelect", not event or #event.actions == 0)
  FugSchedulerRuntime.setDisabled("EventActionPicker", not event or #FugSchedulerRuntime.orderedActions == 0)
  FugSchedulerRuntime.setDisabled("AddEventAction", not event or #FugSchedulerRuntime.orderedActions == 0)
  FugSchedulerRuntime.setDisabled("DeleteEventAction", not actionIndex)
  FugSchedulerRuntime.setDisabled("MoveEventActionUp", not actionIndex or actionIndex <= 1)
  FugSchedulerRuntime.setDisabled("MoveEventActionDown", not actionIndex or actionIndex >= #(event and event.actions or {}))

  FugSchedulerRuntime.updatingDayPatternEditor = false

  local contextWarning = dayPattern and FugSchedulerRuntime.dayPatternContextWarning(scheduler, dayPattern, event) or ""
  if message and contextWarning ~= "" then
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message .. " | " .. contextWarning)
  elseif message then
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message)
  elseif contextWarning ~= "" then
    FugSchedulerRuntime.setText("DayPatternEditorStatus", contextWarning)
  end
end

-- Return the selected Week Pattern in the current Scheduler, falling back to its first pattern.
function FugSchedulerRuntime.selectedWeekPattern()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return nil, nil end

  local selectedId = FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id]
  if not selectedId and Controls.WeekPatternSelect then
    selectedId = FugSchedulerRuntime.choiceId(Controls.WeekPatternSelect.String)
  end
  local weekPattern = scheduler._weekPatternsById[selectedId]
  if not weekPattern then weekPattern = scheduler.weekPatterns[1] end
  if weekPattern then FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id] = weekPattern.id end
  return scheduler, weekPattern
end

-- Count Scheduler-default and Override references to one Week Pattern, including disabled Overrides.
function FugSchedulerRuntime.weekPatternReferences(scheduler, weekPatternId)
  local overrideCount = 0
  for _, override in ipairs(scheduler.overrides or {}) do
    if override.type == "WeekPattern" and override.patternId == weekPatternId then
      overrideCount = overrideCount + 1
    end
  end
  return {
    isDefault = scheduler.defaultWeekPatternId == weekPatternId,
    overrideCount = overrideCount
  }
end

-- Build structured choices with duplicate labels disambiguated by display order, never by ID.
function FugSchedulerRuntime.labeledChoices(items)
  local choices = {}
  local labelCounts = {}
  local labelSeen = {}
  for _, item in ipairs(items or {}) do labelCounts[item.label] = (labelCounts[item.label] or 0) + 1 end
  for _, item in ipairs(items or {}) do
    labelSeen[item.label] = (labelSeen[item.label] or 0) + 1
    local text = item.label
    if labelCounts[item.label] > 1 then text = text .. " (" .. labelSeen[item.label] .. ")" end
    table.insert(choices, {Text = text, Id = item.id})
  end
  return choices, labelCounts
end

-- Return the disambiguated display text for one selected labeled item.
function FugSchedulerRuntime.labeledChoiceText(items, selected, labelCounts)
  if not selected then return "" end
  if not labelCounts or (labelCounts[selected.label] or 0) <= 1 then return selected.label end
  local ordinal = 0
  for _, item in ipairs(items or {}) do
    if item.label == selected.label then ordinal = ordinal + 1 end
    if item.id == selected.id then break end
  end
  return selected.label .. " (" .. ordinal .. ")"
end

-- Return warnings specific to the selected Week Pattern editor context.
function FugSchedulerRuntime.weekPatternContextWarning(scheduler, weekPattern)
  local labelMatches = 0
  for _, candidate in ipairs(scheduler.weekPatterns or {}) do
    if candidate.label == weekPattern.label then labelMatches = labelMatches + 1 end
  end
  if labelMatches > 1 then return "Duplicate Week Pattern label" end
  return ""
end

-- Refresh the Week Pattern list, label, references, and seven structured Day Pattern selectors.
function FugSchedulerRuntime.refreshWeekPatternEditor(message)
  if not FugSchedulerRuntime.activeSchedule then return end
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return end

  FugSchedulerRuntime.updatingWeekPatternEditor = true
  local weekChoices, weekLabelCounts = FugSchedulerRuntime.labeledChoices(scheduler.weekPatterns)
  if Controls.WeekPatternSelect then Controls.WeekPatternSelect.Choices = weekChoices end

  local _, weekPattern = FugSchedulerRuntime.selectedWeekPattern()
  if weekPattern and Controls.WeekPatternSelect then
    Controls.WeekPatternSelect.String = FugSchedulerRuntime.encodeChoice(
      FugSchedulerRuntime.labeledChoiceText(scheduler.weekPatterns, weekPattern, weekLabelCounts),
      weekPattern.id
    )
  elseif Controls.WeekPatternSelect then
    Controls.WeekPatternSelect.String = ""
  end

  if Controls.WeekPatternLabel then Controls.WeekPatternLabel.String = weekPattern and weekPattern.label or "" end
  local references = weekPattern and FugSchedulerRuntime.weekPatternReferences(scheduler, weekPattern.id) or {isDefault = false, overrideCount = 0}
  local referenceSummary = "No Week Pattern"
  if weekPattern then
    if references.isDefault then
      referenceSummary = "Scheduler default; used by " .. references.overrideCount .. " Overrides"
    elseif references.overrideCount > 0 then
      referenceSummary = "Not default; used by " .. references.overrideCount .. " Overrides"
    else
      referenceSummary = "Not referenced"
    end
  end
  FugSchedulerRuntime.setText("WeekPatternReferences", referenceSummary)

  local dayChoices, dayLabelCounts = FugSchedulerRuntime.labeledChoices(scheduler.dayPatterns)
  for _, weekday in ipairs(FugSchedulerWeekdays) do
    local control = Controls[weekday.controlName]
    if control then
      control.Choices = dayChoices
      local dayPattern = weekPattern and scheduler._dayPatternsById[weekPattern.days[weekday.key]] or nil
      if dayPattern then
        control.String = FugSchedulerRuntime.encodeChoice(
          FugSchedulerRuntime.labeledChoiceText(scheduler.dayPatterns, dayPattern, dayLabelCounts),
          dayPattern.id
        )
      else
        control.String = ""
      end
      control.IsDisabled = not weekPattern
    end
  end

  FugSchedulerRuntime.setDisabled("WeekPatternLabel", not weekPattern)
  FugSchedulerRuntime.setDisabled("DuplicateWeekPattern", not weekPattern)
  FugSchedulerRuntime.setDisabled(
    "DeleteWeekPattern",
    not weekPattern or references.isDefault or references.overrideCount > 0 or #scheduler.weekPatterns <= 1
  )
  FugSchedulerRuntime.updatingWeekPatternEditor = false

  local contextWarning = weekPattern and FugSchedulerRuntime.weekPatternContextWarning(scheduler, weekPattern) or ""
  if message and contextWarning ~= "" then
    FugSchedulerRuntime.setText("WeekPatternEditorStatus", message .. " | " .. contextWarning)
  elseif message then
    FugSchedulerRuntime.setText("WeekPatternEditorStatus", message)
  elseif contextWarning ~= "" then
    FugSchedulerRuntime.setText("WeekPatternEditorStatus", contextWarning)
  end
end

-- Return the selected Week Pattern and its index from a persisted candidate model.
function FugSchedulerRuntime.candidateSelectedWeekPattern(candidate)
  local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
  if not schedulerIndex then return nil, nil, nil end
  local scheduler = candidate.schedulers[schedulerIndex]
  local selectedId = FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id]
  for index, weekPattern in ipairs(scheduler.weekPatterns) do
    if weekPattern.id == selectedId then return scheduler, weekPattern, index end
  end
  return scheduler, nil, nil
end

-- Add a Week Pattern with a Scheduler-scoped UUID and the first Day Pattern assigned to every weekday.
function FugSchedulerRuntime.addWeekPattern()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler or not scheduler.dayPatterns[1] then return false end
  local existing = {}
  for _, weekPattern in ipairs(scheduler.weekPatterns) do existing[weekPattern.id] = true end
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.weekPatterns, "New Week Pattern")
  local firstDayPatternId = scheduler.dayPatterns[1].id
  FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Week Pattern added", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    local days = {}
    for _, weekday in ipairs(FugSchedulerWeekdays) do days[weekday.key] = firstDayPatternId end
    table.insert(candidate.schedulers[schedulerIndex].weekPatterns, {id = id, label = label, days = days})
  end, nil, "WeekPatternEditorStatus")
end

-- Duplicate the selected Week Pattern with a fresh ID and independent weekday assignments.
function FugSchedulerRuntime.duplicateWeekPattern()
  local scheduler, source = FugSchedulerRuntime.selectedWeekPattern()
  if not source then return false end
  local existing = {}
  for _, weekPattern in ipairs(scheduler.weekPatterns) do existing[weekPattern.id] = true end
  local sourceId = source.id
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.weekPatterns, source.label .. " Copy")
  FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Week Pattern duplicated", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    local candidateScheduler = candidate.schedulers[schedulerIndex]
    for index, weekPattern in ipairs(candidateScheduler.weekPatterns) do
      if weekPattern.id == sourceId then
        local duplicate = FugSchedulerRuntime.copyPersisted(weekPattern)
        duplicate.id = id
        duplicate.label = label
        table.insert(candidateScheduler.weekPatterns, index + 1, duplicate)
        return
      end
    end
    return false, "selected Week Pattern no longer exists"
  end, nil, "WeekPatternEditorStatus")
end

-- Delete only a non-default, unreferenced Week Pattern while retaining a neighboring selection.
function FugSchedulerRuntime.deleteWeekPattern()
  local scheduler, source = FugSchedulerRuntime.selectedWeekPattern()
  if not source then return false end
  local references = FugSchedulerRuntime.weekPatternReferences(scheduler, source.id)
  local message = nil
  if references.isDefault then
    message = "Delete rejected: Week Pattern is the Scheduler default"
  elseif references.overrideCount > 0 then
    message = "Delete rejected: Week Pattern is used by " .. references.overrideCount .. " Overrides"
  elseif #scheduler.weekPatterns <= 1 then
    message = "Delete rejected: at least one Week Pattern is required"
  end
  if message then
    FugSchedulerRuntime.logLine(message)
    FugSchedulerRuntime.refreshWeekPatternEditor()
    FugSchedulerRuntime.setText("WeekPatternEditorStatus", message)
    return false
  end

  local sourceId = source.id
  local sourceIndex = nil
  for index, weekPattern in ipairs(scheduler.weekPatterns) do
    if weekPattern.id == source.id then sourceIndex = index break end
  end
  local nextIndex = math.min(sourceIndex or 1, #scheduler.weekPatterns - 1)
  local nextPattern = scheduler.weekPatterns[nextIndex]
  if nextPattern.id == source.id then nextPattern = scheduler.weekPatterns[nextIndex + 1] end
  FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id] = nextPattern.id

  return FugSchedulerRuntime.commitScheduleEdit("Week Pattern deleted", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    local candidatePatterns = candidate.schedulers[schedulerIndex].weekPatterns
    for index, weekPattern in ipairs(candidatePatterns) do
      if weekPattern.id == sourceId then
        table.remove(candidatePatterns, index)
        return
      end
    end
    return false, "selected Week Pattern no longer exists"
  end, nil, "WeekPatternEditorStatus")
end

-- Return the selected Override in the current Scheduler, falling back to its first row.
function FugSchedulerRuntime.selectedOverride()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return nil, nil, nil end

  local selectedId = FugSchedulerRuntime.selectedOverrideIds[scheduler.id]
  if not selectedId and Controls.OverrideSelect then
    selectedId = FugSchedulerRuntime.choiceId(Controls.OverrideSelect.String)
  end
  for index, override in ipairs(scheduler.overrides or {}) do
    if override.id == selectedId then
      FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = override.id
      return scheduler, override, index
    end
  end
  local override = scheduler.overrides and scheduler.overrides[1] or nil
  if override then FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = override.id end
  return scheduler, override, override and 1 or nil
end

-- Return the selected Override and its index from a persisted candidate model.
function FugSchedulerRuntime.candidateSelectedOverride(candidate)
  local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
  if not schedulerIndex then return nil, nil, nil end
  local scheduler = candidate.schedulers[schedulerIndex]
  local selectedId = FugSchedulerRuntime.selectedOverrideIds[scheduler.id]
  for index, override in ipairs(scheduler.overrides or {}) do
    if override.id == selectedId then return scheduler, override, index end
  end
  return scheduler, nil, nil
end

-- Count the selected Override's same-type priority and enabled overlaps.
function FugSchedulerRuntime.overrideContext(scheduler, selected)
  local priority, typeCount, overlapCount, labelMatches = 0, 0, 0, 0
  for _, override in ipairs(scheduler.overrides or {}) do
    if override.label == selected.label then labelMatches = labelMatches + 1 end
    if override.type == selected.type then
      typeCount = typeCount + 1
      if override.id == selected.id then priority = typeCount end
      if override.id ~= selected.id and selected.enabled and override.enabled and
          FugSchedulerRuntime.dateRangesOverlap(selected, override) then
        overlapCount = overlapCount + 1
      end
    end
  end
  return priority, typeCount, overlapCount, labelMatches
end

-- Return a stable runtime-only key for the selected Override date buffer.
function FugSchedulerRuntime.overrideDateBufferKey(scheduler, override)
  if not scheduler or not override then return nil end
  return scheduler.id .. "\31" .. override.id
end

-- Ensure the narrow date edit buffer targets the selected Override and selected format.
function FugSchedulerRuntime.ensureOverrideDateBuffer(scheduler, override)
  if not scheduler or not override then
    FugSchedulerRuntime.overrideDateBuffer = nil
    return nil
  end
  local key = FugSchedulerRuntime.overrideDateBufferKey(scheduler, override)
  local format = FugSchedulerRuntime.dateFormatPreference()
  local buffer = FugSchedulerRuntime.overrideDateBuffer
  if not buffer or buffer.key ~= key or buffer.format ~= format then
    buffer = {
      key = key,
      format = format,
      startText = FugSchedulerRuntime.formatDisplayDate(override.startDate, format),
      endText = FugSchedulerRuntime.formatDisplayDate(override.endDate, format),
      startError = nil,
      endError = nil
    }
    FugSchedulerRuntime.overrideDateBuffer = buffer
  end
  return buffer
end

-- Refresh buffered date entry, long-form resolution, validation, and inclusive range summary controls.
function FugSchedulerRuntime.refreshOverrideDateDisplays(scheduler, override)
  local buffer = FugSchedulerRuntime.ensureOverrideDateBuffer(scheduler, override)
  if not override or not buffer then
    FugSchedulerRuntime.setText("OverrideStartDateLongForm", "")
    FugSchedulerRuntime.setText("OverrideStartDateValidation", "")
    FugSchedulerRuntime.setText("OverrideEndDateLongForm", "")
    FugSchedulerRuntime.setText("OverrideEndDateValidation", "")
    FugSchedulerRuntime.setText("OverrideRangeSummary", "No Override selected")
    return
  end

  if Controls.OverrideStartDate then Controls.OverrideStartDate.String = buffer.startText end
  if Controls.OverrideEndDate then Controls.OverrideEndDate.String = buffer.endText end
  FugSchedulerRuntime.setText(
    "OverrideStartDateLongForm",
    buffer.startError and "" or FugSchedulerRuntime.formatLongDate(override.startDate)
  )
  FugSchedulerRuntime.setText("OverrideStartDateValidation", buffer.startError or "")
  FugSchedulerRuntime.setText(
    "OverrideEndDateLongForm",
    buffer.endError and "" or FugSchedulerRuntime.formatLongDate(override.endDate)
  )
  FugSchedulerRuntime.setText("OverrideEndDateValidation", buffer.endError or "")

  local days = FugSchedulerRuntime.inclusiveRangeDays(override.startDate, override.endDate) or 0
  FugSchedulerRuntime.setText("OverrideRangeSummary", string.format(
    "%d day%s inclusive\n%s – %s",
    days,
    days == 1 and "" or "s",
    FugSchedulerRuntime.formatLongDate(override.startDate),
    FugSchedulerRuntime.formatLongDate(override.endDate)
  ))
end

-- Keep invalid date text visible without changing the active model or resolver state.
function FugSchedulerRuntime.rejectBufferedOverrideDate(field, message)
  local scheduler, override = FugSchedulerRuntime.selectedOverride()
  local buffer = FugSchedulerRuntime.ensureOverrideDateBuffer(scheduler, override)
  if not buffer then return false end
  if field == "start" then buffer.startError = message else buffer.endError = message end
  FugSchedulerRuntime.updatingOverrideEditor = true
  FugSchedulerRuntime.refreshOverrideDateDisplays(scheduler, override)
  FugSchedulerRuntime.updatingOverrideEditor = false
  local fieldLabel = field == "start" and "Start date" or "End date"
  FugSchedulerRuntime.setText("OverrideEditorStatus", fieldLabel .. ": " .. message)
  return false
end

-- Commit a complete canonical Override range through the existing atomic transaction path.
function FugSchedulerRuntime.commitOverrideRange(description, startDate, endDate)
  FugSchedulerRuntime.overrideDateBuffer = nil
  return FugSchedulerRuntime.commitScheduleEdit(description, function(candidate)
    local _, override = FugSchedulerRuntime.candidateSelectedOverride(candidate)
    if not override then return false, "selected Override no longer exists" end
    override.startDate = startDate
    override.endDate = endDate
  end, nil, "OverrideEditorStatus")
end

-- Apply buffered Start text while preserving the existing inclusive range duration.
function FugSchedulerRuntime.editOverrideStartDate(dateText)
  local scheduler, override = FugSchedulerRuntime.selectedOverride()
  if not override then return FugSchedulerRuntime.rejectBufferedOverrideDate("start", "No Override is selected") end
  local buffer = FugSchedulerRuntime.ensureOverrideDateBuffer(scheduler, override)
  buffer.startText = dateText
  buffer.startError = nil
  local startDate = FugSchedulerRuntime.parseDisplayDate(dateText, buffer.format)
  if not startDate then
    return FugSchedulerRuntime.rejectBufferedOverrideDate("start", "Invalid date")
  end
  local durationOffset = FugSchedulerRuntime.calendarDayDifference(override.startDate, override.endDate)
  local endDate = durationOffset and FugSchedulerRuntime.shiftDate(startDate, durationOffset) or nil
  if not endDate then return FugSchedulerRuntime.rejectBufferedOverrideDate("start", "Invalid date") end
  return FugSchedulerRuntime.commitOverrideRange("Override range start updated", startDate, endDate)
end

-- Apply buffered End text only when it resolves on or after the persisted Start date.
function FugSchedulerRuntime.editOverrideEndDate(dateText)
  local scheduler, override = FugSchedulerRuntime.selectedOverride()
  if not override then return FugSchedulerRuntime.rejectBufferedOverrideDate("end", "No Override is selected") end
  local buffer = FugSchedulerRuntime.ensureOverrideDateBuffer(scheduler, override)
  buffer.endText = dateText
  buffer.endError = nil
  local endDate = FugSchedulerRuntime.parseDisplayDate(dateText, buffer.format)
  if not endDate then return FugSchedulerRuntime.rejectBufferedOverrideDate("end", "Invalid date") end
  if endDate < override.startDate then
    return FugSchedulerRuntime.rejectBufferedOverrideDate("end", "End date must not be before Start date")
  end
  return FugSchedulerRuntime.commitOverrideRange("Override range end updated", override.startDate, endDate)
end

-- Move Start by whole calendar days while preserving the complete range duration.
function FugSchedulerRuntime.shiftOverrideStart(dayOffset)
  local _, override = FugSchedulerRuntime.selectedOverride()
  if not override then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Start date change rejected: no Override is selected")
    return false
  end
  local startDate = FugSchedulerRuntime.shiftDate(override.startDate, dayOffset)
  local endDate = FugSchedulerRuntime.shiftDate(override.endDate, dayOffset)
  if not startDate or not endDate then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Start date change rejected: invalid persisted range")
    return false
  end
  return FugSchedulerRuntime.commitOverrideRange("Override Start date shifted", startDate, endDate)
end

-- Change the selected range duration by moving only its End date by whole calendar days.
function FugSchedulerRuntime.shiftOverrideRange(dayOffset)
  local _, override = FugSchedulerRuntime.selectedOverride()
  if not override then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Duration change rejected: no Override is selected")
    return false
  end
  local endDate = FugSchedulerRuntime.shiftDate(override.endDate, dayOffset)
  if not endDate then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Duration change rejected: invalid persisted range")
    return false
  end
  if endDate < override.startDate then
    FugSchedulerRuntime.refreshOverrideEditor()
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Duration change rejected: range is already 1 day")
    return false
  end
  local description = dayOffset < 0 and "Override duration shortened" or "Override duration extended"
  return FugSchedulerRuntime.commitOverrideRange(description, override.startDate, endDate)
end

-- Move the selected range to today's Core-local date while preserving duration.
function FugSchedulerRuntime.setOverrideRangeToday()
  local _, override = FugSchedulerRuntime.selectedOverride()
  if not override then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Today rejected: no Override is selected")
    return false
  end
  local durationOffset = FugSchedulerRuntime.calendarDayDifference(override.startDate, override.endDate)
  local startDate = os.date("%Y-%m-%d")
  local endDate = durationOffset and FugSchedulerRuntime.shiftDate(startDate, durationOffset) or nil
  if not endDate then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "Today rejected: invalid persisted range")
    return false
  end
  return FugSchedulerRuntime.commitOverrideRange("Override range moved to Today", startDate, endDate)
end

-- Collapse the selected range to one inclusive calendar date.
function FugSchedulerRuntime.setOverrideRangeOneDay()
  local _, override = FugSchedulerRuntime.selectedOverride()
  if not override then
    FugSchedulerRuntime.setText("OverrideEditorStatus", "1 Day rejected: no Override is selected")
    return false
  end
  return FugSchedulerRuntime.commitOverrideRange("Override range set to 1 Day", override.startDate, override.startDate)
end

-- Refresh the Override list, detail controls, ordering state, and warning summary.
function FugSchedulerRuntime.refreshOverrideEditor(message)
  if not FugSchedulerRuntime.activeSchedule then return end
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return end

  FugSchedulerRuntime.updatingOverrideEditor = true
  local overrideChoices, overrideLabelCounts = FugSchedulerRuntime.labeledChoices(scheduler.overrides)
  if Controls.OverrideSelect then Controls.OverrideSelect.Choices = overrideChoices end

  local _, override, overrideIndex = FugSchedulerRuntime.selectedOverride()
  if override and Controls.OverrideSelect then
    Controls.OverrideSelect.String = FugSchedulerRuntime.encodeChoice(
      FugSchedulerRuntime.labeledChoiceText(scheduler.overrides, override, overrideLabelCounts),
      override.id
    )
  elseif Controls.OverrideSelect then
    Controls.OverrideSelect.String = ""
  end

  if Controls.OverrideLabel then Controls.OverrideLabel.String = override and override.label or "" end
  if Controls.OverrideEnabled then Controls.OverrideEnabled.Boolean = override and override.enabled or false end
  FugSchedulerRuntime.refreshOverrideDateDisplays(scheduler, override)

  if Controls.OverrideType then
    Controls.OverrideType.Choices = {
      {Text = "Day Pattern", Id = "DayPattern"},
      {Text = "Week Pattern", Id = "WeekPattern"}
    }
    if override then
      local typeText = override.type == "WeekPattern" and "Week Pattern" or "Day Pattern"
      Controls.OverrideType.String = FugSchedulerRuntime.encodeChoice(typeText, override.type)
    else
      Controls.OverrideType.String = ""
    end
  end

  if Controls.OverridePattern then
    local patterns = override and (override.type == "WeekPattern" and scheduler.weekPatterns or scheduler.dayPatterns) or {}
    local patternChoices, patternLabelCounts = FugSchedulerRuntime.labeledChoices(patterns)
    Controls.OverridePattern.Choices = patternChoices
    local pattern = nil
    if override then
      pattern = override.type == "WeekPattern" and scheduler._weekPatternsById[override.patternId]
        or scheduler._dayPatternsById[override.patternId]
    end
    Controls.OverridePattern.String = pattern and FugSchedulerRuntime.encodeChoice(
      FugSchedulerRuntime.labeledChoiceText(patterns, pattern, patternLabelCounts),
      pattern.id
    ) or ""
  end

  local contextWarning = ""
  if override then
    local priority, typeCount, overlapCount, labelMatches = FugSchedulerRuntime.overrideContext(scheduler, override)
    local typeLabel = override.type == "WeekPattern" and "Week Pattern" or "Day Pattern"
    local stateSummary = string.format("Priority %d of %d; %s", priority, typeCount, override.enabled and "enabled" or "disabled")
    local overlapSummary
    if not override.enabled then
      overlapSummary = "Disabled; no active overlaps"
    elseif overlapCount > 0 then
      overlapSummary = string.format("Overlaps %d enabled %s Override%s", overlapCount, typeLabel, overlapCount == 1 and "" or "s")
    else
      overlapSummary = "No enabled same-type overlaps"
    end
    FugSchedulerRuntime.setText("OverrideSummary", stateSummary .. " | " .. overlapSummary)
    if labelMatches > 1 then contextWarning = "Duplicate Override label" end
  else
    FugSchedulerRuntime.setText("OverrideSummary", "No Overrides configured")
  end

  local noOverride = override == nil
  FugSchedulerRuntime.setDisabled("OverrideSelect", noOverride)
  FugSchedulerRuntime.setDisabled("OverrideLabel", noOverride)
  FugSchedulerRuntime.setDisabled("OverrideEnabled", noOverride)
  FugSchedulerRuntime.setDisabled("OverrideType", noOverride)
  FugSchedulerRuntime.setDisabled("OverrideStartDate", noOverride)
  FugSchedulerRuntime.setDisabled("OverrideEndDate", noOverride)
  FugSchedulerRuntime.setDisabled("OverridePattern", noOverride)
  local durationOffset = override and FugSchedulerRuntime.calendarDayDifference(override.startDate, override.endDate) or nil
  FugSchedulerRuntime.setDisabled("SetOverrideRangeToday", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideStartBackDay", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideStartForwardDay", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideStartBackWeek", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideStartForwardWeek", noOverride)
  FugSchedulerRuntime.setDisabled("SetOverrideRangeOneDay", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideRangeBack", noOverride or durationOffset == 0)
  FugSchedulerRuntime.setDisabled("ShiftOverrideRangeForward", noOverride)
  FugSchedulerRuntime.setDisabled("ShiftOverrideEndBackWeek", noOverride or not durationOffset or durationOffset < 7)
  FugSchedulerRuntime.setDisabled("ShiftOverrideEndForwardWeek", noOverride)
  FugSchedulerRuntime.setDisabled("DuplicateOverride", noOverride)
  FugSchedulerRuntime.setDisabled("DeleteOverride", noOverride)
  FugSchedulerRuntime.setDisabled("MoveOverrideUp", noOverride or overrideIndex <= 1)
  FugSchedulerRuntime.setDisabled("MoveOverrideDown", noOverride or overrideIndex >= #scheduler.overrides)
  FugSchedulerRuntime.updatingOverrideEditor = false

  if message and contextWarning ~= "" then
    FugSchedulerRuntime.setText("OverrideEditorStatus", message .. " | " .. contextWarning)
  elseif message then
    FugSchedulerRuntime.setText("OverrideEditorStatus", message)
  elseif contextWarning ~= "" then
    FugSchedulerRuntime.setText("OverrideEditorStatus", contextWarning)
  end
end

-- Add an immediately valid disabled Day Pattern Override using today's Core-local date.
function FugSchedulerRuntime.addOverride()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler or not scheduler.dayPatterns[1] then return false end
  local existing = {}
  for _, override in ipairs(scheduler.overrides or {}) do existing[override.id] = true end
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.overrides, "New Override")
  local dateText = os.date("%Y-%m-%d")
  local patternId = scheduler.dayPatterns[1].id
  FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Override added", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    table.insert(candidate.schedulers[schedulerIndex].overrides, {
      id = id,
      label = label,
      enabled = false,
      type = "DayPattern",
      startDate = dateText,
      endDate = dateText,
      patternId = patternId
    })
  end, nil, "OverrideEditorStatus")
end

-- Duplicate the selected Override beside its source with an independent ID and fields.
function FugSchedulerRuntime.duplicateOverride()
  local scheduler, source = FugSchedulerRuntime.selectedOverride()
  if not source then return false end
  local existing = {}
  for _, override in ipairs(scheduler.overrides or {}) do existing[override.id] = true end
  local sourceId = source.id
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.overrides, source.label .. " Copy")
  FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Override duplicated", function(candidate)
    local candidateScheduler = candidate.schedulers[FugSchedulerRuntime.selectedSchedulerIndex(candidate)]
    if not candidateScheduler then return false, "selected Scheduler no longer exists" end
    for index, override in ipairs(candidateScheduler.overrides) do
      if override.id == sourceId then
        local duplicate = FugSchedulerRuntime.copyPersisted(override)
        duplicate.id = id
        duplicate.label = label
        duplicate.enabled = false
        table.insert(candidateScheduler.overrides, index + 1, duplicate)
        return
      end
    end
    return false, "selected Override no longer exists"
  end, nil, "OverrideEditorStatus")
end

-- Delete the selected Override and retain the nearest neighboring selection.
function FugSchedulerRuntime.deleteOverride()
  local scheduler, source, sourceIndex = FugSchedulerRuntime.selectedOverride()
  if not source then
    local message = "Delete rejected: no Override is selected"
    FugSchedulerRuntime.setText("OverrideEditorStatus", message)
    return false
  end
  local nextOverride = nil
  if #scheduler.overrides > 1 then
    nextOverride = scheduler.overrides[math.min(sourceIndex, #scheduler.overrides - 1)]
    if nextOverride.id == source.id then nextOverride = scheduler.overrides[sourceIndex + 1] end
  end
  FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = nextOverride and nextOverride.id or nil
  local sourceId = source.id

  return FugSchedulerRuntime.commitScheduleEdit("Override deleted", function(candidate)
    local candidateScheduler = candidate.schedulers[FugSchedulerRuntime.selectedSchedulerIndex(candidate)]
    if not candidateScheduler then return false, "selected Scheduler no longer exists" end
    for index, override in ipairs(candidateScheduler.overrides) do
      if override.id == sourceId then
        table.remove(candidateScheduler.overrides, index)
        return
      end
    end
    return false, "selected Override no longer exists"
  end, nil, "OverrideEditorStatus")
end

-- Move the selected complete Override object by one persisted array row.
function FugSchedulerRuntime.moveOverride(offset)
  local scheduler, override, index = FugSchedulerRuntime.selectedOverride()
  if not override then return false end
  local targetIndex = index + offset
  if targetIndex < 1 or targetIndex > #scheduler.overrides then
    local message = "Move rejected: Override is already at the boundary"
    FugSchedulerRuntime.refreshOverrideEditor()
    FugSchedulerRuntime.setText("OverrideEditorStatus", message)
    return false
  end

  return FugSchedulerRuntime.commitScheduleEdit("Override moved", function(candidate)
    local _, _, candidateIndex = FugSchedulerRuntime.candidateSelectedOverride(candidate)
    if not candidateIndex then return false, "selected Override no longer exists" end
    local candidateScheduler = candidate.schedulers[FugSchedulerRuntime.selectedSchedulerIndex(candidate)]
    local moved = table.remove(candidateScheduler.overrides, candidateIndex)
    table.insert(candidateScheduler.overrides, candidateIndex + offset, moved)
  end, nil, "OverrideEditorStatus")
end

-- Return the selected Day Pattern and its index from a persisted candidate model.
function FugSchedulerRuntime.candidateSelectedDayPattern(candidate)
  local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
  if not schedulerIndex then return nil, nil, nil end
  local scheduler = candidate.schedulers[schedulerIndex]
  local selectedId = FugSchedulerRuntime.selectedDayPatternIds[scheduler.id]
  for index, dayPattern in ipairs(scheduler.dayPatterns) do
    if dayPattern.id == selectedId then return scheduler, dayPattern, index end
  end
  return scheduler, nil, nil
end

-- Return the selected Event and its persisted index from a candidate model.
function FugSchedulerRuntime.candidateSelectedEvent(candidate)
  local scheduler, dayPattern = FugSchedulerRuntime.candidateSelectedDayPattern(candidate)
  if not dayPattern then return scheduler, dayPattern, nil, nil end
  local selectedId = FugSchedulerRuntime.selectedEventIds[scheduler.id]
  for index, event in ipairs(dayPattern.events) do
    if event.id == selectedId then return scheduler, dayPattern, event, index end
  end
  return scheduler, dayPattern, nil, nil
end

-- Add an empty Day Pattern with a Scheduler-scoped UUID and select it.
function FugSchedulerRuntime.addDayPattern()
  local scheduler = FugSchedulerRuntime.selectedScheduler()
  if not scheduler then return false end
  local existing = {}
  for _, dayPattern in ipairs(scheduler.dayPatterns) do existing[dayPattern.id] = true end
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.dayPatterns, "New Day Pattern")
  FugSchedulerRuntime.selectedDayPatternIds[scheduler.id] = id
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = nil

  return FugSchedulerRuntime.commitScheduleEdit("Day Pattern added", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    table.insert(candidate.schedulers[schedulerIndex].dayPatterns, {id = id, label = label, events = {}})
  end, nil, "DayPatternEditorStatus")
end

-- Duplicate a Day Pattern with fresh Day Pattern and Scheduler-scoped Event UUIDs.
function FugSchedulerRuntime.duplicateDayPattern()
  local scheduler, source = FugSchedulerRuntime.selectedDayPattern()
  if not source then return false end

  local dayPatternIds = {}
  local eventIds = {}
  for _, dayPattern in ipairs(scheduler.dayPatterns) do
    dayPatternIds[dayPattern.id] = true
    for _, event in ipairs(dayPattern.events) do eventIds[event.id] = true end
  end
  local sourceId = source.id
  local dayPatternId = FugSchedulerRuntime.generateUuid(dayPatternIds)
  local eventIdMap = {}
  for _, event in ipairs(source.events) do
    local eventId = FugSchedulerRuntime.generateUuid(eventIds)
    eventIds[eventId] = true
    eventIdMap[event.id] = eventId
  end
  local label = FugSchedulerRuntime.uniqueLabel(scheduler.dayPatterns, source.label .. " Copy")
  FugSchedulerRuntime.selectedDayPatternIds[scheduler.id] = dayPatternId
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = source.events[1] and eventIdMap[source.events[1].id] or nil

  return FugSchedulerRuntime.commitScheduleEdit("Day Pattern duplicated", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    local candidateScheduler = candidate.schedulers[schedulerIndex]
    local dayPattern, sourceIndex = nil, nil
    for index, candidatePattern in ipairs(candidateScheduler.dayPatterns) do
      if candidatePattern.id == sourceId then dayPattern, sourceIndex = candidatePattern, index break end
    end
    if not sourceIndex then return false, "selected Day Pattern no longer exists" end
    local duplicate = FugSchedulerRuntime.copyPersisted(dayPattern)
    duplicate.id = dayPatternId
    duplicate.label = label
    for _, event in ipairs(duplicate.events) do event.id = eventIdMap[event.id] end
    table.insert(candidateScheduler.dayPatterns, sourceIndex + 1, duplicate)
  end, nil, "DayPatternEditorStatus")
end

-- Delete only an unreferenced Day Pattern and retain a neighboring selection.
function FugSchedulerRuntime.deleteDayPattern()
  local scheduler, source = FugSchedulerRuntime.selectedDayPattern()
  if not source then return false end
  local references = FugSchedulerRuntime.dayPatternReferences(scheduler, source.id)
  if references.total > 0 then
    local message = string.format(
      "Delete rejected: Day Pattern is used by %d weekdays and %d Overrides",
      references.weekdayCount,
      references.overrideCount
    )
    FugSchedulerRuntime.logLine(message)
    FugSchedulerRuntime.refreshDayPatternEditor()
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message)
    return false
  end
  if #scheduler.dayPatterns <= 1 then
    local message = "Delete rejected: at least one Day Pattern is required"
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message)
    return false
  end

  local sourceId = source.id
  local sourceIndex = nil
  for index, dayPattern in ipairs(scheduler.dayPatterns) do
    if dayPattern.id == source.id then sourceIndex = index break end
  end
  local nextIndex = math.min(sourceIndex or 1, #scheduler.dayPatterns - 1)
  local nextPattern = scheduler.dayPatterns[nextIndex]
  if nextPattern.id == source.id then nextPattern = scheduler.dayPatterns[nextIndex + 1] end
  FugSchedulerRuntime.selectedDayPatternIds[scheduler.id] = nextPattern.id
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = nextPattern.events[1] and nextPattern.events[1].id or nil

  return FugSchedulerRuntime.commitScheduleEdit("Day Pattern deleted", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    local candidatePatterns = candidate.schedulers[schedulerIndex].dayPatterns
    for index, dayPattern in ipairs(candidatePatterns) do
      if dayPattern.id == sourceId then
        table.remove(candidatePatterns, index)
        return
      end
    end
    return false, "selected Day Pattern no longer exists"
  end, nil, "DayPatternEditorStatus")
end

-- Return the first unused HH:MM value in one Day Pattern.
function FugSchedulerRuntime.firstAvailableEventTime(dayPattern)
  local used = {}
  for _, event in ipairs(dayPattern.events or {}) do used[event.time] = true end
  for minutes = 0, 1439 do
    local timeText = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
    if not used[timeText] then return timeText end
  end
  return "00:00"
end

-- Add an empty Event with a Scheduler-scoped UUID and select it.
function FugSchedulerRuntime.addEvent()
  local scheduler, dayPattern = FugSchedulerRuntime.selectedDayPattern()
  if not dayPattern then return false end
  local existing = {}
  for _, candidate in ipairs(scheduler.dayPatterns) do
    for _, event in ipairs(candidate.events) do existing[event.id] = true end
  end
  local id = FugSchedulerRuntime.generateUuid(existing)
  local label = FugSchedulerRuntime.uniqueLabel(dayPattern.events, "New Event")
  local timeText = FugSchedulerRuntime.firstAvailableEventTime(dayPattern)
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Event added", function(candidate)
    local _, selectedDayPattern = FugSchedulerRuntime.candidateSelectedDayPattern(candidate)
    if not selectedDayPattern then return false, "selected Day Pattern no longer exists" end
    table.insert(selectedDayPattern.events, {id = id, label = label, time = timeText, actions = {}})
  end, nil, "DayPatternEditorStatus")
end

-- Duplicate the selected Event with a fresh Scheduler-scoped UUID.
function FugSchedulerRuntime.duplicateEvent()
  local scheduler, _, source = FugSchedulerRuntime.selectedEvent()
  if not source then return false end
  local existing = {}
  for _, candidate in ipairs(scheduler.dayPatterns) do
    for _, event in ipairs(candidate.events) do existing[event.id] = true end
  end
  local sourceId = source.id
  local dayPatternId = FugSchedulerRuntime.selectedDayPatternIds[scheduler.id]
  local id = FugSchedulerRuntime.generateUuid(existing)
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = id

  return FugSchedulerRuntime.commitScheduleEdit("Event duplicated", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    for _, candidatePattern in ipairs(candidate.schedulers[schedulerIndex].dayPatterns) do
      if candidatePattern.id == dayPatternId then
        for index, event in ipairs(candidatePattern.events) do
          if event.id == sourceId then
            local duplicate = FugSchedulerRuntime.copyPersisted(event)
            duplicate.id = id
            duplicate.label = FugSchedulerRuntime.uniqueLabel(candidatePattern.events, event.label .. " Copy")
            table.insert(candidatePattern.events, index + 1, duplicate)
            return
          end
        end
      end
    end
    return false, "selected Event no longer exists"
  end, nil, "DayPatternEditorStatus")
end

-- Delete the selected Event; empty Day Patterns remain valid.
function FugSchedulerRuntime.deleteEvent()
  local scheduler, dayPattern, source = FugSchedulerRuntime.selectedEvent()
  if not source then return false end
  local sourceId = source.id
  local dayPatternId = dayPattern.id
  local sourceIndex = nil
  for index, event in ipairs(dayPattern.events) do
    if event.id == source.id then sourceIndex = index break end
  end
  local nextEvent = nil
  if #dayPattern.events > 1 then
    local nextIndex = math.min(sourceIndex or 1, #dayPattern.events - 1)
    nextEvent = dayPattern.events[nextIndex]
    if nextEvent.id == source.id then nextEvent = dayPattern.events[nextIndex + 1] end
  end
  FugSchedulerRuntime.selectedEventIds[scheduler.id] = nextEvent and nextEvent.id or nil

  return FugSchedulerRuntime.commitScheduleEdit("Event deleted", function(candidate)
    local schedulerIndex = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not schedulerIndex then return false, "selected Scheduler no longer exists" end
    for _, candidatePattern in ipairs(candidate.schedulers[schedulerIndex].dayPatterns) do
      if candidatePattern.id == dayPatternId then
        for index, event in ipairs(candidatePattern.events) do
          if event.id == sourceId then
            table.remove(candidatePattern.events, index)
            return
          end
        end
      end
    end
    return false, "selected Event no longer exists"
  end, nil, "DayPatternEditorStatus")
end

-- Attach one registered Action to the selected Event.
function FugSchedulerRuntime.addEventAction()
  local scheduler, _, event = FugSchedulerRuntime.selectedEvent()
  if not event then return false end
  local actionId = FugSchedulerRuntime.choiceId(Controls.EventActionPicker and Controls.EventActionPicker.String or "")
  if not FugSchedulerRuntime.actionsById[actionId] then
    local message = "Add rejected: select an available registered Action"
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message)
    return false
  end
  local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  FugSchedulerRuntime.selectedEventActionIndexes[key] = #event.actions + 1

  return FugSchedulerRuntime.commitScheduleEdit("Event Action attached", function(candidate)
    local _, _, selectedEvent = FugSchedulerRuntime.candidateSelectedEvent(candidate)
    if not selectedEvent then return false, "selected Event no longer exists" end
    table.insert(selectedEvent.actions, {actionId = actionId})
  end, nil, "DayPatternEditorStatus")
end

-- Delete the selected Event Action assignment and retain a neighboring row selection.
function FugSchedulerRuntime.deleteEventAction()
  local scheduler, event, index = FugSchedulerRuntime.selectedEventActionIndex()
  if not index then return false end
  local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  FugSchedulerRuntime.selectedEventActionIndexes[key] = (#event.actions > 1) and math.min(index, #event.actions - 1) or nil

  return FugSchedulerRuntime.commitScheduleEdit("Event Action deleted", function(candidate)
    local _, _, selectedEvent = FugSchedulerRuntime.candidateSelectedEvent(candidate)
    if not selectedEvent or not selectedEvent.actions[index] then return false, "selected Event Action no longer exists" end
    table.remove(selectedEvent.actions, index)
  end, nil, "DayPatternEditorStatus")
end

-- Move the selected Event Action assignment by one row while preserving all assignment fields.
function FugSchedulerRuntime.moveEventAction(offset)
  local scheduler, event, index = FugSchedulerRuntime.selectedEventActionIndex()
  if not index then return false end
  local targetIndex = index + offset
  if targetIndex < 1 or targetIndex > #event.actions then return false end
  local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  FugSchedulerRuntime.selectedEventActionIndexes[key] = targetIndex

  return FugSchedulerRuntime.commitScheduleEdit("Event Action moved", function(candidate)
    local _, _, selectedEvent = FugSchedulerRuntime.candidateSelectedEvent(candidate)
    if not selectedEvent or not selectedEvent.actions[index] then return false, "selected Event Action no longer exists" end
    local assignment = table.remove(selectedEvent.actions, index)
    table.insert(selectedEvent.actions, targetIndex, assignment)
  end, nil, "DayPatternEditorStatus")
end

-- Add a minimal valid Scheduler and select it after the transaction commits.
function FugSchedulerRuntime.addScheduler()
  local existing = {}
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do existing[scheduler.id] = true end
  local id = FugSchedulerRuntime.generateUuid(existing)
  return FugSchedulerRuntime.commitScheduleEdit("Scheduler " .. id .. " added", function(candidate)
    table.insert(candidate.schedulers, FugSchedulerRuntime.newScheduler(id, "New Scheduler"))
  end, id)
end

-- Duplicate the selected Scheduler while assigning a new root-scoped Scheduler ID.
function FugSchedulerRuntime.duplicateScheduler()
  local source = FugSchedulerRuntime.selectedScheduler()
  if not source then return false end

  local existing = {}
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do existing[scheduler.id] = true end
  local id = FugSchedulerRuntime.generateUuid(existing)
  return FugSchedulerRuntime.commitScheduleEdit("Scheduler " .. source.id .. " duplicated as " .. id, function(candidate)
    local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not index then return false, "selected Scheduler no longer exists" end
    local duplicate = FugSchedulerRuntime.copyPersisted(candidate.schedulers[index])
    duplicate.id = id
    duplicate.label = duplicate.label .. " Copy"
    duplicate.enabled = false
    duplicate.paused = false
    table.insert(candidate.schedulers, index + 1, duplicate)
  end, id)
end

-- Delete the selected Scheduler, but never permit removal of the final Scheduler.
function FugSchedulerRuntime.deleteScheduler()
  local source = FugSchedulerRuntime.selectedScheduler()
  if not source then return false end
  if #FugSchedulerRuntime.activeSchedule.schedulers <= 1 then
    local message = "Delete rejected: at least one Scheduler is required"
    FugSchedulerRuntime.setText("SchedulerEditorStatus", message)
    FugSchedulerRuntime.logLine(message)
    FugSchedulerRuntime.refreshSchedulerEditor()
    return false
  end

  local currentIndex = FugSchedulerRuntime.selectedSchedulerIndex(FugSchedulerRuntime.activeSchedule)
  local nextIndex = math.min(currentIndex or 1, #FugSchedulerRuntime.activeSchedule.schedulers - 1)
  local selectedAfterDelete = FugSchedulerRuntime.activeSchedule.schedulers[nextIndex].id
  if selectedAfterDelete == source.id then
    selectedAfterDelete = FugSchedulerRuntime.activeSchedule.schedulers[nextIndex + 1].id
  end

  return FugSchedulerRuntime.commitScheduleEdit("Scheduler " .. source.id .. " deleted", function(candidate)
    local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
    if not index then return false, "selected Scheduler no longer exists" end
    table.remove(candidate.schedulers, index)
  end, selectedAfterDelete)
end

-- Convert one Event occurrence into the stable machine-readable status contract.
function FugSchedulerRuntime.eventStatus(item)
  if not item then return nil end

  local actions = {}
  for actionIndex, eventAction in ipairs(item.event.actions or {}) do
    local registeredAction = FugSchedulerRuntime.actionsById[eventAction.actionId]
    table.insert(actions, {
      order = actionIndex,
      actionId = eventAction.actionId,
      actionLabel = registeredAction and registeredAction.label or eventAction.actionId,
      available = registeredAction ~= nil,
      enabled = eventAction.enabled ~= false,
      oneShot = eventAction.oneShot == true,
      fireOnStartup = eventAction.fireOnStartup == true,
      repeatSeconds = eventAction.repeatSeconds
    })
  end

  FugSchedulerRuntime.markJsonArray(actions)
  return {
    id = item.event.id,
    label = item.event.label,
    date = item.date,
    time = item.time,
    scheduledTime = os.date("%Y-%m-%d %H:%M:%S", item.timestamp),
    timestamp = item.timestamp,
    dayPatternId = item.dayPattern.id,
    dayPatternLabel = item.dayPattern.label,
    actions = actions
  }
end

-- Convert the resolved Day Pattern into a compact status view for integrations.
function FugSchedulerRuntime.dayPatternStatus(dayPattern)
  if not dayPattern then return nil end
  local events = {}
  for _, event in ipairs(dayPattern.events or {}) do
    local actionIds = {}
    for _, eventAction in ipairs(event.actions or {}) do table.insert(actionIds, eventAction.actionId) end
    FugSchedulerRuntime.markJsonArray(actionIds)
    table.insert(events, {id = event.id, label = event.label, time = event.time, actionIds = actionIds})
  end
  FugSchedulerRuntime.markJsonArray(events)
  return {id = dayPattern.id, label = dayPattern.label, events = events}
end

-- Build one Scheduler's independent status entry from its resolver result.
function FugSchedulerRuntime.buildSchedulerStatus(scheduler, result, resolveError)
  if resolveError then
    return {
      id = scheduler.id,
      label = scheduler.label,
      enabled = scheduler.enabled,
      paused = scheduler.paused,
      health = {state = "Error", message = tostring(resolveError)}
    }
  end

  local nextTimestamp = result.next and result.next.timestamp or nil
  return {
    id = scheduler.id,
    label = scheduler.label,
    enabled = scheduler.enabled,
    paused = scheduler.paused,
    health = {state = "OK", message = ""},
    resolution = {
      date = result.targetDate,
      source = result.resolutionSource,
      sourceType = result.resolutionRule and result.resolutionRule.type or nil,
      sourceId = result.resolutionRule and result.resolutionRule.id or nil,
      dayPatternId = result.resolvedDayPattern and result.resolvedDayPattern.id or nil,
      dayPatternLabel = result.resolvedDayPattern and result.resolvedDayPattern.label or nil
    },
    resolvedDayPattern = FugSchedulerRuntime.dayPatternStatus(result.resolvedDayPattern),
    previousEvent = FugSchedulerRuntime.eventStatus(result.previous),
    currentEvent = FugSchedulerRuntime.eventStatus(result.current),
    nextEvent = FugSchedulerRuntime.eventStatus(result.next),
    nextTransitionSeconds = nextTimestamp and math.max(0, math.floor(nextTimestamp - result.timestamp)) or nil,
    nextTransitionCountdown = FugSchedulerRuntime.formatCountdown(result.timestamp, nextTimestamp)
  }
end

-- Publish the complete multi-Scheduler status snapshot for third-party integrations.
function FugSchedulerRuntime.publishGlobalStatus(timestamp, schedulerStatuses, hasResolutionError)
  local status = {
    schemaVersion = 1,
    generatedAt = os.date("%Y-%m-%d %H:%M:%S"),
    resolvedFor = os.date("%Y-%m-%d %H:%M:%S", timestamp),
    configurationRevision = FugSchedulerRuntime.activeSchedule and FugSchedulerRuntime.activeSchedule.revision or nil,
    health = {
      state = hasResolutionError and "Error" or "OK",
      configurationValid = FugSchedulerRuntime.activeSchedule ~= nil,
      actionRegistryValid = #FugSchedulerRuntime.orderedActions > 0,
      warningCount = #FugSchedulerRuntime.scheduleWarnings
    },
    schedulers = schedulerStatuses
  }

  FugSchedulerStatus = status
  FugSchedulerRuntime.globalStatus = status
  FugSchedulerRuntime.setText("GlobalSchedulerStatus", FugSchedulerRuntime.encodeJson(status))
  FugSchedulerRuntime.setText("SchedulerCount", tostring(#schedulerStatuses))
end

-- Publish the selected Scheduler's resolver result to human-readable status controls.
function FugSchedulerRuntime.publishResolution(scheduler, result)
  FugSchedulerRuntime.selectedSchedulerId = scheduler.id
  if Controls.SchedulerEnabled then Controls.SchedulerEnabled.Boolean = scheduler.enabled end
  FugSchedulerRuntime.setText("ResolutionSource", result.resolutionSource or "None")
  FugSchedulerRuntime.setText("ResolvedDayPattern", result.resolvedDayPattern and result.resolvedDayPattern.label or "None")
  FugSchedulerRuntime.setText("PreviousEvent", FugSchedulerRuntime.formatEvent(result.previous))
  FugSchedulerRuntime.setText("CurrentEvent", FugSchedulerRuntime.formatEvent(result.current))
  FugSchedulerRuntime.setText("CurrentEventActions", FugSchedulerRuntime.formatEventActions(result.current))
  FugSchedulerRuntime.setText("NextEvent", FugSchedulerRuntime.formatEvent(result.next))
  FugSchedulerRuntime.setText("NextEventTime", result.next and os.date("%Y-%m-%d %H:%M", result.next.timestamp) or "N/A")
  FugSchedulerRuntime.setText("Countdown", FugSchedulerRuntime.formatCountdown(result.timestamp, result.next and result.next.timestamp or nil))
end

-- Resolve every configured Scheduler at TestDateTime and publish aggregate plus selected status.
function FugSchedulerRuntime.resolveSelectedTime()
  if not FugSchedulerRuntime.activeSchedule then
    FugSchedulerRuntime.setText("ScheduleStatus", "No valid Schedule is loaded")
    return false
  end

  local requested = Controls.TestDateTime and Controls.TestDateTime.String or ""
  local timestamp, parseError = FugSchedulerRuntime.parseDateTime(requested)
  if not timestamp then
    local message = "Test date/time error: " .. tostring(parseError)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end

  local resultsById = {}
  local schedulerStatuses = {}
  local hasResolutionError = false
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
    local resolveOk, result = pcall(FugSchedulerRuntime.resolveAt, scheduler, timestamp)
    if resolveOk then
      resultsById[scheduler.id] = result
      table.insert(schedulerStatuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, result, nil))
    else
      hasResolutionError = true
      table.insert(schedulerStatuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, nil, result))
      FugSchedulerRuntime.logLine("Resolution error for Scheduler " .. scheduler.id .. ": " .. tostring(result))
    end
  end

  FugSchedulerRuntime.resolutionResultsById = resultsById
  FugSchedulerRuntime.publishGlobalStatus(timestamp, schedulerStatuses, hasResolutionError)

  local selected = FugSchedulerRuntime.selectedScheduler()
  local selectedResult = selected and resultsById[selected.id] or nil
  if selected and selectedResult then
    FugSchedulerRuntime.publishResolution(selected, selectedResult)
  elseif selected then
    FugSchedulerRuntime.setText("ScheduleStatus", "Resolution failed for selected Scheduler " .. selected.id)
  end
  return not hasResolutionError
end

-- Decode, validate, and atomically install ScheduleData before resolving it.
function FugSchedulerRuntime.reloadSchedule()
  local source = Controls.ScheduleData and Controls.ScheduleData.String or ""
  FugSchedulerRuntime.refreshLineViewer("ScheduleDataViewer", source)
  if source == "" then
    FugSchedulerRuntime.setText("ScheduleStatus", "Waiting for ScheduleData")
    return false
  end

  local decodeOk, decoded, decodeError = pcall(FugSchedulerRuntime.json.decode, source)
  if not decodeOk then
    local message = "Schedule JSON error: " .. tostring(decoded)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end
  if decoded == nil then
    local message = "Schedule JSON error: " .. tostring(decodeError)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end

  local validated, warnings, validationError = FugSchedulerRuntime.validateSchedule(decoded)
  if not validated then
    local message = "Schedule validation error: " .. tostring(validationError)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message)
    return false
  end

  FugSchedulerRuntime.installValidatedSchedule(
    validated,
    warnings,
    FugSchedulerRuntime.selectedSchedulerId,
    "Loaded"
  )
  return true
end

-- Refresh the aggregate plugin state without enabling automatic Event execution.
function FugSchedulerRuntime.refreshStatus()
  local schedulerCount, enabledCount = 0, 0
  if FugSchedulerRuntime.activeSchedule then
    schedulerCount = #FugSchedulerRuntime.activeSchedule.schedulers
    for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
      if scheduler.enabled then enabledCount = enabledCount + 1 end
    end
  end
  FugSchedulerRuntime.setText("Status", string.format(
    "Resolution spike ready; %d/%d Schedulers enabled; automatic Event execution is off",
    enabledCount,
    schedulerCount
  ))
end

-- Populate the persistent presentation preference without touching schedule configuration.
function FugSchedulerRuntime.refreshPreferences(message)
  if not Controls.DateFormatPreference then return end
  FugSchedulerRuntime.updatingPreferences = true
  Controls.DateFormatPreference.Choices = {
    {Text = "dd/mm/yyyy", Id = "DMY"},
    {Text = "mm/dd/yyyy", Id = "MDY"},
    {Text = "yyyy-mm-dd", Id = "ISO"}
  }
  local format = FugSchedulerRuntime.dateFormatPreference()
  local labels = {DMY = "dd/mm/yyyy", MDY = "mm/dd/yyyy", ISO = "yyyy-mm-dd"}
  Controls.DateFormatPreference.String = FugSchedulerRuntime.encodeChoice(labels[format], format)
  FugSchedulerRuntime.updatingPreferences = false
  FugSchedulerRuntime.setText("PreferencesStatus", message or ("Date display format: " .. labels[format]))
end

-- Attach handlers for Action loading, Schedule loading, and deterministic resolution tests.
function FugSchedulerRuntime.attachHandlers()
  if Controls.ActionSource then
    Controls.ActionSource.EventHandler = function() FugSchedulerRuntime.reloadActions() end
  end

  if Controls.ScheduleData then
    Controls.ScheduleData.EventHandler = function()
      if not FugSchedulerRuntime.writingScheduleData then
        FugSchedulerRuntime.overrideDateBuffer = nil
        FugSchedulerRuntime.reloadSchedule()
      end
    end
  end

  if Controls.SchedulerSelect then
    Controls.SchedulerSelect.EventHandler = function(control)
      FugSchedulerRuntime.selectedSchedulerId = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.overrideDateBuffer = nil
      local scheduler = FugSchedulerRuntime.selectedScheduler()
      local result = scheduler and FugSchedulerRuntime.resolutionResultsById[scheduler.id] or nil
      if scheduler and result then FugSchedulerRuntime.publishResolution(scheduler, result) end
      FugSchedulerRuntime.refreshSchedulerEditor("Selected Scheduler " .. tostring(scheduler and scheduler.label or ""))
      FugSchedulerRuntime.refreshDayPatternEditor("Selected Scheduler " .. tostring(scheduler and scheduler.label or ""))
      FugSchedulerRuntime.refreshWeekPatternEditor("Selected Scheduler " .. tostring(scheduler and scheduler.label or ""))
      FugSchedulerRuntime.refreshOverrideEditor("Selected Scheduler " .. tostring(scheduler and scheduler.label or ""))
    end
  end

  if Controls.SchedulerLabel then
    Controls.SchedulerLabel.EventHandler = function(control)
      if FugSchedulerRuntime.updatingSchedulerEditor then return end
      local label = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Scheduler label updated", function(candidate)
        local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
        if not index then return false, "selected Scheduler no longer exists" end
        candidate.schedulers[index].label = label
      end)
    end
  end

  if Controls.SchedulerEditorEnabled then
    Controls.SchedulerEditorEnabled.EventHandler = function(control)
      if FugSchedulerRuntime.updatingSchedulerEditor then return end
      local enabled = control.Boolean
      FugSchedulerRuntime.commitScheduleEdit("Scheduler enabled state updated", function(candidate)
        local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
        if not index then return false, "selected Scheduler no longer exists" end
        candidate.schedulers[index].enabled = enabled
      end)
    end
  end

  if Controls.SchedulerPaused then
    Controls.SchedulerPaused.EventHandler = function(control)
      if FugSchedulerRuntime.updatingSchedulerEditor then return end
      local paused = control.Boolean
      FugSchedulerRuntime.commitScheduleEdit("Scheduler paused state updated", function(candidate)
        local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
        if not index then return false, "selected Scheduler no longer exists" end
        candidate.schedulers[index].paused = paused
      end)
    end
  end

  if Controls.SchedulerDefaultWeekPattern then
    Controls.SchedulerDefaultWeekPattern.EventHandler = function(control)
      if FugSchedulerRuntime.updatingSchedulerEditor then return end
      local weekPatternId = FugSchedulerRuntime.choiceId(control.String) or ""
      FugSchedulerRuntime.commitScheduleEdit("Default Week Pattern updated", function(candidate)
        local index = FugSchedulerRuntime.selectedSchedulerIndex(candidate)
        if not index then return false, "selected Scheduler no longer exists" end
        candidate.schedulers[index].defaultWeekPatternId = weekPatternId
      end)
    end
  end

  if Controls.AddScheduler then
    Controls.AddScheduler.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addScheduler() end
    end
  end

  if Controls.DuplicateScheduler then
    Controls.DuplicateScheduler.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.duplicateScheduler() end
    end
  end

  if Controls.DeleteScheduler then
    Controls.DeleteScheduler.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteScheduler() end
    end
  end

  if Controls.DayPatternSelect then
    Controls.DayPatternSelect.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local scheduler = FugSchedulerRuntime.selectedScheduler()
      if not scheduler then return end
      FugSchedulerRuntime.selectedDayPatternIds[scheduler.id] = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.selectedEventIds[scheduler.id] = nil
      FugSchedulerRuntime.refreshDayPatternEditor("Day Pattern selected")
    end
  end

  if Controls.DayPatternLabel then
    Controls.DayPatternLabel.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local label = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Day Pattern label updated", function(candidate)
        local _, dayPattern = FugSchedulerRuntime.candidateSelectedDayPattern(candidate)
        if not dayPattern then return false, "selected Day Pattern no longer exists" end
        dayPattern.label = label
      end, nil, "DayPatternEditorStatus")
    end
  end

  if Controls.AddDayPattern then
    Controls.AddDayPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addDayPattern() end
    end
  end

  if Controls.DuplicateDayPattern then
    Controls.DuplicateDayPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.duplicateDayPattern() end
    end
  end

  if Controls.DeleteDayPattern then
    Controls.DeleteDayPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteDayPattern() end
    end
  end

  if Controls.EventSelect then
    Controls.EventSelect.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local scheduler = FugSchedulerRuntime.selectedScheduler()
      if not scheduler then return end
      FugSchedulerRuntime.selectedEventIds[scheduler.id] = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.refreshDayPatternEditor("Event selected")
    end
  end

  if Controls.EventLabel then
    Controls.EventLabel.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local label = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Event label updated", function(candidate)
        local _, _, event = FugSchedulerRuntime.candidateSelectedEvent(candidate)
        if not event then return false, "selected Event no longer exists" end
        event.label = label
      end, nil, "DayPatternEditorStatus")
    end
  end

  if Controls.EventTime then
    Controls.EventTime.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local timeText = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Event time updated", function(candidate)
        local _, _, event = FugSchedulerRuntime.candidateSelectedEvent(candidate)
        if not event then return false, "selected Event no longer exists" end
        event.time = timeText
      end, nil, "DayPatternEditorStatus")
    end
  end

  if Controls.AddEvent then
    Controls.AddEvent.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addEvent() end
    end
  end

  if Controls.DuplicateEvent then
    Controls.DuplicateEvent.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.duplicateEvent() end
    end
  end

  if Controls.DeleteEvent then
    Controls.DeleteEvent.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteEvent() end
    end
  end

  if Controls.EventActionSelect then
    Controls.EventActionSelect.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local scheduler, _, event = FugSchedulerRuntime.selectedEvent()
      if not event then return end
      local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
      FugSchedulerRuntime.selectedEventActionIndexes[key] = tonumber(FugSchedulerRuntime.choiceId(control.String))
      FugSchedulerRuntime.refreshDayPatternEditor("Event Action selected")
    end
  end

  if Controls.AddEventAction then
    Controls.AddEventAction.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addEventAction() end
    end
  end

  if Controls.DeleteEventAction then
    Controls.DeleteEventAction.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteEventAction() end
    end
  end

  if Controls.MoveEventActionUp then
    Controls.MoveEventActionUp.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.moveEventAction(-1) end
    end
  end

  if Controls.MoveEventActionDown then
    Controls.MoveEventActionDown.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.moveEventAction(1) end
    end
  end

  if Controls.WeekPatternSelect then
    Controls.WeekPatternSelect.EventHandler = function(control)
      if FugSchedulerRuntime.updatingWeekPatternEditor then return end
      local scheduler = FugSchedulerRuntime.selectedScheduler()
      if not scheduler then return end
      FugSchedulerRuntime.selectedWeekPatternIds[scheduler.id] = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.refreshWeekPatternEditor("Week Pattern selected")
    end
  end

  if Controls.WeekPatternLabel then
    Controls.WeekPatternLabel.EventHandler = function(control)
      if FugSchedulerRuntime.updatingWeekPatternEditor then return end
      local label = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Week Pattern label updated", function(candidate)
        local _, weekPattern = FugSchedulerRuntime.candidateSelectedWeekPattern(candidate)
        if not weekPattern then return false, "selected Week Pattern no longer exists" end
        weekPattern.label = label
      end, nil, "WeekPatternEditorStatus")
    end
  end

  for _, weekday in ipairs(FugSchedulerWeekdays) do
    local weekdayKey = weekday.key
    local controlName = weekday.controlName
    if Controls[controlName] then
      Controls[controlName].EventHandler = function(control)
        if FugSchedulerRuntime.updatingWeekPatternEditor then return end
        local dayPatternId = FugSchedulerRuntime.choiceId(control.String) or ""
        FugSchedulerRuntime.commitScheduleEdit(weekdayKey .. " assignment updated", function(candidate)
          local scheduler, weekPattern = FugSchedulerRuntime.candidateSelectedWeekPattern(candidate)
          if not weekPattern then return false, "selected Week Pattern no longer exists" end
          local dayPatternExists = false
          for _, dayPattern in ipairs(scheduler.dayPatterns) do
            if dayPattern.id == dayPatternId then dayPatternExists = true break end
          end
          if not dayPatternExists then return false, "selected Day Pattern no longer exists" end
          weekPattern.days[weekdayKey] = dayPatternId
        end, nil, "WeekPatternEditorStatus")
      end
    end
  end

  if Controls.AddWeekPattern then
    Controls.AddWeekPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addWeekPattern() end
    end
  end

  if Controls.DuplicateWeekPattern then
    Controls.DuplicateWeekPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.duplicateWeekPattern() end
    end
  end

  if Controls.DeleteWeekPattern then
    Controls.DeleteWeekPattern.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteWeekPattern() end
    end
  end

  if Controls.OverrideSelect then
    Controls.OverrideSelect.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      local scheduler = FugSchedulerRuntime.selectedScheduler()
      if not scheduler then return end
      FugSchedulerRuntime.selectedOverrideIds[scheduler.id] = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.overrideDateBuffer = nil
      FugSchedulerRuntime.refreshOverrideEditor("Override selected")
    end
  end

  if Controls.OverrideLabel then
    Controls.OverrideLabel.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      local label = control.String or ""
      FugSchedulerRuntime.commitScheduleEdit("Override label updated", function(candidate)
        local _, override = FugSchedulerRuntime.candidateSelectedOverride(candidate)
        if not override then return false, "selected Override no longer exists" end
        override.label = label
      end, nil, "OverrideEditorStatus")
    end
  end

  if Controls.OverrideEnabled then
    Controls.OverrideEnabled.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      local enabled = control.Boolean
      FugSchedulerRuntime.commitScheduleEdit("Override enabled state updated", function(candidate)
        local _, override = FugSchedulerRuntime.candidateSelectedOverride(candidate)
        if not override then return false, "selected Override no longer exists" end
        override.enabled = enabled
      end, nil, "OverrideEditorStatus")
    end
  end

  if Controls.OverrideType then
    Controls.OverrideType.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      local overrideType = FugSchedulerRuntime.choiceId(control.String) or ""
      FugSchedulerRuntime.commitScheduleEdit("Override type updated", function(candidate)
        local scheduler, override = FugSchedulerRuntime.candidateSelectedOverride(candidate)
        if not override then return false, "selected Override no longer exists" end
        if overrideType ~= "DayPattern" and overrideType ~= "WeekPattern" then
          return false, "Override type must be Day Pattern or Week Pattern"
        end
        local patterns = overrideType == "WeekPattern" and scheduler.weekPatterns or scheduler.dayPatterns
        override.type = overrideType
        if not FugSchedulerRuntime.itemById(patterns, override.patternId) then
          if not patterns[1] then return false, "selected Override type has no available Patterns" end
          override.patternId = patterns[1].id
        end
      end, nil, "OverrideEditorStatus")
    end
  end

  if Controls.OverrideStartDate then
    Controls.OverrideStartDate.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      FugSchedulerRuntime.editOverrideStartDate(control.String or "")
    end
  end

  if Controls.OverrideEndDate then
    Controls.OverrideEndDate.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      FugSchedulerRuntime.editOverrideEndDate(control.String or "")
    end
  end

  if Controls.OverridePattern then
    Controls.OverridePattern.EventHandler = function(control)
      if FugSchedulerRuntime.updatingOverrideEditor then return end
      local patternId = FugSchedulerRuntime.choiceId(control.String) or ""
      FugSchedulerRuntime.commitScheduleEdit("Override pattern updated", function(candidate)
        local scheduler, override = FugSchedulerRuntime.candidateSelectedOverride(candidate)
        if not override then return false, "selected Override no longer exists" end
        local patterns = override.type == "WeekPattern" and scheduler.weekPatterns or scheduler.dayPatterns
        if not FugSchedulerRuntime.itemById(patterns, patternId) then
          return false, "selected Pattern is invalid for this Override type"
        end
        override.patternId = patternId
      end, nil, "OverrideEditorStatus")
    end
  end

  if Controls.AddOverride then
    Controls.AddOverride.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.addOverride() end
    end
  end

  if Controls.DuplicateOverride then
    Controls.DuplicateOverride.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.duplicateOverride() end
    end
  end

  if Controls.DeleteOverride then
    Controls.DeleteOverride.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.deleteOverride() end
    end
  end

  if Controls.MoveOverrideUp then
    Controls.MoveOverrideUp.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.moveOverride(-1) end
    end
  end

  if Controls.MoveOverrideDown then
    Controls.MoveOverrideDown.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.moveOverride(1) end
    end
  end

  if Controls.ShiftOverrideStartBackDay then
    Controls.ShiftOverrideStartBackDay.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideStart(-1) end
    end
  end

  if Controls.ShiftOverrideStartForwardDay then
    Controls.ShiftOverrideStartForwardDay.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideStart(1) end
    end
  end

  if Controls.ShiftOverrideStartBackWeek then
    Controls.ShiftOverrideStartBackWeek.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideStart(-7) end
    end
  end

  if Controls.ShiftOverrideStartForwardWeek then
    Controls.ShiftOverrideStartForwardWeek.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideStart(7) end
    end
  end

  if Controls.ShiftOverrideRangeBack then
    Controls.ShiftOverrideRangeBack.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideRange(-1) end
    end
  end

  if Controls.SetOverrideRangeToday then
    Controls.SetOverrideRangeToday.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.setOverrideRangeToday() end
    end
  end

  if Controls.ShiftOverrideRangeForward then
    Controls.ShiftOverrideRangeForward.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideRange(1) end
    end
  end

  if Controls.ShiftOverrideEndBackWeek then
    Controls.ShiftOverrideEndBackWeek.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideRange(-7) end
    end
  end

  if Controls.ShiftOverrideEndForwardWeek then
    Controls.ShiftOverrideEndForwardWeek.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.shiftOverrideRange(7) end
    end
  end

  if Controls.SetOverrideRangeOneDay then
    Controls.SetOverrideRangeOneDay.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.setOverrideRangeOneDay() end
    end
  end

  if Controls.DateFormatPreference then
    Controls.DateFormatPreference.EventHandler = function(control)
      if FugSchedulerRuntime.updatingPreferences then return end
      local format = FugSchedulerRuntime.choiceId(control.String)
      if format ~= "DMY" and format ~= "MDY" and format ~= "ISO" then
        FugSchedulerRuntime.refreshPreferences("Invalid date format preference; retained previous value")
        return
      end
      FugSchedulerRuntime.overrideDateBuffer = nil
      FugSchedulerRuntime.refreshPreferences()
      FugSchedulerRuntime.refreshOverrideEditor("Date format preference updated")
    end
  end

  if Controls.ReloadActions then
    Controls.ReloadActions.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.reloadActions() end
    end
  end

  if Controls.ReloadSchedule then
    Controls.ReloadSchedule.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.reloadSchedule() end
    end
  end

  if Controls.ResolveTestTime then
    Controls.ResolveTestTime.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.resolveSelectedTime() end
    end
  end

  if Controls.TestAction then
    Controls.TestAction.EventHandler = function(control)
      if control.Boolean then FugSchedulerRuntime.testSelectedAction() end
    end
  end
end

-- Initialize sample persistence, registries, status, and the first resolution result.
function FugSchedulerRuntime.initialize()
  if Controls.ActionSelect then Controls.ActionSelect.Choices = {} end
  if Controls.SchedulerSelect then Controls.SchedulerSelect.Choices = {} end
  if Controls.SchedulerDefaultWeekPattern then Controls.SchedulerDefaultWeekPattern.Choices = {} end
  if Controls.DayPatternSelect then Controls.DayPatternSelect.Choices = {} end
  if Controls.EventSelect then Controls.EventSelect.Choices = {} end
  if Controls.EventActionSelect then Controls.EventActionSelect.Choices = {} end
  if Controls.EventActionPicker then Controls.EventActionPicker.Choices = {} end
  if Controls.WeekPatternSelect then Controls.WeekPatternSelect.Choices = {} end
  if Controls.OverrideSelect then Controls.OverrideSelect.Choices = {} end
  if Controls.OverrideType then Controls.OverrideType.Choices = {} end
  if Controls.OverridePattern then Controls.OverridePattern.Choices = {} end
  if Controls.DateFormatPreference then Controls.DateFormatPreference.Choices = {} end
  for _, weekday in ipairs(FugSchedulerWeekdays) do
    if Controls[weekday.controlName] then Controls[weekday.controlName].Choices = {} end
  end
  if Controls.ScheduleDataViewer then Controls.ScheduleDataViewer.Choices = {} end
  if Controls.GlobalSchedulerStatusViewer then Controls.GlobalSchedulerStatusViewer.Choices = {} end
  if Controls.DiagnosticLogViewer then Controls.DiagnosticLogViewer.Choices = {} end
  FugSchedulerRuntime.setText("RegistryStatus", "Checking ActionSource evaluator support")
  FugSchedulerRuntime.setText("RegisteredActionCount", "0")
  FugSchedulerRuntime.setText("SchedulerCount", "0")
  FugSchedulerRuntime.setText("GlobalSchedulerStatus", "{}")
  FugSchedulerRuntime.setText("ScheduleStatus", "Checking persisted ScheduleData")
  FugSchedulerRuntime.setText("SchedulerEditorStatus", "Waiting for a valid Scheduler configuration")
  FugSchedulerRuntime.setText("DayPatternEditorStatus", "Waiting for a valid Day Pattern configuration")
  FugSchedulerRuntime.setText("WeekPatternEditorStatus", "Waiting for a valid Week Pattern configuration")
  FugSchedulerRuntime.setText("OverrideEditorStatus", "Waiting for a valid Override configuration")
  FugSchedulerRuntime.setText("PreferencesStatus", "Loading presentation preferences")
  FugSchedulerRuntime.setText("BuildDateDisplay", FugSchedulerRuntime.formatBuildDate(FugSchedulerPluginInfo.BuildTimestamp))
  FugSchedulerRuntime.refreshStatus()
  FugSchedulerRuntime.logLine("FugScheduler 2000 resolution spike initialized.")

  if Controls.ScheduleData and (Controls.ScheduleData.String or "") == "" then
    FugSchedulerRuntime.writingScheduleData = true
    Controls.ScheduleData.String = FugSchedulerRuntime.encodeJson(FugSchedulerRuntime.sampleSchedule())
    FugSchedulerRuntime.refreshLineViewer("ScheduleDataViewer", Controls.ScheduleData.String)
    FugSchedulerRuntime.writingScheduleData = false
  end
  if Controls.TestDateTime and (Controls.TestDateTime.String or "") == "" then
    Controls.TestDateTime.String = "2026-12-25 12:00"
  end
  if Controls.DateFormatPreference and (Controls.DateFormatPreference.String or "") == "" then
    Controls.DateFormatPreference.String = FugSchedulerRuntime.encodeChoice("yyyy-mm-dd", "ISO")
  end
  FugSchedulerRuntime.refreshPreferences()

  FugSchedulerRuntime.reloadActions()
  FugSchedulerRuntime.scheduleInitialized = true
  FugSchedulerRuntime.reloadSchedule()
end

FugSchedulerRuntime.attachHandlers()
FugSchedulerRuntime.initialize()
