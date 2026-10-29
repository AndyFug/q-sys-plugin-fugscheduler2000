-- Q-SYS calls this before runtime to define editable plugin properties.
function GetProperties()
  local props = {}

  table.insert(props, {
    Name = "Scheduler Slot Count",
    Type = "integer",
    Value = 8,
    Min = 1,
    Max = 32,
    Header = "Scheduler Slots",
    Comment = "Number of stable runnable Scheduler slots exposed by the plugin (1-32)."
  })
  table.insert(props, {
    Name = "Show Diagnostics Page",
    Type = "boolean",
    Value = true,
    Header = "User Interface",
    Comment = "Show the runtime diagnostics and logging page."
  })
  table.insert(props, {
    Name = "Layout Debug",
    Type = "boolean",
    Value = false,
    Comment = "Show page and canvas diagnostics in the plugin UI."
  })

  return props
end
