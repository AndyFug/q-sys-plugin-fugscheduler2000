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

-- Stop retained timers from a prior hot-loaded runtime before replacing its global table.
local PreviousFugSchedulerRuntime = FugSchedulerRuntime
if type(PreviousFugSchedulerRuntime) == "table" then
  if PreviousFugSchedulerRuntime.executionTimer then
    pcall(function() PreviousFugSchedulerRuntime.executionTimer:Stop() end)
  end
  for _, previousPlan in pairs(PreviousFugSchedulerRuntime.runtimePlans or {}) do
    if previousPlan.timer then pcall(function() previousPlan.timer:Stop() end) end
  end
end

-- Hold the latest aggregate runtime snapshot for internal and debug-runtime consumers.
FugSchedulerStatus = nil

-- Use normalized numeric severities for inexpensive destination threshold comparisons.
local LogLevel = {
  OFF = 0,
  ERROR = 3,
  INFO = 6,
  DEBUG = 7
}

local LogLevelLabels = {
  [LogLevel.OFF] = "Off",
  [LogLevel.ERROR] = "Error",
  [LogLevel.INFO] = "Info",
  [LogLevel.DEBUG] = "Debug"
}

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
  updatingExecutionControl = false,
  overrideDateBuffer = nil,
  selectedDayPatternIds = {},
  selectedWeekPatternIds = {},
  selectedOverrideIds = {},
  selectedEventIds = {},
  selectedEventActionIndexes = {},
  runtimePlans = {},
  nextPlanGeneration = 0,
  executionPollSeconds = 1,
  normalEdgeMaxDelaySeconds = 90,
  occurrenceSafetyHorizonDays = 400,
  rollingFutureDateCount = 2,
  deferredRefreshGeneration = 0,
  lastExecutionMessage = "Automatic execution is disabled",
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

-- Return the configured numeric threshold for one external logging destination.
function FugSchedulerRuntime.loggingLevel(controlName, fallback)
  local control = Controls[controlName]
  local selected = control and tonumber(FugSchedulerRuntime.choiceId(control.String)) or nil
  if LogLevelLabels[selected] then return selected end
  return fallback
end

-- Return whether one message severity passes a configured destination threshold.
function FugSchedulerRuntime.shouldLog(messageLevel, destinationLevel)
  return destinationLevel ~= LogLevel.OFF and messageLevel <= destinationLevel
end

-- Build the shared concise context used by every logging destination.
function FugSchedulerRuntime.formatLogContext(context)
  if type(context) ~= "table" then return "" end
  local parts = {}
  -- Add one available label/ID pair without requiring every context field.
  local function addEntity(kind, label, id)
    if label and label ~= "" and id and id ~= "" then
      table.insert(parts, string.format('%s "%s" [%s]', kind, tostring(label), tostring(id)))
    elseif label and label ~= "" then
      table.insert(parts, kind .. ' "' .. tostring(label) .. '"')
    elseif id and id ~= "" then
      table.insert(parts, kind .. " [" .. tostring(id) .. "]")
    end
  end
  addEntity("Scheduler", context.schedulerLabel, context.schedulerId)
  addEntity("Event", context.eventLabel, context.eventId)
  addEntity("Action", context.actionLabel, context.actionId)
  if context.actionIndex then table.insert(parts, "action=" .. tostring(context.actionIndex)) end
  if context.reason and context.reason ~= "" then table.insert(parts, "reason=" .. tostring(context.reason)) end
  return table.concat(parts, " | ")
end

-- Return the product and optional Code Name prefix needed in the shared Core Event Log.
function FugSchedulerRuntime.eventLogPrefix()
  local designator = ""
  local ok, value = pcall(function()
    return Properties and Properties.internal_designator and Properties.internal_designator.Value or ""
  end)
  if ok then designator = tostring(value or "") end
  if designator ~= "" then return "FugScheduler 2000 [" .. designator .. "] " end
  return "FugScheduler 2000 "
end

-- Append one complete line while retaining only the newest 12,000 diagnostic characters.
function FugSchedulerRuntime.appendDiagnostic(line)
  local control = Controls.DiagnosticLog
  if not control then return end

  local existing = control.String or ""
  if existing ~= "" then existing = existing .. "\n" end
  existing = existing .. tostring(line)
  if #existing > 12000 then
    local overflow = #existing - 12000
    local nextLine = string.find(existing, "\n", overflow + 1, true)
    existing = nextLine and string.sub(existing, nextLine + 1) or string.sub(existing, -12000)
  end
  control.String = existing
  FugSchedulerRuntime.refreshLineViewer("DiagnosticLogViewer", existing)
end

-- Route one normalized message to the bounded diagnostics, Debug Output, and Core Event Log.
function FugSchedulerRuntime.log(messageLevel, message, context)
  if not LogLevelLabels[messageLevel] or messageLevel == LogLevel.OFF then messageLevel = LogLevel.INFO end
  local levelName = string.upper(LogLevelLabels[messageLevel])
  local contextText = FugSchedulerRuntime.formatLogContext(context)
  local body = contextText ~= "" and (contextText .. " | " .. tostring(message)) or tostring(message)
  local shortMessage = "[" .. levelName .. "] " .. body
  FugSchedulerRuntime.appendDiagnostic(os.date("%Y-%m-%d %H:%M:%S") .. " " .. shortMessage)

  local debugLevel = FugSchedulerRuntime.loggingLevel("DebugLogLevel", LogLevel.INFO)
  if FugSchedulerRuntime.shouldLog(messageLevel, debugLevel) then print(shortMessage) end

  local eventLevel = FugSchedulerRuntime.loggingLevel("EventLogLevel", LogLevel.OFF)
  if FugSchedulerRuntime.shouldLog(messageLevel, eventLevel) then
    local eventMessage = FugSchedulerRuntime.eventLogPrefix() .. shortMessage
    if messageLevel == LogLevel.ERROR then
      pcall(function() Log.Error(eventMessage) end)
    else
      pcall(function() Log.Message(eventMessage) end)
    end
  end
end

