--[[
  FugScheduler 2000
  Template/compiler workflow source shell.

  Edit files under src/ and compile them into ../FugScheduler2000.qplug.
  The current runtime validates trusted external Actions, persists a versioned
  multi-Scheduler model, and publishes read-only resolution status.
]]

-- Information block for the plugin.
--[[ #include "info.lua" ]]

-- Constants, theme overrides, and property/page helpers.
--[[ #include "globals.lua" ]]

-- Vendored shared FugUi framework.
--[[ #include "fug_ui.lua" ]]

-- Merge project theme overrides with FugUi's common visual baseline.
FugSchedulerTheme = FugUi.theme(FugSchedulerTheme)

-- Scheduler-specific UI helpers.
--[[ #include "ui.lua" ]]

-- Return the plugin block color shown in Q-SYS Designer.
function GetColor(_props)
  return FugSchedulerTheme.colors.accent
end

-- Return the initial plugin name shown when dragged into a design.
function GetPrettyName(_props)
  return "FugScheduler 2000 v" .. PluginInfo.Version
end

-- Define the plugin pages.
--[[ #include "pages.lua" ]]

-- Define user-editable design-time properties.
--[[ #include "properties.lua" ]]

-- Rectify dependent properties after design-time edits.
--[[ #include "rectify_properties.lua" ]]

-- Define non-control pins.
--[[ #include "pins.lua" ]]

-- Define hidden embedded components.
--[[ #include "components.lua" ]]

-- Define wiring between pins and embedded components.
--[[ #include "wiring.lua" ]]

-- Define persistent controls and control pins.
--[[ #include "controls.lua" ]]

-- Define plugin UI layout and graphics.
--[[ #include "layout.lua" ]]

-- Start event-based runtime logic when loaded on a Core or in emulation.
if Controls then
  --[[ #include "runtime.lua" ]]
end
