local date = require("date")
local json = require("rapidjson")

local siteMusicSnapshots = Component.New("SiteMusicSnapshots")
local siteMuteSnapshots = Component.New("SiteMuteSnapshots")
--local gateMusicSnapshots = Component.New("GateMusicSnapshots")
local bigWheelSnapshots = Component.New("BigWheelSnapshots")

local fadeX32sToValue = function(val)
    -- for i = 1, 1 do
    --     local x32Id = string.format("%02d", tostring(i))
    --     local x32 = Component.New("X32-" .. x32Id)
    --     local fadeTo = x32["DcaFadeTo " .. 1]
    --     local fader = x32["DcaFader " .. 1]
    --     local fadeTrigger = x32["DcaFadeTrigger " .. 1]
    --     local fadeAutoTrigger = x32["DcaFadeAutoEnable " .. 1]

    --     if fader.Value == val then
    --         print("Fader already at target value: " .. val .. " dB")
    --         return
    --     elseif fadeTo.Value ~= val and fadeAutoTrigger.Boolean then
    --         print("Auto fade enabled, setting fadeTo to: " .. val .. " dB")
    --         fadeTo.Value = val
    --     else
    --         print("Auto fade not enabled, triggering fade to: " .. val .. " dB")
    --         fadeTo.Value = val
    --         fadeTrigger:Trigger()
    --     end
    -- end
end

------------------------------------------------------------------------------
-- Configuration definitions
------------------------------------------------------------------------------
---
----------------- SITE MUSIC DEFINITIONS ------------------------------------------------

