-- Keep weekday keys, labels, and assignment control names consistent across design and runtime code.
FugSchedulerWeekdays = {
  {key = "Mon", label = "Monday", controlName = "WeekPatternMon"},
  {key = "Tue", label = "Tuesday", controlName = "WeekPatternTue"},
  {key = "Wed", label = "Wednesday", controlName = "WeekPatternWed"},
  {key = "Thu", label = "Thursday", controlName = "WeekPatternThu"},
  {key = "Fri", label = "Friday", controlName = "WeekPatternFri"},
  {key = "Sat", label = "Saturday", controlName = "WeekPatternSat"},
  {key = "Sun", label = "Sunday", controlName = "WeekPatternSun"}
}

FugSchedulerTheme = {
  pageW = 900,
  pageH = 520,
  colors = {
    accent = {42, 150, 135},
    schedule = {75, 155, 230},
    action = {235, 165, 55},
    statusBackground = {190, 195, 200},
    statusText = {20, 22, 24}
  }
}

-- Return a property value by name, or a fallback when unavailable.
function propValue(props, name, fallback)
  if props == nil then return fallback end
  if props[name] and props[name].Value ~= nil then return props[name].Value end
  for _, prop in ipairs(props) do
    if prop.Name == name then return prop.Value end
  end
  return fallback
end

-- Return the page names implied by the current design-time properties.
function pageNames(props)
  local names = {"Overview", "Schedules", "Day Patterns", "Week Patterns", "Overrides", "Actions", "Preferences"}
  if propValue(props, "Show Diagnostics Page", true) then
    table.insert(names, "Diagnostics")
  end
  table.insert(names, "About")
  return names
end

-- Return the active page selected by Q-SYS Designer.
function currentPageName(props)
  local names = pageNames(props)
  local index = propValue(props, "page_index", 1)
  return names[index] or names[1]
end