-- Preserve the existing internal call boundary while routing through the centralized logger.
function FugSchedulerRuntime.logLine(message, messageLevel, context)
  FugSchedulerRuntime.log(messageLevel or LogLevel.INFO, message, context)
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
              {id = "weekday-morning", label = "Morning", time = "09:00", actions = {{
                actionId = "Callback1", enabled = true, oneShot = false,
                fireOnStartup = true, fireOnResume = true, repeatSeconds = 300
              }}},
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
              {id = "opening-announcement", label = "Opening Announcement", time = "10:30", actions = {{
                actionId = "Callback2", enabled = true, oneShot = true,
                fireOnStartup = false, fireOnResume = false
              }}},
              {id = "closing-announcement", label = "Closing Announcement", time = "18:30", actions = {{
                actionId = "Callback1", enabled = true, oneShot = true,
                fireOnStartup = false, fireOnResume = false
              }}}
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
  if decodeOk and type(decoded) == "table" and
      (type(decoded.Id) == "string" or type(decoded.Id) == "number") then
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

    local suppliedDefaults = type(definition.defaults) == "table" and definition.defaults or {}
    local enabledDefault = suppliedDefaults.enabled
    if enabledDefault == nil then enabledDefault = definition.enabledDefault end
    local oneShotDefault = suppliedDefaults.oneShot
    if oneShotDefault == nil then oneShotDefault = definition.oneShotDefault end
    local fireOnStartupDefault = suppliedDefaults.fireOnStartup
    if fireOnStartupDefault == nil then fireOnStartupDefault = definition.fireOnStartupDefault end
    local fireOnResumeDefault = suppliedDefaults.fireOnResume
    if fireOnResumeDefault == nil then fireOnResumeDefault = definition.fireOnResumeDefault end
    if fireOnResumeDefault == nil then fireOnResumeDefault = fireOnStartupDefault end
    local repeatSecondsDefault = suppliedDefaults.repeatSeconds
    if repeatSecondsDefault == nil then repeatSecondsDefault = definition.repeatSecondsDefault end

    if enabledDefault ~= nil and type(enabledDefault) ~= "boolean" then
      return nil, nil, "Action " .. id .. " enabled default must be Boolean"
    end
    if oneShotDefault ~= nil and type(oneShotDefault) ~= "boolean" then
      return nil, nil, "Action " .. id .. " oneShot default must be Boolean"
    end
    if fireOnStartupDefault ~= nil and type(fireOnStartupDefault) ~= "boolean" then
      return nil, nil, "Action " .. id .. " fireOnStartup default must be Boolean"
    end
    if fireOnResumeDefault ~= nil and type(fireOnResumeDefault) ~= "boolean" then
      return nil, nil, "Action " .. id .. " fireOnResume default must be Boolean"
    end
    if repeatSecondsDefault ~= nil and
        (type(repeatSecondsDefault) ~= "number" or repeatSecondsDefault <= 0 or repeatSecondsDefault % 1 ~= 0) then
      return nil, nil, "Action " .. id .. " repeatSeconds default must be a positive whole number"
    end
    if oneShotDefault == true and
        (fireOnStartupDefault == true or fireOnResumeDefault == true or repeatSecondsDefault ~= nil) then
      return nil, nil, "Action " .. id .. " one-shot defaults cannot restore or repeat"
    end

    local action = {
      id = id,
      label = definition.label or id,
      description = definition.description,
      callback = definition.callback,
      defaults = {
        enabled = enabledDefault ~= false,
        oneShot = oneShotDefault == true,
        fireOnStartup = fireOnStartupDefault == true,
        fireOnResume = fireOnResumeDefault == true,
        repeatSeconds = repeatSecondsDefault
      }
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
    FugSchedulerRuntime.logLine(compileError, LogLevel.ERROR)
    return false
  end

  local provider = environment.GetFugSchedulerActions
  if type(provider) ~= "function" then
    local message = "ActionSource must define GetFugSchedulerActions()"
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return false
  end

  local providerOk, actionDefinitions = pcall(provider)
  if not providerOk then
    local message = "Provider error: " .. tostring(actionDefinitions)
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return false
  end

  local actionsById, orderedActions, validationError = FugSchedulerRuntime.buildRegistry(actionDefinitions)
  if not actionsById then
    FugSchedulerRuntime.setText("RegistryStatus", validationError)
    FugSchedulerRuntime.logLine(validationError, LogLevel.ERROR)
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return
  end

  local context = {actionLabel = action.label, actionId = action.id, reason = "manual test"}
  local callbackOk, callbackError = pcall(action.callback)
  if callbackOk then
    local message = "Test succeeded: " .. action.label .. " [" .. action.id .. "]"
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine("Manual Action test succeeded", LogLevel.INFO, context)
  else
    local message = "Callback error for " .. action.id .. ": " .. tostring(callbackError)
    FugSchedulerRuntime.setText("RegistryStatus", message)
    FugSchedulerRuntime.logLine("Manual Action test failed: " .. tostring(callbackError), LogLevel.ERROR, context)
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
          if eventAction.enabled ~= nil and type(eventAction.enabled) ~= "boolean" then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " enabled must be Boolean"
          end
          if eventAction.oneShot ~= nil and type(eventAction.oneShot) ~= "boolean" then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " oneShot must be Boolean"
          end
          if eventAction.fireOnStartup ~= nil and type(eventAction.fireOnStartup) ~= "boolean" then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " fireOnStartup must be Boolean"
          end
          if eventAction.fireOnResume ~= nil and type(eventAction.fireOnResume) ~= "boolean" then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " fireOnResume must be Boolean"
          end
          if eventAction.repeatSeconds ~= nil and
              (type(eventAction.repeatSeconds) ~= "number" or eventAction.repeatSeconds <= 0 or eventAction.repeatSeconds % 1 ~= 0) then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " repeatSeconds must be a positive whole number"
          end

          eventAction.enabled = eventAction.enabled ~= false
          eventAction.oneShot = eventAction.oneShot == true
          eventAction.fireOnStartup = eventAction.fireOnStartup == true
          if eventAction.fireOnResume == nil then eventAction.fireOnResume = eventAction.fireOnStartup end
          eventAction.fireOnResume = eventAction.fireOnResume == true
          if eventAction.oneShot and
              (eventAction.fireOnStartup or eventAction.fireOnResume or eventAction.repeatSeconds ~= nil) then
            return nil, nil, prefix .. " Event Action " .. actionIndex .. " in Event " .. event.id ..
              " is one-shot and cannot restore or repeat"
          end
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

-- Compare persisted model fragments while ignoring runtime-only underscore keys.
function FugSchedulerRuntime.persistedEqual(first, second)
  if type(first) ~= type(second) then return false end
  if type(first) ~= "table" then return first == second end
  for key, value in pairs(first) do
    if type(key) ~= "string" or string.sub(key, 1, 1) ~= "_" then
      if not FugSchedulerRuntime.persistedEqual(value, second[key]) then return false end
    end
  end
  for key in pairs(second) do
    if (type(key) ~= "string" or string.sub(key, 1, 1) ~= "_") and first[key] == nil then return false end
  end
  return true
end

-- Compile each Day Pattern once into stable chronological Event order.
function FugSchedulerRuntime.compileSchedulerEvents(scheduler)
  local compiled = {}
  local eventCount, actionCount = 0, 0
  for _, dayPattern in ipairs(scheduler.dayPatterns or {}) do
    local rows = {}
    for persistedOrder, event in ipairs(dayPattern.events or {}) do
      table.insert(rows, {
        event = event,
        minutes = event._minutes,
        persistedOrder = persistedOrder
      })
      eventCount = eventCount + 1
      actionCount = actionCount + #(event.actions or {})
    end
    table.sort(rows, function(first, second)
      if first.minutes == second.minutes then return first.persistedOrder < second.persistedOrder end
      return first.minutes < second.minutes
    end)
    compiled[dayPattern.id] = rows
  end
  return compiled, eventCount, actionCount
end

-- Create a runtime-only Scheduler plan; callers decide whether to attach a timer.
function FugSchedulerRuntime.createRuntimePlan(scheduler, configurationRevision)
  local started = Timer.Now()
  FugSchedulerRuntime.nextPlanGeneration = FugSchedulerRuntime.nextPlanGeneration + 1
  local compiledEvents, eventCount, actionCount = FugSchedulerRuntime.compileSchedulerEvents(scheduler)
  local plan = {
    schedulerId = scheduler.id,
    scheduler = scheduler,
    configurationRevision = configurationRevision,
    generation = FugSchedulerRuntime.nextPlanGeneration,
    compiledEventsByDayPatternId = compiledEvents,
    dateCache = {},
    windowDates = {},
    occurrences = {},
    previousIndex = nil,
    currentIndex = nil,
    nextIndex = nil,
    previousOccurrence = nil,
    currentOccurrence = nil,
    nextOccurrence = nil,
    initialized = false,
    lastObservedTimestamp = nil,
    activeOccurrenceKey = nil,
    activeOccurrence = nil,
    repeatDeadlines = {},
    lastEnabled = nil,
    lastPaused = nil,
    lastAutomaticEnabled = nil,
    lastTransitionReason = "Not initialized",
    lastCallbackResult = "None",
    timer = nil,
    timerPhaseSeconds = nil,
    timerPhasePending = false,
    lastPollElapsedTime = nil,
    forwardSearchLimitDate = nil,
    metrics = {
      schedulerCount = 1,
      eventCount = eventCount,
      actionCount = actionCount,
      pollCount = 0,
      totalPollDuration = 0,
      maximumPollDuration = 0,
      delayedPollCount = 0,
      planRebuildDuration = 0
    }
  }
  plan.metrics.planRebuildDuration = math.max(0, Timer.Now() - started)
  return plan
end

-- Resolve and cache one local date, including its already-ordered Event occurrences.
function FugSchedulerRuntime.resolvePlanDate(plan, dateText)
  local cached = plan.dateCache[dateText]
  if cached then return cached end
  local dayPattern, source, rule = FugSchedulerRuntime.resolveDayPattern(plan.scheduler, dateText)
  local occurrences = {}
  for _, compiled in ipairs(plan.compiledEventsByDayPatternId[dayPattern.id] or {}) do
    table.insert(occurrences, {
      timestamp = FugSchedulerRuntime.eventTimestamp(dateText, compiled.event.time),
      date = dateText,
      time = compiled.event.time,
      event = compiled.event,
      eventId = compiled.event.id,
      dayPattern = dayPattern,
      dayPatternId = dayPattern.id,
      sequence = compiled.persistedOrder
    })
  end
  cached = {
    date = dateText,
    dayPattern = dayPattern,
    resolutionSource = source,
    resolutionRule = rule,
    occurrences = occurrences
  }
  plan.dateCache[dateText] = cached
  return cached
end

-- Refresh authoritative Previous/Current/Next references from the current index.
function FugSchedulerRuntime.refreshPlanCursor(plan)
  local count = #plan.occurrences
  local currentIndex = plan.currentIndex
  plan.previousIndex = currentIndex and currentIndex > 1 and (currentIndex - 1) or nil
  plan.nextIndex = currentIndex and currentIndex < count and (currentIndex + 1) or (not currentIndex and count > 0 and 1 or nil)
  plan.previousOccurrence = plan.previousIndex and plan.occurrences[plan.previousIndex] or nil
  plan.currentOccurrence = currentIndex and plan.occurrences[currentIndex] or nil
  plan.nextOccurrence = plan.nextIndex and plan.occurrences[plan.nextIndex] or nil
end

-- Rebuild the small ordered occurrence window around an arbitrary timestamp.
function FugSchedulerRuntime.positionPlanCursor(plan, timestamp)
  local targetDate = os.date("%Y-%m-%d", timestamp)
  if (plan.metrics.eventCount or 0) == 0 then
    FugSchedulerRuntime.resolvePlanDate(plan, targetDate)
    plan.windowDates = {targetDate}
    plan.occurrences = {}
    plan.currentIndex = nil
    plan.forwardSearchLimitDate = FugSchedulerRuntime.shiftDate(targetDate, FugSchedulerRuntime.occurrenceSafetyHorizonDays)
    FugSchedulerRuntime.refreshPlanCursor(plan)
    return nil
  end
  local horizon = FugSchedulerRuntime.occurrenceSafetyHorizonDays
  local minimumOffset, maximumOffset = 0, 0
  local priorCount, nextFound = 0, false

  for offset = 0, -horizon, -1 do
    local entry = FugSchedulerRuntime.resolvePlanDate(plan, FugSchedulerRuntime.shiftDate(targetDate, offset))
    for _, occurrence in ipairs(entry.occurrences) do
      if occurrence.timestamp <= timestamp then priorCount = priorCount + 1 end
    end
    minimumOffset = offset
    if priorCount >= 2 then break end
  end

  for offset = 0, horizon do
    local entry = FugSchedulerRuntime.resolvePlanDate(plan, FugSchedulerRuntime.shiftDate(targetDate, offset))
    for _, occurrence in ipairs(entry.occurrences) do
      if occurrence.timestamp > timestamp then nextFound = true break end
    end
    maximumOffset = offset
    if nextFound then
      maximumOffset = math.min(horizon, offset + FugSchedulerRuntime.rollingFutureDateCount)
      break
    end
  end

  plan.windowDates = {}
  plan.occurrences = {}
  for offset = minimumOffset, maximumOffset do
    local dateText = FugSchedulerRuntime.shiftDate(targetDate, offset)
    local entry = FugSchedulerRuntime.resolvePlanDate(plan, dateText)
    table.insert(plan.windowDates, dateText)
    for _, occurrence in ipairs(entry.occurrences) do table.insert(plan.occurrences, occurrence) end
  end

  plan.currentIndex = nil
  for index, occurrence in ipairs(plan.occurrences) do
    if occurrence.timestamp <= timestamp then plan.currentIndex = index else break end
  end
  FugSchedulerRuntime.refreshPlanCursor(plan)
  plan.forwardSearchLimitDate = not plan.nextOccurrence and plan.windowDates[#plan.windowDates] or nil
  return plan.currentOccurrence
end

-- Append dates incrementally until a future occurrence is available or the 400-day safety horizon is reached.
function FugSchedulerRuntime.extendPlanForward(plan)
  if (plan.metrics.eventCount or 0) == 0 then return end
  local lastDate = plan.windowDates[#plan.windowDates] or os.date("%Y-%m-%d", plan.lastObservedTimestamp or os.time())
  if plan.forwardSearchLimitDate and lastDate >= plan.forwardSearchLimitDate then return end
  local appended = 0
  while not plan.nextOccurrence and appended < FugSchedulerRuntime.occurrenceSafetyHorizonDays do
    lastDate = FugSchedulerRuntime.shiftDate(lastDate, 1)
    local entry = FugSchedulerRuntime.resolvePlanDate(plan, lastDate)
    table.insert(plan.windowDates, lastDate)
    for _, occurrence in ipairs(entry.occurrences) do table.insert(plan.occurrences, occurrence) end
    appended = appended + 1
    FugSchedulerRuntime.refreshPlanCursor(plan)
  end
  if plan.nextOccurrence then
    plan.forwardSearchLimitDate = nil
    for _ = 1, FugSchedulerRuntime.rollingFutureDateCount do
      lastDate = FugSchedulerRuntime.shiftDate(lastDate, 1)
      local entry = FugSchedulerRuntime.resolvePlanDate(plan, lastDate)
      table.insert(plan.windowDates, lastDate)
      for _, occurrence in ipairs(entry.occurrences) do table.insert(plan.occurrences, occurrence) end
    end
    FugSchedulerRuntime.refreshPlanCursor(plan)
  else
    plan.forwardSearchLimitDate = lastDate
  end
end

-- Drop obsolete occurrence history while retaining the authoritative Previous occurrence.
function FugSchedulerRuntime.trimPlanWindow(plan)
  local keepFrom = plan.previousIndex or plan.currentIndex or 1
  if keepFrom <= 1 then return end
  local trimmed = {}
  for index = keepFrom, #plan.occurrences do table.insert(trimmed, plan.occurrences[index]) end
  plan.occurrences = trimmed
  plan.currentIndex = plan.currentIndex and (plan.currentIndex - keepFrom + 1) or nil

  local firstDate = trimmed[1] and trimmed[1].date or nil
  if firstDate then
    local dates = {}
    for _, dateText in ipairs(plan.windowDates) do
      if dateText >= firstDate then table.insert(dates, dateText) end
    end
    plan.windowDates = dates
    for dateText in pairs(plan.dateCache) do
      if dateText < firstDate then plan.dateCache[dateText] = nil end
    end
  end
  FugSchedulerRuntime.refreshPlanCursor(plan)
end

-- Advance the cached cursor and return all genuinely crossed occurrences in order.
function FugSchedulerRuntime.advancePlanCursor(plan, fromTimestamp, toTimestamp)
  local crossed = {}
  if not plan.nextOccurrence and plan.forwardSearchLimitDate and
      os.date("%Y-%m-%d", toTimestamp) >= plan.forwardSearchLimitDate then
    plan.forwardSearchLimitDate = nil
  end
  if not plan.nextOccurrence then FugSchedulerRuntime.extendPlanForward(plan) end
  while plan.nextOccurrence and plan.nextOccurrence.timestamp <= toTimestamp do
    local occurrence = plan.nextOccurrence
    if occurrence.timestamp > fromTimestamp then table.insert(crossed, occurrence) end
    plan.currentIndex = plan.nextIndex
    FugSchedulerRuntime.refreshPlanCursor(plan)
    if not plan.nextOccurrence then FugSchedulerRuntime.extendPlanForward(plan) end
  end
  FugSchedulerRuntime.trimPlanWindow(plan)
  return crossed
end

-- Build a resolver result from one positioned plan without changing live execution state.
function FugSchedulerRuntime.planResolutionResult(plan, timestamp)
  local targetDate = os.date("%Y-%m-%d", timestamp)
  local dateEntry = FugSchedulerRuntime.resolvePlanDate(plan, targetDate)
  return {
    timestamp = timestamp,
    targetDate = targetDate,
    resolvedDayPattern = dateEntry.dayPattern,
    resolutionSource = dateEntry.resolutionSource,
    resolutionRule = dateEntry.resolutionRule,
    previous = plan.previousOccurrence,
    current = plan.currentOccurrence,
    next = plan.nextOccurrence
  }
end

-- Resolve an arbitrary timestamp incrementally without mutating the live Scheduler cursor.
function FugSchedulerRuntime.resolveAt(scheduler, timestamp)
  local plan = FugSchedulerRuntime.createRuntimePlan(scheduler, nil)
  FugSchedulerRuntime.positionPlanCursor(plan, timestamp)
  return FugSchedulerRuntime.planResolutionResult(plan, timestamp)
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

-- Return Event and Event Action counts used to decide whether UI/status refresh should be deferred.
function FugSchedulerRuntime.scheduleWorkload(schedule)
  local eventCount, actionCount = 0, 0
  for _, scheduler in ipairs(schedule.schedulers or {}) do
    for _, dayPattern in ipairs(scheduler.dayPatterns or {}) do
      eventCount = eventCount + #(dayPattern.events or {})
      for _, event in ipairs(dayPattern.events or {}) do actionCount = actionCount + #(event.actions or {}) end
    end
  end
  return eventCount, actionCount
end

-- Refresh a large installed model in bounded Scheduler chunks and discard obsolete deferred work.
function FugSchedulerRuntime.deferInstalledScheduleRefresh(summary)
  FugSchedulerRuntime.deferredRefreshGeneration = FugSchedulerRuntime.deferredRefreshGeneration + 1
  local generation = FugSchedulerRuntime.deferredRefreshGeneration
  local schedule = FugSchedulerRuntime.activeSchedule
  Timer.CallAfter(function()
    if generation ~= FugSchedulerRuntime.deferredRefreshGeneration or schedule ~= FugSchedulerRuntime.activeSchedule then return end
    local requested = Controls.TestDateTime and Controls.TestDateTime.String or ""
    local timestamp, parseError = FugSchedulerRuntime.parseDateTime(requested)
    if not timestamp then
      FugSchedulerRuntime.setText("ScheduleStatus", "Test date/time error: " .. tostring(parseError))
      return
    end
    local state = {index = 1, statuses = {}, resultsById = {}, hasResolutionError = false}
    local function step()
      if generation ~= FugSchedulerRuntime.deferredRefreshGeneration or schedule ~= FugSchedulerRuntime.activeSchedule then return end
      local lastIndex = math.min(#schedule.schedulers, state.index + 3)
      for index = state.index, lastIndex do
        local scheduler = schedule.schedulers[index]
        local resolveOk, result = pcall(function()
          local plan = FugSchedulerRuntime.runtimePlans[scheduler.id]
          if requested == "" and plan and plan.currentOccurrence then
            return FugSchedulerRuntime.planResolutionResult(plan, timestamp)
          end
          return FugSchedulerRuntime.resolveAt(scheduler, timestamp)
        end)
        if resolveOk then
          state.resultsById[scheduler.id] = result
          table.insert(state.statuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, result, nil))
        else
          state.hasResolutionError = true
          table.insert(state.statuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, nil, result))
        end
      end
      state.index = lastIndex + 1
      if state.index <= #schedule.schedulers then
        Timer.CallAfter(step, 0.02)
        return
      end
      FugSchedulerRuntime.resolutionResultsById = state.resultsById
      FugSchedulerRuntime.publishGlobalStatus(timestamp, state.statuses, state.hasResolutionError)
      local selected = FugSchedulerRuntime.selectedScheduler()
      local selectedResult = selected and state.resultsById[selected.id] or nil
      if selected and selectedResult then FugSchedulerRuntime.publishResolution(selected, selectedResult) end
      Timer.CallAfter(function()
        if generation ~= FugSchedulerRuntime.deferredRefreshGeneration or schedule ~= FugSchedulerRuntime.activeSchedule then return end
        FugSchedulerRuntime.refreshSchedulerEditor(summary)
        FugSchedulerRuntime.refreshDayPatternEditor(summary)
        FugSchedulerRuntime.refreshWeekPatternEditor(summary)
        FugSchedulerRuntime.refreshOverrideEditor(summary)
        FugSchedulerRuntime.refreshStatus()
      end, 0.02)
    end
    step()
  end, 2.1)
end

-- Atomically install a completely validated model and rebuild every derived view.
function FugSchedulerRuntime.installValidatedSchedule(validated, warnings, selectedId, statusPrefix)
  FugSchedulerRuntime.activeSchedule = validated
  FugSchedulerRuntime.scheduleWarnings = warnings or {}
  FugSchedulerRuntime.synchronizeRuntimePlans(validated)
  FugSchedulerRuntime.selectedSchedulerId = selectedId
  FugSchedulerRuntime.refreshSchedulerChoices()

  local summary = (statusPrefix or "Loaded") .. " " .. FugSchedulerRuntime.scheduleSummary(validated, #FugSchedulerRuntime.scheduleWarnings)
  FugSchedulerRuntime.setText("ScheduleStatus", summary)
  FugSchedulerRuntime.logLine(summary)
  for _, warning in ipairs(FugSchedulerRuntime.scheduleWarnings) do
    FugSchedulerRuntime.logLine("Schedule warning: " .. warning)
  end

  local eventCount = FugSchedulerRuntime.scheduleWorkload(validated)
  if #validated.schedulers > 10 or eventCount > 200 then
    FugSchedulerRuntime.setText("ScheduleStatus", summary .. "; refreshing status asynchronously")
    FugSchedulerRuntime.deferInstalledScheduleRefresh(summary)
    FugSchedulerRuntime.refreshStatus()
  else
    FugSchedulerRuntime.deferredRefreshGeneration = FugSchedulerRuntime.deferredRefreshGeneration + 1
    FugSchedulerRuntime.resolveSelectedTime()
    FugSchedulerRuntime.refreshSchedulerEditor(summary)
    FugSchedulerRuntime.refreshDayPatternEditor(summary)
    FugSchedulerRuntime.refreshWeekPatternEditor(summary)
    FugSchedulerRuntime.refreshOverrideEditor(summary)
    FugSchedulerRuntime.refreshStatus()
  end
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
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

-- Return the selected Event Action assignment and its owning Event.
function FugSchedulerRuntime.selectedEventAction()
  local scheduler, event, index = FugSchedulerRuntime.selectedEventActionIndex()
  return scheduler, event, index and event.actions[index] or nil, index
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
      local mode = eventAction.oneShot and "1x" or "state"
      local disabled = eventAction.enabled == false and " off" or ""
      table.insert(actionChoices, {Text = index .. "  " .. label .. " [" .. mode .. disabled .. "]", Id = tostring(index)})
    end
  end
  if Controls.EventActionSelect then Controls.EventActionSelect.Choices = actionChoices end

  local _, _, actionIndex = FugSchedulerRuntime.selectedEventActionIndex()
  if event and actionIndex and Controls.EventActionSelect then
    local eventAction = event.actions[actionIndex]
    local action = FugSchedulerRuntime.actionsById[eventAction.actionId]
    local label = action and action.label or (eventAction.actionId .. " (unavailable)")
    local mode = eventAction.oneShot and "1x" or "state"
    local disabled = eventAction.enabled == false and " off" or ""
    Controls.EventActionSelect.String = FugSchedulerRuntime.encodeChoice(
      actionIndex .. "  " .. label .. " [" .. mode .. disabled .. "]",
      tostring(actionIndex)
    )
  elseif Controls.EventActionSelect then
    Controls.EventActionSelect.String = ""
  end

  local selectedEventAction = actionIndex and event.actions[actionIndex] or nil
  if Controls.EventActionMode then
    Controls.EventActionMode.Choices = {
      {Text = "Stateful", Id = "Stateful"},
      {Text = "One Shot", Id = "OneShot"}
    }
    if selectedEventAction then
      local modeId = selectedEventAction.oneShot and "OneShot" or "Stateful"
      Controls.EventActionMode.String = FugSchedulerRuntime.encodeChoice(
        selectedEventAction.oneShot and "One Shot" or "Stateful",
        modeId
      )
    else
      Controls.EventActionMode.String = ""
    end
  end
  if Controls.EventActionEnabled then Controls.EventActionEnabled.Boolean = selectedEventAction and selectedEventAction.enabled ~= false or false end
  if Controls.EventActionFireOnStartup then Controls.EventActionFireOnStartup.Boolean = selectedEventAction and selectedEventAction.fireOnStartup == true or false end
  if Controls.EventActionFireOnResume then Controls.EventActionFireOnResume.Boolean = selectedEventAction and selectedEventAction.fireOnResume == true or false end
  if Controls.EventActionRepeatSeconds then
    Controls.EventActionRepeatSeconds.String = selectedEventAction and selectedEventAction.repeatSeconds and tostring(selectedEventAction.repeatSeconds) or ""
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
  FugSchedulerRuntime.setDisabled("EventActionEnabled", not selectedEventAction)
  FugSchedulerRuntime.setDisabled("EventActionMode", not selectedEventAction)
  FugSchedulerRuntime.setDisabled("EventActionFireOnStartup", not selectedEventAction or selectedEventAction.oneShot)
  FugSchedulerRuntime.setDisabled("EventActionFireOnResume", not selectedEventAction or selectedEventAction.oneShot)
  FugSchedulerRuntime.setDisabled("EventActionRepeatSeconds", not selectedEventAction or selectedEventAction.oneShot)
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
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

-- Apply one validated option edit to the selected Event Action assignment.
function FugSchedulerRuntime.updateSelectedEventAction(description, editFunction)
  local _, event, eventAction, index = FugSchedulerRuntime.selectedEventAction()
  if not eventAction or not index then return false end

  return FugSchedulerRuntime.commitScheduleEdit(description, function(candidate)
    local _, _, selectedEvent = FugSchedulerRuntime.candidateSelectedEvent(candidate)
    if not selectedEvent or not selectedEvent.actions[index] then
      return false, "selected Event Action no longer exists"
    end
    return editFunction(selectedEvent.actions[index])
  end, nil, "DayPatternEditorStatus")
end

-- Attach one registered Action to the selected Event and copy its execution defaults.
function FugSchedulerRuntime.addEventAction()
  local scheduler, _, event = FugSchedulerRuntime.selectedEvent()
  if not event then return false end
  local actionId = FugSchedulerRuntime.choiceId(Controls.EventActionPicker and Controls.EventActionPicker.String or "")
  local action = FugSchedulerRuntime.actionsById[actionId]
  if not action then
    local message = "Add rejected: select an available registered Action"
    FugSchedulerRuntime.setText("DayPatternEditorStatus", message)
    return false
  end
  local key = FugSchedulerRuntime.eventActionSelectionKey(scheduler, event)
  FugSchedulerRuntime.selectedEventActionIndexes[key] = #event.actions + 1
  local defaults = action.defaults or {}

  return FugSchedulerRuntime.commitScheduleEdit("Event Action attached", function(candidate)
    local _, _, selectedEvent = FugSchedulerRuntime.candidateSelectedEvent(candidate)
    if not selectedEvent then return false, "selected Event no longer exists" end
    table.insert(selectedEvent.actions, {
      actionId = actionId,
      enabled = defaults.enabled ~= false,
      oneShot = defaults.oneShot == true,
      fireOnStartup = defaults.fireOnStartup == true,
      fireOnResume = defaults.fireOnResume == true,
      repeatSeconds = defaults.repeatSeconds
    })
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
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

-- Return whether the plugin-wide automatic execution safety control is armed.
function FugSchedulerRuntime.automaticExecutionEnabled()
  return Controls.AutomaticExecutionEnabled and Controls.AutomaticExecutionEnabled.Boolean == true or false
end

-- Build a stable runtime-only identity for one dated, ordered Event occurrence.
function FugSchedulerRuntime.occurrenceKey(item)
  if not item then return nil end
  return table.concat({
    tostring(item.timestamp),
    tostring(item.date),
    tostring(item.dayPatternId or (item.dayPattern and item.dayPattern.id)),
    tostring(item.eventId or (item.event and item.event.id)),
    tostring(item.sequence)
  }, "\31")
end

-- Return one Scheduler's compiled runtime plan.
function FugSchedulerRuntime.executionState(schedulerId)
  return FugSchedulerRuntime.runtimePlans[schedulerId]
end

-- Publish the latest execution result and route it through the centralized logger.
function FugSchedulerRuntime.setExecutionMessage(message, messageLevel, context, logText)
  FugSchedulerRuntime.lastExecutionMessage = tostring(message)
  FugSchedulerRuntime.setText("ExecutionStatus", FugSchedulerRuntime.lastExecutionMessage)
  FugSchedulerRuntime.logLine(logText or FugSchedulerRuntime.lastExecutionMessage, messageLevel or LogLevel.INFO, context)
end

-- Stop repeat scheduling for one Scheduler without affecting timeline resolution.
function FugSchedulerRuntime.clearRepeats(state)
  state.repeatDeadlines = {}
end

-- Invoke one registered Event Action with callback isolation and execution diagnostics.
function FugSchedulerRuntime.executeEventAction(scheduler, occurrence, eventAction, actionIndex, reason)
  if eventAction.enabled == false then return false end
  local action = FugSchedulerRuntime.actionsById[eventAction.actionId]
  local event = occurrence and occurrence.event or nil
  local occurrenceLabel = event and event.label or "Unknown Event"
  local context = {
    schedulerLabel = scheduler.label,
    schedulerId = scheduler.id,
    eventLabel = occurrenceLabel,
    eventId = event and event.id or nil,
    actionLabel = action and action.label or nil,
    actionId = eventAction.actionId,
    actionIndex = actionIndex,
    reason = reason
  }
  if not action then
    local message = string.format(
      "Execution skipped: Scheduler %s Event %s Action %s is unavailable",
      scheduler.label,
      occurrenceLabel,
      tostring(eventAction.actionId)
    )
    local state = FugSchedulerRuntime.executionState(scheduler.id)
    if state then state.lastCallbackResult = message end
    FugSchedulerRuntime.setExecutionMessage(message, LogLevel.ERROR, context, "Action is unavailable; execution skipped")
    return false
  end

  local callbackOk, callbackError = pcall(action.callback)
  local state = FugSchedulerRuntime.executionState(scheduler.id)
  if callbackOk then
    local message = string.format(
      "Executed %s / %s / %s (%s, Action %d)",
      scheduler.label,
      occurrenceLabel,
      action.label,
      reason,
      actionIndex
    )
    if state then state.lastCallbackResult = message end
    local level = reason == "repeat" and LogLevel.DEBUG or LogLevel.INFO
    FugSchedulerRuntime.setExecutionMessage(message, level, context, "Executed successfully")
    return true
  end

  local message = string.format(
    "Callback error: %s / %s / %s: %s",
    scheduler.label,
    occurrenceLabel,
    action.id,
    tostring(callbackError)
  )
  if state then state.lastCallbackResult = message end
  FugSchedulerRuntime.setExecutionMessage(
    message,
    LogLevel.ERROR,
    context,
    "Callback failed: " .. tostring(callbackError)
  )
  return false
end

-- Start repeat deadlines for the current occurrence without producing catch-up bursts.
function FugSchedulerRuntime.scheduleRepeats(state, occurrence, now)
  FugSchedulerRuntime.clearRepeats(state)
  if not occurrence then return end
  for actionIndex, eventAction in ipairs(occurrence.event.actions or {}) do
    if eventAction.enabled ~= false and not eventAction.oneShot and eventAction.repeatSeconds then
      state.repeatDeadlines[actionIndex] = {
        due = now + eventAction.repeatSeconds,
        actionId = eventAction.actionId,
        repeatSeconds = eventAction.repeatSeconds
      }
    end
  end
end

-- Execute every enabled Event Action at a normally observed Event edge.
function FugSchedulerRuntime.executeOccurrence(scheduler, state, occurrence, reason, now)
  state.activeOccurrence = occurrence
  state.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(occurrence)
  state.lastTransitionReason = reason
  FugSchedulerRuntime.clearRepeats(state)

  for actionIndex, eventAction in ipairs(occurrence.event.actions or {}) do
    if eventAction.enabled ~= false then
      FugSchedulerRuntime.executeEventAction(scheduler, occurrence, eventAction, actionIndex, reason)
    end
  end
  FugSchedulerRuntime.scheduleRepeats(state, occurrence, now)
end

-- Activate the already-current Event after lifecycle or configuration transitions.
-- When optionName is nil, every enabled stateful Action reconciles immediately.
function FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, state, occurrence, optionName, reason, now)
  state.activeOccurrence = occurrence
  state.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(occurrence)
  state.lastTransitionReason = reason
  FugSchedulerRuntime.clearRepeats(state)
  if not occurrence then return end

  for actionIndex, eventAction in ipairs(occurrence.event.actions or {}) do
    if eventAction.enabled ~= false and not eventAction.oneShot and
        (optionName == nil or eventAction[optionName] == true) then
      FugSchedulerRuntime.executeEventAction(scheduler, occurrence, eventAction, actionIndex, reason)
    end
  end
  FugSchedulerRuntime.scheduleRepeats(state, occurrence, now)
end

-- Run due repeats once and reschedule from now so delayed polls never create callback bursts.
function FugSchedulerRuntime.processRepeats(scheduler, state, currentOccurrence, now)
  if not currentOccurrence or state.activeOccurrenceKey ~= FugSchedulerRuntime.occurrenceKey(currentOccurrence) then return end

  for actionIndex, eventAction in ipairs(currentOccurrence.event.actions or {}) do
    local repeatState = state.repeatDeadlines[actionIndex]
    local shouldRepeat = eventAction.enabled ~= false and not eventAction.oneShot and eventAction.repeatSeconds ~= nil
    local repeatMatches = repeatState and repeatState.actionId == eventAction.actionId and
      repeatState.repeatSeconds == eventAction.repeatSeconds
    if shouldRepeat and not repeatMatches then
      state.repeatDeadlines[actionIndex] = {
        due = now + eventAction.repeatSeconds,
        actionId = eventAction.actionId,
        repeatSeconds = eventAction.repeatSeconds
      }
    elseif not shouldRepeat then
      state.repeatDeadlines[actionIndex] = nil
    end
  end

  for actionIndex, repeatState in pairs(state.repeatDeadlines or {}) do
    local eventAction = currentOccurrence.event.actions[actionIndex]
    local assignmentStillMatches = eventAction and eventAction.enabled ~= false and not eventAction.oneShot and
      eventAction.actionId == repeatState.actionId and eventAction.repeatSeconds == repeatState.repeatSeconds
    if not assignmentStillMatches then
      state.repeatDeadlines[actionIndex] = nil
    elseif repeatState.due <= now then
      FugSchedulerRuntime.executeEventAction(scheduler, currentOccurrence, eventAction, actionIndex, "repeat")
      repeatState.due = now + eventAction.repeatSeconds
    end
  end
end

-- Process one Scheduler from its cached cursor; this is the only steady-state execution path.
function FugSchedulerRuntime.processSchedulerExecution(plan)
  local scheduler = plan.scheduler
  local now = os.time()
  local automaticEnabled = FugSchedulerRuntime.automaticExecutionEnabled()
  local allowed = automaticEnabled and scheduler.enabled and not scheduler.paused

  if not plan.initialized then
    FugSchedulerRuntime.positionPlanCursor(plan, now)
    plan.initialized = true
    plan.lastObservedTimestamp = now
    plan.lastEnabled = scheduler.enabled
    plan.lastPaused = scheduler.paused
    plan.lastAutomaticEnabled = automaticEnabled
    plan.activeOccurrence = plan.currentOccurrence
    plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
    plan.lastTransitionReason = "Initialized"
    if allowed then
      FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnStartup", "startup", now)
    end
    return
  end

  local elapsed = now - plan.lastObservedTimestamp
  if elapsed < 0 then
    FugSchedulerRuntime.positionPlanCursor(plan, now)
    plan.activeOccurrence = plan.currentOccurrence
    plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
    plan.lastTransitionReason = "Clock moved backwards"
    FugSchedulerRuntime.clearRepeats(plan)
    FugSchedulerRuntime.setExecutionMessage(
      "Clock moved backwards; execution state reset without replay",
      LogLevel.INFO,
      {schedulerLabel = scheduler.label, schedulerId = scheduler.id, reason = "clock moved backwards"}
    )
  elseif elapsed > FugSchedulerRuntime.normalEdgeMaxDelaySeconds then
    FugSchedulerRuntime.positionPlanCursor(plan, now)
    plan.activeOccurrence = plan.currentOccurrence
    plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
    FugSchedulerRuntime.clearRepeats(plan)
    if allowed then
      FugSchedulerRuntime.restoreCurrentOccurrence(
        scheduler,
        plan,
        plan.currentOccurrence,
        "fireOnStartup",
        "forward clock jump or delayed poll",
        now
      )
    else
      plan.lastTransitionReason = "Forward clock jump while execution blocked"
    end
    FugSchedulerRuntime.setExecutionMessage(
      string.format("%s skipped historical one-shots after a %d-second clock discontinuity", scheduler.label, elapsed),
      LogLevel.INFO,
      {schedulerLabel = scheduler.label, schedulerId = scheduler.id, reason = "clock discontinuity"}
    )
  else
    local crossed = FugSchedulerRuntime.advancePlanCursor(plan, plan.lastObservedTimestamp, now)
    if not automaticEnabled or not scheduler.enabled then
      plan.activeOccurrence = plan.currentOccurrence
      plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
      plan.lastTransitionReason = not scheduler.enabled and "Scheduler disabled" or "Automatic execution disabled"
      FugSchedulerRuntime.clearRepeats(plan)
    elseif scheduler.paused then
      plan.activeOccurrence = plan.currentOccurrence
      plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
      plan.lastTransitionReason = "Scheduler paused"
      FugSchedulerRuntime.clearRepeats(plan)
    elseif plan.lastAutomaticEnabled == false and automaticEnabled then
      FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnStartup", "startup", now)
    elseif plan.lastEnabled == false and scheduler.enabled then
      FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnStartup", "enabled", now)
    elseif plan.lastPaused == true and not scheduler.paused then
      FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnResume", "resume", now)
    else
      for _, occurrence in ipairs(crossed) do
        FugSchedulerRuntime.executeOccurrence(scheduler, plan, occurrence, "scheduled edge", now)
      end
      if #crossed == 0 then
        plan.activeOccurrence = plan.currentOccurrence
        plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
      end
      FugSchedulerRuntime.processRepeats(scheduler, plan, plan.currentOccurrence, now)
    end
  end

  plan.lastObservedTimestamp = now
  plan.lastEnabled = scheduler.enabled
  plan.lastPaused = scheduler.paused
  plan.lastAutomaticEnabled = automaticEnabled
end

-- Measure and isolate one Scheduler timer callback without logging routine polls.
function FugSchedulerRuntime.pollRuntimePlan(schedulerId, generation)
  local plan = FugSchedulerRuntime.runtimePlans[schedulerId]
  if not plan or plan.generation ~= generation then return end
  local started = Timer.Now()
  local previousOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
  local previousTransitionReason = plan.lastTransitionReason
  if plan.lastPollElapsedTime and started - plan.lastPollElapsedTime > FugSchedulerRuntime.executionPollSeconds * 1.5 then
    plan.metrics.delayedPollCount = plan.metrics.delayedPollCount + 1
  end
  plan.lastPollElapsedTime = started

  local processOk, processError = pcall(FugSchedulerRuntime.processSchedulerExecution, plan)
  local duration = math.max(0, Timer.Now() - started)
  plan.metrics.pollCount = plan.metrics.pollCount + 1
  plan.metrics.totalPollDuration = plan.metrics.totalPollDuration + duration
  if duration > plan.metrics.maximumPollDuration then plan.metrics.maximumPollDuration = duration end

  if processOk and (previousOccurrenceKey ~= FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence) or
      previousTransitionReason ~= plan.lastTransitionReason) then
    FugSchedulerRuntime.publishLiveRuntimeStatus()
  elseif not processOk then
    plan.lastCallbackResult = "Execution error: " .. tostring(processError)
    FugSchedulerRuntime.setExecutionMessage(
      "Execution error for Scheduler " .. schedulerId .. ": " .. tostring(processError),
      LogLevel.ERROR,
      {schedulerLabel = plan.scheduler.label, schedulerId = schedulerId},
      "Execution engine failed: " .. tostring(processError)
    )
  end
end

-- Keep orphaned callbacks from pre-plan hot loads harmless until their timer is collected.
function FugSchedulerRuntime.executionPoll()
end

-- Start one retained timer with a deliberate first-phase offset, then poll every second.
function FugSchedulerRuntime.startPlanTimer(plan, schedulerIndex, schedulerCount)
  local phase = 0.05 + (((schedulerIndex - 1) / math.max(1, schedulerCount)) * 0.90)
  plan.timerPhaseSeconds = phase
  plan.timerPhasePending = true
  plan.timer = Timer.New()
  local schedulerId, generation = plan.schedulerId, plan.generation
  plan.timer.EventHandler = function()
    FugSchedulerRuntime.pollRuntimePlan(schedulerId, generation)
  end
  Timer.CallAfter(function()
    local current = FugSchedulerRuntime.runtimePlans[schedulerId]
    if not current or current.generation ~= generation or not current.timer then return end
    current.timerPhasePending = false
    current.timer:Start(FugSchedulerRuntime.executionPollSeconds)
  end, phase)
end

-- Stop a replaced or deleted plan so its obsolete callback cannot process configuration.
function FugSchedulerRuntime.stopRuntimePlan(plan)
  if plan and plan.timer then plan.timer:Stop() end
  if plan then plan.timer = nil end
end

-- Reconcile a rebuilt plan against its prior Current occurrence without replaying one-shots.
function FugSchedulerRuntime.reconcileRuntimePlan(plan, previousPlan, now)
  if not previousPlan then return end
  FugSchedulerRuntime.positionPlanCursor(plan, now)

  plan.initialized = previousPlan.initialized
  plan.lastObservedTimestamp = now
  plan.lastEnabled = previousPlan.lastEnabled
  plan.lastPaused = previousPlan.lastPaused
  plan.lastAutomaticEnabled = previousPlan.lastAutomaticEnabled
  plan.lastCallbackResult = previousPlan.lastCallbackResult
  plan.activeOccurrence = plan.currentOccurrence
  plan.activeOccurrenceKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
  if not previousPlan.initialized then return end

  local scheduler = plan.scheduler
  local allowed = FugSchedulerRuntime.automaticExecutionEnabled() and scheduler.enabled and not scheduler.paused
  local previousKey = FugSchedulerRuntime.occurrenceKey(previousPlan.currentOccurrence)
  local currentKey = FugSchedulerRuntime.occurrenceKey(plan.currentOccurrence)
  if not allowed then
    FugSchedulerRuntime.clearRepeats(plan)
    plan.lastTransitionReason = scheduler.paused and "Scheduler paused" or "Execution blocked after plan rebuild"
  elseif previousPlan.scheduler.enabled == false and scheduler.enabled then
    FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnStartup", "enabled", now)
  elseif previousPlan.scheduler.paused == true and not scheduler.paused then
    FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, "fireOnResume", "resume", now)
  elseif previousKey ~= currentKey then
    FugSchedulerRuntime.restoreCurrentOccurrence(scheduler, plan, plan.currentOccurrence, nil, "schedule change", now)
  else
    plan.lastTransitionReason = "Plan rebuilt; Current occurrence unchanged"
    FugSchedulerRuntime.scheduleRepeats(plan, plan.currentOccurrence, now)
  end
end

-- Reuse unchanged plans and replace only changed, added, or deleted Scheduler plans.
function FugSchedulerRuntime.synchronizeRuntimePlans(schedule)
  local existing = FugSchedulerRuntime.runtimePlans
  local nextPlans = {}
  local now = os.time()
  local schedulerCount = #schedule.schedulers

  for schedulerIndex, scheduler in ipairs(schedule.schedulers) do
    local previousPlan = existing[scheduler.id]
    if previousPlan and FugSchedulerRuntime.persistedEqual(previousPlan.scheduler, scheduler) then
      previousPlan.scheduler = scheduler
      previousPlan.configurationRevision = schedule.revision
      nextPlans[scheduler.id] = previousPlan
    else
      local plan = FugSchedulerRuntime.createRuntimePlan(scheduler, schedule.revision)
      nextPlans[scheduler.id] = plan
      FugSchedulerRuntime.runtimePlans = nextPlans
      FugSchedulerRuntime.reconcileRuntimePlan(plan, previousPlan, now)
      if previousPlan then FugSchedulerRuntime.stopRuntimePlan(previousPlan) end
      FugSchedulerRuntime.startPlanTimer(plan, schedulerIndex, schedulerCount)
    end
  end

  for schedulerId, plan in pairs(existing) do
    if not nextPlans[schedulerId] then FugSchedulerRuntime.stopRuntimePlan(plan) end
  end
  FugSchedulerRuntime.runtimePlans = nextPlans
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
      fireOnResume = eventAction.fireOnResume == true,
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
  local executionState = FugSchedulerRuntime.executionState(scheduler.id)
  local repeatCount = 0
  for _ in pairs(executionState and executionState.repeatDeadlines or {}) do repeatCount = repeatCount + 1 end
  local metrics = executionState and executionState.metrics or {}
  local averagePollDuration = metrics.pollCount and metrics.pollCount > 0 and
    (metrics.totalPollDuration / metrics.pollCount) or 0
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
    execution = {
      allowed = FugSchedulerRuntime.automaticExecutionEnabled() and scheduler.enabled and not scheduler.paused,
      initialized = executionState and executionState.initialized or false,
      activeOccurrence = FugSchedulerRuntime.eventStatus(executionState and executionState.activeOccurrence or nil),
      activeRepeatCount = repeatCount,
      lastObservedTime = executionState and executionState.lastObservedTimestamp and
        os.date("%Y-%m-%d %H:%M:%S", executionState.lastObservedTimestamp) or nil,
      lastTransitionReason = executionState and executionState.lastTransitionReason or "No runtime plan",
      lastCallbackResult = executionState and executionState.lastCallbackResult or "None",
      planGeneration = executionState and executionState.generation or nil,
      configurationRevision = executionState and executionState.configurationRevision or nil,
      timerPhaseSeconds = executionState and executionState.timerPhaseSeconds or nil,
      performance = {
        pollCount = metrics.pollCount or 0,
        averagePollDurationSeconds = averagePollDuration,
        maximumPollDurationSeconds = metrics.maximumPollDuration or 0,
        delayedPollCount = metrics.delayedPollCount or 0,
        planRebuildDurationSeconds = metrics.planRebuildDuration or 0,
        eventCount = metrics.eventCount or 0,
        actionCount = metrics.actionCount or 0
      }
    },
    previousEvent = FugSchedulerRuntime.eventStatus(result.previous),
    currentEvent = FugSchedulerRuntime.eventStatus(result.current),
    nextEvent = FugSchedulerRuntime.eventStatus(result.next),
    nextTransitionSeconds = nextTimestamp and math.max(0, math.floor(nextTimestamp - result.timestamp)) or nil,
    nextTransitionCountdown = FugSchedulerRuntime.formatCountdown(result.timestamp, nextTimestamp)
  }