--- Event definitions
local MusicEvents = {
    Off = {
        label = "Music off",
        callback = function()
            -- print("Loading 'Off' preset")
            siteMusicSnapshots["load.1"]:Trigger()
            -- gateMusicSnapshots["load.1"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    Morning = {
        label = "Morning",
        callback = function()
            -- print("Loading 'Morning' preset")
            siteMusicSnapshots["load.2"]:Trigger()
            -- gateMusicSnapshots["load.2"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    Afternoon = {
        label = "Afternoon",
        callback = function()
            -- print("Loading 'Afternoon' preset")
            siteMusicSnapshots["load.3"]:Trigger()
            -- gateMusicSnapshots["load.3"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    Evening = {
        label = "Evening",
        callback = function()
            -- print("Loading 'Evening' preset")
            siteMusicSnapshots["load.4"]:Trigger()
            -- gateMusicSnapshots["load.4"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
}

--- Pattern definitions
local MusicPatterns = {
    Weekday = {
        label = "Standard Weekday",
        events = {
            { time = "09:40", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "22:00", event = "Off" },
        }
    },
    Weekend = {
        label = "Standard Weekend",
        events = {
            { time = "09:40", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "22:00", event = "Off" },
        }
    },
    Build = {
        label = "Build",
        events = {
            { time = "12:00", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "22:00", event = "Off" },
        }
    },
    TenOpen = {
        label = "10am Open",
        events = {
            { time = "09:40", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "21:59", event = "Off" },
        }
    },
    ElevenOpen = {
        label = "11am Open",
        events = {
            { time = "10:40", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "21:59", event = "Off" },
        }
    },
    TwelveOpen = {
        label = "Midday Open",
        events = {
            { time = "11:40", event = "Morning" },
            { time = "14:00", event = "Afternoon" },
            { time = "17:00", event = "Evening" },
            { time = "21:59", event = "Off" },
        }
    },
    Closed = {
        label = "Closed",
        events = {
            { time = "07:00", event = "Off" },
        }
    },
}

--- Default pattern mapping for days of the week
local MusicDefaultPatterns = {
    Mon = "ElevenOpen",
    Tue = "ElevenOpen",
    Wed = "ElevenOpen",
    Thu = "ElevenOpen",
    Fri = "ElevenOpen",
    Sat = "TenOpen",
    Sun = "TenOpen",
}

--- Special days mapping (YYYY-MM-DD) to pattern names
local MusicSpecialDays = {
    ["2025-11-11"] = "Build",
    ["2025-11-12"] = "Build",
    ["2025-11-13"] = "Build",
    ["2025-11-14"] = "Build",
    ["2025-11-17"] = "TwelveOpen",
    ["2025-11-18"] = "Closed", -- Tues
    ["2025-11-19"] = "TenOpen", -- Weds
    ["2025-11-24"] = "Closed", -- Mon
    ["2025-11-25"] = "Closed", -- Tues
    ["2025-11-26"] = "TwelveOpen", -- Weds
    ["2025-12-01"] = "TwelveOpen", -- Mon
    ["2025-12-02"] = "TwelveOpen", -- Tues
    ["2025-12-03"] = "TwelveOpen", -- Weds
    ["2025-12-19"] = "TenOpen", -- Fri
    ["2025-12-22"] = "TenOpen", -- Mon
    ["2025-12-23"] = "TenOpen", -- Tues
    ["2025-12-24"] = "TenOpen", -- Weds
    ["2025-12-25"] = "Closed", -- CHRISTMAS DAY
}

-------------- SITE MUTE DEFINITIONS ------------------------------------------------

--- Event definitions
local SiteMuteEvents = {
    MuteOn = {
        label = "Site muted",
        callback = function()
            -- print("Loading 'Site Muted' preset")
            siteMuteSnapshots["load.1"]:Trigger()
            fadeX32sToValue(-90)
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    MuteOff = {
        label = "Site unmuted",
        callback = function()
            -- print("Loading 'Site Unmuted' preset")
            siteMuteSnapshots["load.2"]:Trigger()
            fadeX32sToValue(0)
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    MuteNight = {
        label = "Overnight mute",
        callback = function()
            -- print("Loading 'Site Unmuted' preset")
            siteMuteSnapshots["load.3"]:Trigger()
            fadeX32sToValue(0)
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    }
}
--- Pattern definitions
local SiteMutePatterns = {
    Default = {
        label = "Standard Day",
        events = {
            { time = "08:30", event = "MuteOff" },
            -- { time = "22:00", event = "MuteOn" },
            { time = "22:00", event = "MuteNight" },
        }
    },
    Build = {
        label = "Build",
        events = {
            { time = "08:30", event = "MuteOff" },
            { time = "22:01", event = "MuteOn" },
        }
    },
}
--- Default pattern mapping for days of the week
local SiteMuteDefaultPatterns = {
    Mon = "Default",
    Tue = "Default",
    Wed = "Default",
    Thu = "Default",
    Fri = "Default",
    Sat = "Default",
    Sun = "Default",
}
--- Special days mapping (YYYY-MM-DD) to pattern names
local SiteMuteSpecialDays = {
    ["2025-11-11"] = "Build",
    ["2025-11-12"] = "Build",

}

-------------- ICE RINK DEFINITIONS ------------------------------------------------

local iceRinkPlaybackController = Component.New("IceRinkMessageController")

--- Event definitions
--- These are 'oneShot' events becasue they must only be fired at the time
local IceRinkEvents = {
    Announcement15Mins = {
        label = "15 Mins Warning",
        oneShot = true,
        callback = function()
            -- print("Playing '15min' announcement")
            iceRinkPlaybackController["FileTrigger 1"]:Trigger()
        end
    },
    Announcement10Mins = {
        label = "10 Mins Warning",
        oneShot = true,
        callback = function()
            -- print("Playing '10min' announcement")
            iceRinkPlaybackController["FileTrigger 2"]:Trigger()
        end
    },
    Announcement5Mins = {
        label = "5 Mins Warning",
        oneShot = true,
        callback = function()
            -- print("Playing '5min' announcement")
            iceRinkPlaybackController["FileTrigger 3"]:Trigger()
        end
    },
    AnnouncementSessionEnd = {
        label = "Session End",
        oneShot = true,
        callback = function()
            -- print("Playing 'Session End' announcement")
            iceRinkPlaybackController["FileTrigger 4"]:Trigger()
        end
    },
}

--- Pattern definitions
local IceRinkPatterns = {
    Default = {
        label = "Standard Day",
        events = {
            { time = "10:30", event = "Announcement15Mins" },
            { time = "10:35", event = "Announcement10Mins" },
            { time = "10:40", event = "Announcement5Mins" },
            { time = "10:45", event = "AnnouncementSessionEnd" },

            { time = "11:30", event = "Announcement15Mins" },
            { time = "11:35", event = "Announcement10Mins" },
            { time = "11:40", event = "Announcement5Mins" },
            { time = "11:45", event = "AnnouncementSessionEnd" },

            { time = "12:30", event = "Announcement15Mins" },
            { time = "12:35", event = "Announcement10Mins" },
            { time = "12:40", event = "Announcement5Mins" },
            { time = "12:45", event = "AnnouncementSessionEnd" },

            { time = "13:30", event = "Announcement15Mins" },
            { time = "13:35", event = "Announcement10Mins" },
            { time = "13:40", event = "Announcement5Mins" },
            { time = "13:45", event = "AnnouncementSessionEnd" },

            { time = "14:30", event = "Announcement15Mins" },
            { time = "14:35", event = "Announcement10Mins" },
            { time = "14:40", event = "Announcement5Mins" },
            { time = "14:45", event = "AnnouncementSessionEnd" },

            { time = "15:30", event = "Announcement15Mins" },
            { time = "15:35", event = "Announcement10Mins" },
            { time = "15:40", event = "Announcement5Mins" },
            { time = "15:45", event = "AnnouncementSessionEnd" },

            { time = "16:30", event = "Announcement15Mins" },
            { time = "16:35", event = "Announcement10Mins" },
            { time = "16:40", event = "Announcement5Mins" },
            { time = "16:45", event = "AnnouncementSessionEnd" },

            { time = "17:30", event = "Announcement15Mins" },
            { time = "17:35", event = "Announcement10Mins" },
            { time = "17:40", event = "Announcement5Mins" },
            { time = "17:45", event = "AnnouncementSessionEnd" },

            { time = "18:30", event = "Announcement15Mins" },
            { time = "18:35", event = "Announcement10Mins" },
            { time = "18:40", event = "Announcement5Mins" },
            { time = "18:45", event = "AnnouncementSessionEnd" },

            { time = "19:30", event = "Announcement15Mins" },
            { time = "19:35", event = "Announcement10Mins" },
            { time = "19:40", event = "Announcement5Mins" },
            { time = "19:45", event = "AnnouncementSessionEnd" },

            { time = "20:30", event = "Announcement15Mins" },
            { time = "20:35", event = "Announcement10Mins" },
            { time = "20:40", event = "Announcement5Mins" },
            { time = "20:45", event = "AnnouncementSessionEnd" },

            { time = "21:30", event = "Announcement15Mins" },
            { time = "21:35", event = "Announcement10Mins" },
            { time = "21:40", event = "Announcement5Mins" },
            { time = "21:45", event = "AnnouncementSessionEnd" },
        }
    },
}

--- Default pattern mapping for days of the week
local IceRinkDefaultPatterns = {
    Mon = "Default",
    Tue = "Default",
    Wed = "Default",
    Thu = "Default",
    Fri = "Default",
    Sat = "Default",
    Sun = "Default",
}

--- Special days mapping (YYYY-MM-DD) to pattern names
local IceRinkSpecialDays = {
    -- ["2025-12-25"] = "Weekend",
}

-------------- BIG WHEEL DEFINITIONS ------------------------------------------------

--- Event definitions
local BigWheelEvents = {
    Default = {
        label = "Default",
        callback = function()
            -- print("Big Wheel Default")
            -- siteMuteSnapshots["load.1"]:Trigger()
            -- fadeX32sToValue(-90)
            bigWheelSnapshots["load.1"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    LightShow = {
        label = "Light Show",
        callback = function()
            -- print("Big Wheel Light Show")
            -- siteMuteSnapshots["load.2"]:Trigger()
            -- fadeX32sToValue(0)
            bigWheelSnapshots["load.2"]:Trigger()
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    }
}
--- Pattern definitions
local BigWheelPatterns = {
    Default = {
        label = "Standard Day",
        events = {
            { time = "09:00", event = "Default" },
            -- -- 17:15
            -- { time = "17:15", event = "LightShow" },
            -- { time = "17:27", event = "Default" },
            -- -- 18:15
            -- { time = "18:15", event = "LightShow" },
            -- { time = "18:27", event = "Default" },
            -- -- 19:15
            -- { time = "19:15", event = "LightShow" },
            -- { time = "19:27", event = "Default" },
            -- -- 20:15
            -- { time = "20:15", event = "LightShow" },
            -- { time = "20:27", event = "Default" },

            -- 19:00
            { time = "19:00", event = "LightShow" },
            { time = "19:12", event = "Default" },
        }
    },
}
--- Default pattern mapping for days of the week
local BigWheelPatternDefaults = {
    Mon = "Default",
    Tue = "Default",
    Wed = "Default",
    Thu = "Default",
    Fri = "Default",
    Sat = "Default",
    Sun = "Default",
}
--- Special days mapping (YYYY-MM-DD) to pattern names
local BigWheelSpecialDays = {
    -- ["2025-11-11"] = "Build",
    -- ["2025-11-12"] = "Build",

}

-------------- DE-ICER DEFINITIONS ------------------------------------------------
DeIcerMixer = Component.New("DeIcerMixer")
--- Event definitions
local DeIcerEvents = {
    On = {
        label = "De-Icer On",
        callback = function()
            DeIcerMixer["group.1.mute"].Boolean = false
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    },
    Off = {
        label = "De-Icer Off",
        callback = function()
            DeIcerMixer["group.1.mute"].Boolean = true
        end,
        fireOnStartup = true,
        repeatSeconds = 300,
    }
}
--- Pattern definitions
local DeIcerPatterns = {
    Default = {
        label = "Default Pattern",
        events = {
            { time = "22:30", event = "On" },
            { time = "08:30", event = "Off" },
        }
    },
}
--- Default pattern mapping for days of the week
local DeIcerDefaultPatterns = {
    Mon = "Default",
    Tue = "Default",
    Wed = "Default",
    Thu = "Default",
    Fri = "Default",
    Sat = "Default",
    Sun = "Default",
}
--- Special days mapping (YYYY-MM-DD) to pattern names
local DeIcerSpecialDays = {
    -- ["2025-11-11"] = "Build",
    -- ["2025-11-12"] = "Build",

}

------------------------------------------------------------------------------
-- Scheduler implementation
------------------------------------------------------------------------------
local SchedulerLogLevel = {
    Error = "Error",
    Info = "Info",
    Debug = "Debug",
}

--- EventTrigger class  --------------------------------------------------------------

local EventTrigger = {}
EventTrigger.__index = EventTrigger

function EventTrigger.new(eventDef, cfg)
    local self = setmetatable({}, EventTrigger)

    self.eventDef = eventDef
    self.repeatTriggerTimer = nil

    self.active = false
    self.paused = false

    self.logCallback = cfg and cfg.logCallback or nil

    -- Wrap the callback to check for pause state and handle errors
    self.evtCbWrapped = function()
        if not self.paused then
            self:_log(SchedulerLogLevel.Info, "TRIGGERING EVENT: \"" ..
                self.eventDef.label .. "\" at " .. date():fmt("%Y-%m-%d %H:%M:%S"))
            local ok, err = pcall(self.eventDef.callback)
            if not ok then
                self:_log(SchedulerLogLevel.Error,
                    "Error firing event callback for " .. self.eventDef.label .. ": " .. err)
            end
        end
    end

    return self
end

function EventTrigger:start(pausedOnStart)
    if self.eventDef.repeatSeconds then
        self:_log(SchedulerLogLevel.Debug, "Configuring repeat timer for event: " ..
            self.eventDef.label .. " every " .. self.eventDef.repeatSeconds .. " seconds")
        self.repeatTriggerTimer = Timer.New()
        self.repeatTriggerTimer.EventHandler = self.evtCbWrapped
    end
    self:setPause(pausedOnStart)

    self.active = true

    if not self.paused then
        self:_runStartupActions()
    elseif self.eventDef.oneShot then
        -- If we are paused when we are started, then we have missed our one shot, so set this trigger as inactive
        self.active = false
    end
end

function EventTrigger:stop()
    -- Implementation for stopping the event trigger
    if self.repeatTriggerTimer then
        self.repeatTriggerTimer:Stop()
    end
    self.active = false
end

function EventTrigger:_runStartupActions()
    if not self.active then return end -- Return early if we have been made inactive

    -- Handle 'oneShot' events
    if self.eventDef.oneShot and not self.paused then
        self.evtCbWrapped()
        self.active = false
        return
    end

    -- If we have repeats then start the timer
    if self.eventDef.repeatSeconds then
        self.repeatTriggerTimer:Start(self.eventDef.repeatSeconds)
    end

    -- Fire repeated + single events immediately on startup if configured to do so
    if (self.eventDef.repeatSeconds or self.eventDef.fireOnStartup) and not self.paused then
        self.evtCbWrapped()
    end
end

function EventTrigger:setPause(pause)
    if self.paused == false and pause == true then
        -- Going from unpaused to paused
        self.paused = true
        -- print("Pausing event trigger: " .. self.eventDef.label)
        self:_log(SchedulerLogLevel.Debug, "Pausing event trigger: " .. self.eventDef.label)
        if self.repeatTriggerTimer then
            self.repeatTriggerTimer:Stop()
        end
    elseif self.paused == true and pause == false then
        -- Going from paused to unpaused
        self.paused = false
        if self.active then
            -- print("Resuming event trigger: " .. self.eventDef.label)
            self:_log(SchedulerLogLevel.Debug, "Resuming event trigger: " .. self.eventDef.label)
            -- Run startup actions
            self:_runStartupActions()
        end
    end
end

function EventTrigger:_log(level, msg)
    if self.logCallback then
        self.logCallback(level, msg)
    end
end

--- FugScheduler class  --------------------------------------------------------------
local FugScheduler = {}
FugScheduler.__index = FugScheduler

function FugScheduler.new(cfg)
    local self = setmetatable({}, FugScheduler)
    self.name = cfg.name or "Fug Scheduler"
    self.events = cfg.events or {}
    self.patterns = cfg.patterns or {}
    self.defaultPatterns = cfg.defaultPatterns or {}
    self.specialDays = cfg.specialDays or {}

    self.pollInterval = cfg.pollInterval or 1
    self.logCallback = cfg.logCallback or nil

    self.currentPattern = nil

    self.currentEvent = nil
    self.nextEvent = nil
    self.previousEvent = nil
    -- self.currentEventStartTime = nil

    self.currentEventTrigger = nil

    self.pollTimer = nil

    self.paused = false
    self.started = false
    self.firstPollComplete = false -- So we can provide initial status update etc after first poll only

    self.statusUpdateCallback = nil

    return self
end

function FugScheduler:start()
    self.pollTimer = Timer.New()
    self.pollTimer.EventHandler = function() self:_poll() end

    self:_log(SchedulerLogLevel.Info, "Started with poll interval: " .. self.pollInterval .. " seconds")

    self:initEventScheduling()

    self.pollTimer:Start(self.pollInterval)

    self.started = true
    -- Update status for listeners
    self:callStatusUpdate()
end

function FugScheduler:_eventTriggerLogHandler(level, msg)
    self:_log(level, "(EventTrigger) " .. msg)
end

function FugScheduler:initEventScheduling()
    self:updateEventScheduling()
    if self.currentEvent then
        self.currentEventTrigger = EventTrigger.new(self.currentEvent,
            { logCallback = function(level, msg) self:_eventTriggerLogHandler(level, msg) end })
        -- Make sure we don't trigger a 'oneShot' / edge triggered event.  This should only be triggered once
        if not self.currentEventTrigger.eventDef.oneShot then
            self.currentEventTrigger:start(self.paused)
        end
    end
end

function FugScheduler:updateEventScheduling()
    -- Determine current and next events
    if self.nextEvent and self.currentEvent then
        -- Shuffle along
        self.previousEvent = self.currentEvent
        self.currentEvent = self.nextEvent

        -- Get next event
        local nextEvent, nextEventTime = self:getNextEvent()
        self.nextEvent = nextEvent
        self.nextEvent.scheduledStartTime = nextEventTime
    else
        local currentEvent, currentEventStart = self:getCurrentEvent()
        local nextEvent, nextEventStart = self:getNextEvent()

        if currentEvent then
            self.currentEvent = currentEvent
            self.currentEvent.scheduledStartTime = currentEventStart
        end
        if nextEvent then
            self.nextEvent = nextEvent
            self.nextEvent.scheduledStartTime = nextEventStart
        end
    end
end

-- Internal polling method
function FugScheduler:_poll()
    local now = date()

    -- Set the pattern definition for today
    -- self.currentPattern = self:getPattern(now)
    local newPattern = self:getPattern(now)
    if self.currentPattern ~= newPattern then
      self.currentPattern = newPattern
      self:_log(SchedulerLogLevel.Info, "New pattern loaded: " .. self.currentPattern.label)
      self:callStatusUpdate()
    end

    -- Check which event (definition) should be running now.
    if self.nextEvent then
        if now >= self.nextEvent.scheduledStartTime then
            -- Time to switch to the next event
            self.currentEventTrigger:stop()
            -- print("Stopping event trigger: " .. self.currentEventTrigger.eventDef.label)
            self:_log(SchedulerLogLevel.Info, "Stopping event: " .. self.currentEventTrigger.eventDef
                .label)

            -- Create + start a new one for the next event
            -- print("Starting event trigger: " .. self.nextEvent.label)
            self:_log(SchedulerLogLevel.Info, "Starting event: " .. self.nextEvent.label)

            self.currentEventTrigger = EventTrigger.new(self.nextEvent,
                { logCallback = function(level, msg) self:_eventTriggerLogHandler(level, msg) end })
            self.currentEventTrigger:start(self.paused)

            self:updateEventScheduling()

            -- Update status for listeners
            self:callStatusUpdate()
        end
    end

    if not self.firstPollComplete then
        self:callStatusUpdate()
        self.firstPollComplete = true
    end

    -- local eventToRun, eventTimeToRun = self:getCurrentEvent()

    -- -- If the event has changed, stop the old event trigger and start the new one
    -- if eventToRun ~= nil and eventToRun ~= self.currentEvent then
    --     if self.currentEventTrigger then
    --         print("Stopping event trigger: " .. self.currentEventTrigger.eventDef.label)
    --         self.currentEventTrigger:stop()
    --         self.currentEventTrigger = nil
    --     end

    --     print("Starting event trigger: " .. eventToRun.label)
    --     self.currentEventTrigger = EventTrigger.new(eventToRun)
    --     self.currentEventTrigger:start(self.paused)

    --     self.currentEvent = eventToRun
    --     -- self.currentEventStartTime = eventTimeToRun

    --     -- Update status for listeners
    --     self:callStatusUpdate()
    -- end
end

function FugScheduler:getPattern(now)
    -- Determine the current pattern for today
    local todayStr = now:fmt("%Y-%m-%d")

    local patternName = self.specialDays[todayStr] or self.defaultPatterns[now:fmt("%a")]

    return self.patterns[patternName]
end

function FugScheduler:getEventByTime(now, pattern)
    -- Determine which event should be active now based on the pattern
    local eventToRun = nil
    local eventTimeToRun = nil
    for _, evtEntry in ipairs(pattern.events) do
        local evtTime = date(now:fmt("%Y-%m-%d") .. " " .. evtEntry.time)
        if now >= evtTime then
            if not eventTimeToRun or evtTime > eventTimeToRun then
                eventToRun = self.events[evtEntry.event]
                eventTimeToRun = evtTime
            end
        end
    end

    return eventToRun, eventTimeToRun
end

-- Get the current event based on current time, even if it started on the previous day
function FugScheduler:getCurrentEvent()
    local now = date()
    local currentPattern = self:getPattern(now)
    local eventToRun, eventTimeToRun = self:getEventByTime(now, currentPattern)

    if eventToRun then
        return eventToRun, eventTimeToRun
    else
        -- Look to previous day's pattern
        local yesterday = date():adddays(-1)
        local yesterdayPattern = self:getPattern(yesterday)
        local lastEvtEntry = nil
        local lastEvtTime = nil
        for _, evtEntry in ipairs(yesterdayPattern.events) do
            local evtTime = date(yesterday:fmt("%Y-%m-%d") .. " " .. evtEntry.time)
            if not lastEvtEntry or evtTime > date(yesterday:fmt("%Y-%m-%d") .. " " .. lastEvtEntry.time) then
                lastEvtEntry = evtEntry
                lastEvtTime = evtTime
            end
        end
        if lastEvtEntry then
            return self.events[lastEvtEntry.event], lastEvtTime
        end
    end
end

-- Get the previous event, even if it was the day before
function FugScheduler:getPreviousEvent()
    local now = date()
    local currentPattern = self:getPattern(now)
    local previousPattern = self:getPattern(date():adddays(-1))
    local lastEvtEntry = nil
    local lastEvtTime = nil
    for _, evtEntry in ipairs(currentPattern.events) do
        local evtTime = date(now:fmt("%Y-%m-%d") .. " " .. evtEntry.time)
        if now > evtTime then
            if not lastEvtEntry or evtTime > date(now:fmt("%Y-%m-%d") .. " " .. lastEvtEntry.time) then
                lastEvtEntry = evtEntry
                lastEvtTime = evtTime
            end
        end
    end
    if lastEvtEntry then
        return self.events[lastEvtEntry.event], lastEvtTime
    else
        -- Look in previous day's pattern
        for _, evtEntry in ipairs(previousPattern.events) do
            local evtTime = date(date():adddays(-1):fmt("%Y-%m-%d") .. " " .. evtEntry.time)
            if not lastEvtEntry or evtTime > date(date():adddays(-1):fmt("%Y-%m-%d") .. " " .. lastEvtEntry.time) then
                lastEvtEntry = evtEntry
                lastEvtTime = evtTime
            end
        end
        if lastEvtEntry then
            return self.events[lastEvtEntry.event], lastEvtTime
        end
    end
end

-- Get the next event, even if it is the next day
function FugScheduler:getNextEvent()
    local now = date()
    local currentPattern = self:getPattern(now)
    local nextPattern = self:getPattern(date():adddays(1))
    local nextEvtEntry = nil
    local nextEvtTime = nil
    for _, evtEntry in ipairs(currentPattern.events) do
        local evtTime = date(now:fmt("%Y-%m-%d") .. " " .. evtEntry.time)
        if now < evtTime then
            if not nextEvtEntry or evtTime < nextEvtTime then
                nextEvtEntry = evtEntry
                nextEvtTime = evtTime
            end
        end
    end

    -- If we have found a next event today, return it, otherwise look to tomorrow
    if nextEvtEntry then
        -- print('next', nextEvtEntry.event, nextEvtTime:fmt("%Y-%m-%d %H:%M:%S"))

        return self.events[nextEvtEntry.event], nextEvtTime
    else
        -- Look in next day's pattern
        for _, evtEntry in ipairs(nextPattern.events) do
            local evtTime = date(date():adddays(1):fmt("%Y-%m-%d") .. " " .. evtEntry.time)
            if not nextEvtEntry or evtTime < nextEvtTime then
                nextEvtEntry = evtEntry
                nextEvtTime = evtTime
            end
        end
        if nextEvtEntry then
            -- print('next', nextEvtEntry.event, nextEvtTime:fmt("%Y-%m-%d %H:%M:%S"))
            return self.events[nextEvtEntry.event], nextEvtTime
        end
    end
end

function FugScheduler:setPause(pause)
    self.paused = pause

    if self.currentEventTrigger then
        self.currentEventTrigger:setPause(pause)
    end
    -- Update status for listeners
    if self.started then
        if self.paused then
            self:_log(SchedulerLogLevel.Info, "Scheduler paused")
            -- print(self.name .. " paused")
        else
            self:_log(SchedulerLogLevel.Info, "Scheduler resumed")
            -- print(self.name .. " resumed")
        end
        self:callStatusUpdate()
    end
end

-- Introspection methods
function FugScheduler:isPaused()
    return self.paused
end

function FugScheduler:buildStatus()
    -- local now = date()

    -- local currentEvent, currentEventStartTime = self:getCurrentEvent()
    -- local nextEvent, nextEventStartTime = self:getNextEvent()
    local currentEvent = self.currentEvent
    local currentEventStartTime = self.currentEvent.scheduledStartTime

    local nextEvent = self.nextEvent
    local nextEventStartTime = self.nextEvent.scheduledStartTime

    local prevEvent, prevEventStartTime
    if self.previousEvent then
        prevEvent = self.previousEvent
        prevEventStartTime = self.previousEvent.scheduledStartTime
    else
        prevEvent, prevEventStartTime = self:getPreviousEvent()
    end

    local status = {
        paused = self.paused,
        currentPattern = {
            label = self.currentPattern and self.currentPattern.label or "None",
            events = self.currentPattern and self.currentPattern.events or {}
        },
        currentEvent = {
            label = currentEvent and currentEvent.label or "None",
            repeatSeconds = currentEvent and currentEvent.repeatSeconds or "N/A",
            fireOnStartup = currentEvent and currentEvent.fireOnStartup or "N/A",
            startTime = currentEventStartTime and currentEventStartTime:fmt("%Y-%m-%d %H:%M:%S") or "N/A",
        },
        nextEvent = {
            label = nextEvent and nextEvent.label or "None",
            repeatSeconds = nextEvent and nextEvent.repeatSeconds or "N/A",
            fireOnStartup = nextEvent and nextEvent.fireOnStartup or "N/A",
            startTime = nextEventStartTime and nextEventStartTime:fmt("%Y-%m-%d %H:%M:%S") or "N/A",
        },
        previousEvent = {
            label = prevEvent and prevEvent.label or "None",
            repeatSeconds = prevEvent and prevEvent.repeatSeconds or "N/A",
            fireOnStartup = prevEvent and prevEvent.fireOnStartup or "N/A",
            startTime = prevEventStartTime and prevEventStartTime:fmt("%Y-%m-%d %H:%M:%S") or "N/A",
        }
    }
    return status
end

function FugScheduler:callStatusUpdate()
    if not self.statusUpdateCallback then return end
    local cb = function()
        local status = self:buildStatus()
        if self.statusUpdateCallback then
            local ok, err = pcall(function() self.statusUpdateCallback(status) end)
            if not ok then
                self:_log("Error", "Error in status update callback: " .. err)
            end
        end
    end
    Timer.CallAfter(cb, 0.500)
end

function FugScheduler:_log(level, msg)
    if self.logCallback then
        self.logCallback(level, msg)
    end
end

--- Main script execution  --------------------------------------------------------------

-------------------- Logging --------------------
LogLevel = {
    Debug = 1,
    Info = 2,
    Error = 3,
    Off = 4
}

EventLogLevel = {}
DebugLogLevel = {}

GlobalEventLogLevel = LogLevel.Info
GlobalDebugLogLevel = LogLevel.Info

function buildLogMessage(level, msg)
    -- local msgs = { ... }
    -- local msg = ""
    -- for k, v in ipairs(msgs) do
    --     msg = msg .. " " .. v
    -- end

    return "[" .. level:upper() .. "]: " .. msg
end

function addEventLogPrefix(msg)
    -- return "X32 (" .. Controls.IpAddress.String .. ") " .. msg
    return msg
end

function logError(msg, idx)
    local eventLogLevel = idx and EventLogLevel[idx] or GlobalEventLogLevel
    local debugLogLevel = idx and DebugLogLevel[idx] or GlobalDebugLogLevel
    if eventLogLevel <= LogLevel.Error then
        local eventMsg = buildLogMessage("Error", msg)
        Log.Error(addEventLogPrefix(eventMsg))
    end

    if debugLogLevel <= LogLevel.Error then
        print(buildLogMessage("Error", msg))
    end
end

function logInfo(msg, idx)
    local eventLogLevel = idx and EventLogLevel[idx] or GlobalEventLogLevel
    local debugLogLevel = idx and DebugLogLevel[idx] or GlobalDebugLogLevel
    if eventLogLevel <= LogLevel.Info then
        local eventMsg = buildLogMessage("Info", msg)
        Log.Message(addEventLogPrefix(eventMsg))
    end

    if debugLogLevel <= LogLevel.Info then
        print(buildLogMessage("Info", msg))
    end
end

function logDebug(msg, idx)
    local eventLogLevel = idx and EventLogLevel[idx] or GlobalEventLogLevel
    local debugLogLevel = idx and DebugLogLevel[idx] or GlobalDebugLogLevel
    if eventLogLevel <= LogLevel.Debug then
        local eventMsg = buildLogMessage("Debug", msg)
        Log.Message(addEventLogPrefix(eventMsg))
    end

    if debugLogLevel <= LogLevel.Debug then
        print(buildLogMessage("Debug", msg))
    end
end

function setDebugLogLevel(idx)
    print("Changing 'Debug Log Level' to " .. Controls.DebugLogLevel[idx].String)
    DebugLogLevel[idx] = json.decode(Controls.DebugLogLevel[idx].String).id
end

function setEventLogLevel(idx)
    print("Changing 'Event Log Level' to " .. Controls.DebugLogLevel[idx].String)
    EventLogLevel[idx] = json.decode(Controls.EventLogLevel[idx].String).id
end

function initLogging(idx)
    local debugLogLevelCtrl = Controls.DebugLogLevel[idx]
    local eventLogLevelCtrl = Controls.EventLogLevel[idx]

    logLevelChoices = {
        {
            id = LogLevel.Debug,
            Text = "Debug"
        },
        {
            id = LogLevel.Info,
            Text = "Info"
        },
        {
            id = LogLevel.Error,
            Text = "Error"
        },
        {
            id = LogLevel.Off,
            Text = "Off"
        },
    }

    debugLogLevelCtrl.Choices = logLevelChoices
    eventLogLevelCtrl.Choices = logLevelChoices

    -- If we don't have values yet, set some default ones (Info)
    if debugLogLevelCtrl.String == "" then
        debugLogLevelCtrl.String = json.encode(logLevelChoices[2])
    end

    if eventLogLevelCtrl.String == "" then
        eventLogLevelCtrl.String = json.encode(logLevelChoices[2])
    end

    -- Initialise
    setDebugLogLevel(idx)
    setEventLogLevel(idx)

    -- Set Event handlers
    debugLogLevelCtrl.EventHandler = function()
        setDebugLogLevel(idx)
    end

    eventLogLevelCtrl.EventHandler = function()
        setEventLogLevel(idx)
    end
end

-------------------- Init Scheduling --------------------
function schedulerLogHandler(schedulerId, idx, level, msg)
    local schedulerIdPrefix = "(" .. schedulerId .. " Scheduler) "
    if level == "Error" then
        logError(schedulerIdPrefix .. msg, idx)
    elseif level == "Info" then
        logInfo(schedulerIdPrefix .. msg, idx)
    elseif level == "Debug" then
        logDebug(schedulerIdPrefix .. msg, idx)
    end
end

function initScheduler(controlIdx, scheduler)
    scheduler.logCallback = function(level, msg) schedulerLogHandler(scheduler.name, controlIdx, level, msg) end

    scheduler.statusUpdateCallback = function(status)
        Controls.CurrentPatternLabel[controlIdx].String = status.currentPattern.label
        Controls.CurrentEventLabel[controlIdx].String = status.currentEvent.label
        Controls.NextEventLabel[controlIdx].String = status.nextEvent.label
        Controls.CurrentEventStartTime[controlIdx].String = date(status.currentEvent.startTime):fmt("%H:%M %d/%m/%Y")
        Controls.NextEventStartTime[controlIdx].String = date(status.nextEvent.startTime):fmt("%H:%M %d/%m/%Y")
        Controls.SchedulerName[controlIdx].String = scheduler.name

        local statusString = json.encode(status, { pretty = true })
        Controls.SchedulerStatus[controlIdx].String = statusString
    end

    Controls["EnableScheduler"][controlIdx].EventHandler = function(ctrl)
        scheduler:setPause(not ctrl.Boolean)
    end
    scheduler:setPause(not Controls["EnableScheduler"][controlIdx].Boolean)

    initLogging(controlIdx)

    scheduler.ticker = Timer.New()
    scheduler.ticker.EventHandler = function()
        local statusString = Controls.SchedulerStatus[controlIdx].String
        local res, currentStatus = pcall(function() return json.decode(statusString) end)
        if not res then return end
        if currentStatus then
            local now = date()
            -- print(currentStatus.nextEvent.startTime)
            local nextEvtTime = date(currentStatus.nextEvent.startTime)
            local span = nextEvtTime - now
            local spanSecs = span:spanseconds()
            local hours = math.floor(spanSecs / 3600)
            local minutes = math.floor((spanSecs % 3600) / 60)
            local seconds = math.floor(spanSecs % 60)
            local formatted = string.format("%d Hrs %d Mins %d Secs", hours, minutes, seconds)
            -- print(formatted)
            Controls.CountdownNextEvent[controlIdx].String = formatted
        end
    end
    scheduler.ticker:Start(1)

    scheduler:start()
end

local musicScheduler = FugScheduler.new {
    name = "Site Music",
    events = MusicEvents,
    patterns = MusicPatterns,
    defaultPatterns = MusicDefaultPatterns,
    specialDays = MusicSpecialDays,
    pollInterval = 1,
}

local siteMuteScheduler = FugScheduler.new {
    name = "Site Mute",
    events = SiteMuteEvents,
    patterns = SiteMutePatterns,
    defaultPatterns = SiteMuteDefaultPatterns,
    specialDays = SiteMuteSpecialDays,
    pollInterval = 1,
    logCallback = function(level, msg) schedulerLogHandler("Site Mute Scheduler", level, msg) end
}

local iceRinkScheduler = FugScheduler.new {
    name = "Ice Rink",
    events = IceRinkEvents,
    patterns = IceRinkPatterns,
    defaultPatterns = IceRinkDefaultPatterns,
    specialDays = IceRinkSpecialDays,
    pollInterval = 1,
    logCallback = function(level, msg) schedulerLogHandler("Ice Rink Scheduler", level, msg) end
}

local bigWheelScheduler = FugScheduler.new {
    name = "Big Wheel",
    events = BigWheelEvents,
    patterns = BigWheelPatterns,
    defaultPatterns = BigWheelPatternDefaults,
    specialDays = BigWheelSpecialDays,
    pollInterval = 1,
    logCallback = function(level, msg) schedulerLogHandler("Big Wheel Scheduler", level, msg) end
}

local deIcerScheduler = FugScheduler.new {
    name = "De-Icer",
    events = DeIcerEvents,
    patterns = DeIcerPatterns,
    defaultPatterns = DeIcerDefaultPatterns,
    specialDays = DeIcerSpecialDays,
    pollInterval = 1,
    logCallback = function(level, msg) schedulerLogHandler("De-Icer Scheduler", level, msg) end
}

initScheduler(1, siteMuteScheduler)
initScheduler(2, musicScheduler)
initScheduler(3, iceRinkScheduler)
initScheduler(4, bigWheelScheduler)
initScheduler(5, deIcerScheduler)
-- Ticker:Start(1)