end

-- Publish the complete multi-Scheduler status snapshot for third-party integrations.
function FugSchedulerRuntime.publishGlobalStatus(timestamp, schedulerStatuses, hasResolutionError)
  local performance = {
    schedulerCount = 0,
    eventCount = 0,
    actionCount = 0,
    pollCount = 0,
    averagePollDurationSeconds = 0,
    maximumPollDurationSeconds = 0,
    delayedPollCount = 0,
    totalPlanRebuildDurationSeconds = 0
  }
  local totalPollDuration = 0
  for _, plan in pairs(FugSchedulerRuntime.runtimePlans) do
    local metrics = plan.metrics or {}
    performance.schedulerCount = performance.schedulerCount + 1
    performance.eventCount = performance.eventCount + (metrics.eventCount or 0)
    performance.actionCount = performance.actionCount + (metrics.actionCount or 0)
    performance.pollCount = performance.pollCount + (metrics.pollCount or 0)
    totalPollDuration = totalPollDuration + (metrics.totalPollDuration or 0)
    performance.maximumPollDurationSeconds = math.max(
      performance.maximumPollDurationSeconds,
      metrics.maximumPollDuration or 0
    )
    performance.delayedPollCount = performance.delayedPollCount + (metrics.delayedPollCount or 0)
    performance.totalPlanRebuildDurationSeconds = performance.totalPlanRebuildDurationSeconds +
      (metrics.planRebuildDuration or 0)
  end
  if performance.pollCount > 0 then
    performance.averagePollDurationSeconds = totalPollDuration / performance.pollCount
  end

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
    automaticExecutionEnabled = Controls.AutomaticExecutionEnabled and Controls.AutomaticExecutionEnabled.Boolean == true or false,
    performance = performance,
    schedulers = schedulerStatuses
  }

  FugSchedulerStatus = status
  FugSchedulerRuntime.globalStatus = status
  FugSchedulerRuntime.setText("GlobalSchedulerStatus", FugSchedulerRuntime.encodeJson(status))
  FugSchedulerRuntime.setText("SchedulerCount", tostring(#schedulerStatuses))
end

-- Publish live cached plan state after an execution/lifecycle transition without detached resolution.
function FugSchedulerRuntime.publishLiveRuntimeStatus()
  if not FugSchedulerRuntime.activeSchedule then return end
  if Controls.TestDateTime and (Controls.TestDateTime.String or "") ~= "" then return end
  local schedulerStatuses = {}
  local selectedScheduler, selectedResult = FugSchedulerRuntime.selectedScheduler(), nil
  local resolvedTimestamp = os.time()
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
    local plan = FugSchedulerRuntime.runtimePlans[scheduler.id]
    if plan then
      local timestamp = plan.lastObservedTimestamp or resolvedTimestamp
      local result = FugSchedulerRuntime.planResolutionResult(plan, timestamp)
      table.insert(schedulerStatuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, result, nil))
      if selectedScheduler and selectedScheduler.id == scheduler.id then selectedResult = result end
    end
  end
  FugSchedulerRuntime.publishGlobalStatus(resolvedTimestamp, schedulerStatuses, false)
  if selectedScheduler and selectedResult then FugSchedulerRuntime.publishResolution(selectedScheduler, selectedResult) end
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return false
  end

  local resultsById = {}
  local schedulerStatuses = {}
  local hasResolutionError = false
  for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
    local resolveOk, result = pcall(function()
      local plan = FugSchedulerRuntime.runtimePlans[scheduler.id]
      if requested == "" and plan and plan.currentOccurrence then
        return FugSchedulerRuntime.planResolutionResult(plan, timestamp)
      end
      return FugSchedulerRuntime.resolveAt(scheduler, timestamp)
    end)
    if resolveOk then
      resultsById[scheduler.id] = result
      table.insert(schedulerStatuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, result, nil))
    else
      hasResolutionError = true
      table.insert(schedulerStatuses, FugSchedulerRuntime.buildSchedulerStatus(scheduler, nil, result))
      FugSchedulerRuntime.logLine(
        "Resolution failed: " .. tostring(result),
        LogLevel.ERROR,
        {schedulerLabel = scheduler.label, schedulerId = scheduler.id}
      )
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
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return false
  end
  if decoded == nil then
    local message = "Schedule JSON error: " .. tostring(decodeError)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
    return false
  end

  local validated, warnings, validationError = FugSchedulerRuntime.validateSchedule(decoded)
  if not validated then
    local message = "Schedule validation error: " .. tostring(validationError)
    FugSchedulerRuntime.setText("ScheduleStatus", message)
    FugSchedulerRuntime.logLine(message, LogLevel.ERROR)
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

-- Refresh the aggregate plugin state and report whether automatic execution is armed.
function FugSchedulerRuntime.refreshStatus()
  local schedulerCount, enabledCount = 0, 0
  if FugSchedulerRuntime.activeSchedule then
    schedulerCount = #FugSchedulerRuntime.activeSchedule.schedulers
    for _, scheduler in ipairs(FugSchedulerRuntime.activeSchedule.schedulers) do
      if scheduler.enabled then enabledCount = enabledCount + 1 end
    end
  end
  local executionState = FugSchedulerRuntime.automaticExecutionEnabled() and "ARMED" or "OFF"
  FugSchedulerRuntime.setText("Status", string.format(
    "Scheduler ready; %d/%d Schedulers enabled; automatic execution %s",
    enabledCount,
    schedulerCount,
    executionState
  ))
end

-- Populate persistent presentation and logging preferences without touching schedule configuration.
function FugSchedulerRuntime.refreshPreferences(message)
  FugSchedulerRuntime.updatingPreferences = true

  local dateLabels = {DMY = "dd/mm/yyyy", MDY = "mm/dd/yyyy", ISO = "yyyy-mm-dd"}
  if Controls.DateFormatPreference then
    Controls.DateFormatPreference.Choices = {
      {Text = dateLabels.DMY, Id = "DMY"},
      {Text = dateLabels.MDY, Id = "MDY"},
      {Text = dateLabels.ISO, Id = "ISO"}
    }
    local format = FugSchedulerRuntime.dateFormatPreference()
    Controls.DateFormatPreference.String = FugSchedulerRuntime.encodeChoice(dateLabels[format], format)
  end

  local logChoices = {
    {Text = LogLevelLabels[LogLevel.DEBUG], Id = LogLevel.DEBUG},
    {Text = LogLevelLabels[LogLevel.INFO], Id = LogLevel.INFO},
    {Text = LogLevelLabels[LogLevel.ERROR], Id = LogLevel.ERROR},
    {Text = LogLevelLabels[LogLevel.OFF], Id = LogLevel.OFF}
  }
  local debugLevel = FugSchedulerRuntime.loggingLevel("DebugLogLevel", LogLevel.INFO)
  local eventLevel = FugSchedulerRuntime.loggingLevel("EventLogLevel", LogLevel.OFF)
  if Controls.DebugLogLevel then
    Controls.DebugLogLevel.Choices = logChoices
    Controls.DebugLogLevel.String = FugSchedulerRuntime.encodeChoice(LogLevelLabels[debugLevel], debugLevel)
  end
  if Controls.EventLogLevel then
    Controls.EventLogLevel.Choices = logChoices
    Controls.EventLogLevel.String = FugSchedulerRuntime.encodeChoice(LogLevelLabels[eventLevel], eventLevel)
  end

  FugSchedulerRuntime.updatingPreferences = false
  local format = FugSchedulerRuntime.dateFormatPreference()
  FugSchedulerRuntime.setText(
    "PreferencesStatus",
    message or string.format(
      "Date format: %s | Debug Output: %s | Event Log: %s | DiagnosticLog: all levels",
      dateLabels[format],
      LogLevelLabels[debugLevel],
      LogLevelLabels[eventLevel]
    )
  )
end

-- Attach handlers for Action loading, Schedule loading, and deterministic resolution tests.
function FugSchedulerRuntime.attachHandlers()
  if Controls.ActionSource then
    Controls.ActionSource.EventHandler = function() FugSchedulerRuntime.reloadActions() end
  end

  if Controls.AutomaticExecutionEnabled then
    Controls.AutomaticExecutionEnabled.EventHandler = function(control)
      if FugSchedulerRuntime.updatingExecutionControl then return end
      if control.Boolean then
        FugSchedulerRuntime.setExecutionMessage("Automatic execution armed; staggered Scheduler timers are initializing live state")
      else
        FugSchedulerRuntime.setExecutionMessage("Automatic execution disabled; callbacks and repeats are blocked")
        for _, plan in pairs(FugSchedulerRuntime.runtimePlans) do FugSchedulerRuntime.clearRepeats(plan) end
      end
      FugSchedulerRuntime.refreshStatus()
      FugSchedulerRuntime.resolveSelectedTime()
    end
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

  if Controls.EventActionEnabled then
    Controls.EventActionEnabled.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local enabled = control.Boolean
      FugSchedulerRuntime.updateSelectedEventAction("Event Action enabled state updated", function(eventAction)
        eventAction.enabled = enabled
      end)
    end
  end

  if Controls.EventActionMode then
    Controls.EventActionMode.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local mode = FugSchedulerRuntime.choiceId(control.String)
      FugSchedulerRuntime.updateSelectedEventAction("Event Action mode updated", function(eventAction)
        if mode == "OneShot" then
          eventAction.oneShot = true
          eventAction.fireOnStartup = false
          eventAction.fireOnResume = false
          eventAction.repeatSeconds = nil
        elseif mode == "Stateful" then
          eventAction.oneShot = false
        else
          return false, "Event Action mode must be Stateful or One Shot"
        end
      end)
    end
  end

  if Controls.EventActionFireOnStartup then
    Controls.EventActionFireOnStartup.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local enabled = control.Boolean
      FugSchedulerRuntime.updateSelectedEventAction("Startup restore option updated", function(eventAction)
        if eventAction.oneShot then return false, "one-shot Event Actions cannot restore on startup" end
        eventAction.fireOnStartup = enabled
      end)
    end
  end

  if Controls.EventActionFireOnResume then
    Controls.EventActionFireOnResume.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local enabled = control.Boolean
      FugSchedulerRuntime.updateSelectedEventAction("Resume restore option updated", function(eventAction)
        if eventAction.oneShot then return false, "one-shot Event Actions cannot restore on resume" end
        eventAction.fireOnResume = enabled
      end)
    end
  end

  if Controls.EventActionRepeatSeconds then
    Controls.EventActionRepeatSeconds.EventHandler = function(control)
      if FugSchedulerRuntime.updatingDayPatternEditor then return end
      local text = string.match(control.String or "", "^%s*(.-)%s*$") or ""
      FugSchedulerRuntime.updateSelectedEventAction("Repeat interval updated", function(eventAction)
        if eventAction.oneShot and text ~= "" then return false, "one-shot Event Actions cannot repeat" end
        if text == "" then
          eventAction.repeatSeconds = nil
          return
        end
        local seconds = tonumber(text)
        if not seconds or seconds <= 0 or seconds % 1 ~= 0 then
          return false, "repeat interval must be a positive whole number of seconds"
        end
        eventAction.repeatSeconds = seconds
      end)
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

  -- Validate and retain one destination's normalized numeric threshold selection.
  local function attachLogLevelHandler(controlName, destinationName)
    if not Controls[controlName] then return end
    Controls[controlName].EventHandler = function(control)
      if FugSchedulerRuntime.updatingPreferences then return end
      local selected = tonumber(FugSchedulerRuntime.choiceId(control.String))
      if not LogLevelLabels[selected] then
        FugSchedulerRuntime.refreshPreferences("Invalid " .. destinationName .. " level; restored its default")
        return
      end
      FugSchedulerRuntime.refreshPreferences(destinationName .. " level: " .. LogLevelLabels[selected])
      FugSchedulerRuntime.logLine(destinationName .. " level changed to " .. LogLevelLabels[selected])
    end
  end
  attachLogLevelHandler("DebugLogLevel", "Debug Output")
  attachLogLevelHandler("EventLogLevel", "Event Log")

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
  if Controls.EventActionMode then Controls.EventActionMode.Choices = {} end
  if Controls.WeekPatternSelect then Controls.WeekPatternSelect.Choices = {} end
  if Controls.OverrideSelect then Controls.OverrideSelect.Choices = {} end
  if Controls.OverrideType then Controls.OverrideType.Choices = {} end
  if Controls.OverridePattern then Controls.OverridePattern.Choices = {} end
  if Controls.DateFormatPreference then Controls.DateFormatPreference.Choices = {} end
  if Controls.DebugLogLevel then Controls.DebugLogLevel.Choices = {} end
  if Controls.EventLogLevel then Controls.EventLogLevel.Choices = {} end
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
  FugSchedulerRuntime.setText(
    "ExecutionStatus",
    FugSchedulerRuntime.automaticExecutionEnabled() and
      "Automatic execution is armed; waiting for live initialization" or
      "Automatic execution is disabled"
  )
  FugSchedulerRuntime.setText("ScheduleStatus", "Checking persisted ScheduleData")
  FugSchedulerRuntime.setText("SchedulerEditorStatus", "Waiting for a valid Scheduler configuration")
  FugSchedulerRuntime.setText("DayPatternEditorStatus", "Waiting for a valid Day Pattern configuration")
  FugSchedulerRuntime.setText("WeekPatternEditorStatus", "Waiting for a valid Week Pattern configuration")
  FugSchedulerRuntime.setText("OverrideEditorStatus", "Waiting for a valid Override configuration")
  FugSchedulerRuntime.setText("PreferencesStatus", "Loading preferences")
  FugSchedulerRuntime.setText("BuildDateDisplay", FugSchedulerRuntime.formatBuildDate(FugSchedulerPluginInfo.BuildTimestamp))
  FugSchedulerRuntime.refreshStatus()

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
  if Controls.DebugLogLevel and (Controls.DebugLogLevel.String or "") == "" then
    Controls.DebugLogLevel.String = FugSchedulerRuntime.encodeChoice("Info", LogLevel.INFO)
  end
  if Controls.EventLogLevel and (Controls.EventLogLevel.String or "") == "" then
    Controls.EventLogLevel.String = FugSchedulerRuntime.encodeChoice("Off", LogLevel.OFF)
  end
  FugSchedulerRuntime.refreshPreferences()
  FugSchedulerRuntime.logLine("FugScheduler 2000 scheduler runtime initialized.")

  FugSchedulerRuntime.reloadActions()
  FugSchedulerRuntime.scheduleInitialized = true
  FugSchedulerRuntime.reloadSchedule()
end

FugSchedulerRuntime.attachHandlers()
FugSchedulerRuntime.initialize()
