FugSchedulerUi = FugSchedulerUi or {}

-- Return the retained-container column specifications for Scheduler Slot rows.
function FugSchedulerUi.slotColumnSpecs()
  return {
    {width = 34}, {width = 180}, {width = 42}, {width = 42},
    {grow = 1}, {grow = 1}, {grow = 1}
  }
end

-- Add the compact Scheduler Slot table header.
function FugSchedulerUi.slotHeader(ui, rect)
  local row = FugUi.box(ui, rect, {padding = 2})
  local cells = {row:splitRow(FugSchedulerUi.slotColumnSpecs(), {gap = 4})}
  local labels = {"Slot", "Scheduler Definition", "On", "Pause", "Current Pattern", "Current Event", "Next Event"}
  for index, cell in ipairs(cells) do
    ui:label(labels[index], cell:fill(), {
      Color = ui:color("mutedText"), FontSize = 9, IsBold = true,
      HTextAlign = (index == 1 or index == 3 or index == 4) and "Center" or "Left"
    })
  end
  return row
end

-- Add one fixed numbered Scheduler Slot row using the stable counted slot controls.
function FugSchedulerUi.slotRow(ui, rect, slotNumber)
  local row = FugUi.box(ui, rect, {padding = 2})
  row:group("", {
    Fill = ui:color(slotNumber % 2 == 0 and "panelAlt" or "panel"),
    StrokeColor = ui:color("stroke"), StrokeWidth = 1, CornerRadius = 3
  })
  local cells = {row:splitRow(FugSchedulerUi.slotColumnSpecs(), {gap = 4})}
  ui:textControl(countedControlName("SchedulerSlotNumber", slotNumber), cells[1]:fill(), {
    IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
    FontSize = 9, IsBold = true, HTextAlign = "Center"
  })
  ui:control(countedControlName("SchedulerSlotDefinition", slotNumber), "ComboBox", cells[2]:fill(), {
    PrettyName = "Scheduler Slots~Slot " .. tostring(slotNumber) .. " Definition", FontSize = 8
  })
  local enableCell = cells[3]:fill()
  local pauseCell = cells[4]:fill()
  ui:button(countedControlName("SchedulerSlotEnabled", slotNumber), ui:center(enableCell, 30, enableCell.h), {
    ButtonStyle = "Toggle", Legend = "", Color = ui:color("ok")
  })
  ui:button(countedControlName("SchedulerSlotPaused", slotNumber), ui:center(pauseCell, 30, pauseCell.h), {
    ButtonStyle = "Toggle", Legend = "", Color = ui:color("warning")
  })
  ui:textControl(countedControlName("SchedulerSlotCurrentPattern", slotNumber), cells[5]:fill(), {
    IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
    HTextAlign = "Left", VTextAlign = "Center", WordWrap = true, FontSize = 8
  })
  ui:textControl(countedControlName("SchedulerSlotCurrentEvent", slotNumber), cells[6]:fill(), {
    IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
    HTextAlign = "Left", VTextAlign = "Center", WordWrap = true, FontSize = 8
  })
  ui:textControl(countedControlName("SchedulerSlotNextEvent", slotNumber), cells[7]:fill(), {
    IsReadOnly = true, TextBoxStyle = "NoBackground", TextColor = ui:color("controlText"),
    HTextAlign = "Left", VTextAlign = "Center", WordWrap = true, FontSize = 8
  })
  return row
end

-- Draw a label and read-only Text control as one status row.
function FugSchedulerUi.statusField(ui, label, controlName, rect)
  local labelWidth = 150
  ui:label(label, ui:rect(rect.x, rect.y, labelWidth, rect.h), {
    Color = ui:color("mutedText")
  })
  ui:textControl(controlName, ui:rect(rect.x + labelWidth, rect.y, rect.w - labelWidth, rect.h), {
    IsReadOnly = true,
    TextBoxStyle = "NoBackground",
    TextColor = ui:color("controlText"),
    HTextAlign = "Left",
    PrettyName = "Status~" .. label
  })
end

-- Draw a centered read-only editor message with a shared high-contrast status style.
function FugSchedulerUi.editorStatus(ui, controlName, rect, prettyName)
  ui:textControl(controlName, rect, {
    IsReadOnly = true,
    TextBoxStyle = "Normal",
    Color = ui:color("statusBackground"),
    TextColor = ui:color("statusText"),
    HTextAlign = "Center",
    VTextAlign = "Center",
    WordWrap = true,
    FontSize = 10,
    PrettyName = prettyName
  })
end

-- Draw a scrollable JSON or log viewer as a monospaced ListBox of source lines.
function FugSchedulerUi.dataViewer(ui, controlName, rect, prettyName, _isReadOnly)
  ui:control(controlName, "ListBox", rect, {
    Color = ui:color("statusBackground"),
    TextColor = ui:color("statusText"),
    HTextAlign = "Left",
    Font = "Roboto Mono",
    FontSize = 9,
    PrettyName = prettyName
  })
end

-- Draw one Week Pattern weekday label and structured Day Pattern selector row.
function FugSchedulerUi.weekdayAssignment(ui, weekday, y)
  ui:label(weekday.label, ui:rect(340, y + 2, 112, 22), {Color = ui:color("mutedText")})
  ui:control(weekday.controlName, "ComboBox", ui:rect(456, y, 414, 26), {
    PrettyName = "Week Patterns~" .. weekday.label .. " Day Pattern"
  })
end

-- Draw one Override date entry with normal long-form output and a separate red validation message.
function FugSchedulerUi.overrideDateField(ui, label, entryName, longFormName, validationName, y)
  ui:label(label, ui:rect(314, y + 2, 88, 22), {Color = ui:color("mutedText")})
  ui:textControl(entryName, ui:rect(406, y, 160, 26), {
    PrettyName = "Overrides~" .. label,
    HTextAlign = "Center"
  })
  ui:textControl(longFormName, ui:rect(406, y + 27, 464, 18), {
    IsReadOnly = true,
    TextBoxStyle = "NoBackground",
    HTextAlign = "Left",
    TextColor = ui:color("controlText"),
    FontSize = 10
  })
  ui:textControl(validationName, ui:rect(406, y + 27, 464, 18), {
    IsReadOnly = true,
    TextBoxStyle = "NoBackground",
    HTextAlign = "Left",
    TextColor = ui:color("danger"),
    FontSize = 9
  })
end

-- Draw one compact neutral Override date convenience button.
function FugSchedulerUi.overrideDateButton(ui, controlName, legend, x, y)
  ui:button(controlName, ui:rect(x, y, 54, 24), {
    ButtonStyle = "Momentary",
    Legend = legend,
    Color = ui:color("statusBackground"),
    TextColor = {255, 255, 255},
    FontSize = 9
  })
end

-- Draw a standard explanatory panel for unfinished editor pages.
function FugSchedulerUi.placeholderPanel(ui, title, body)
  ui:group(title, ui:rect(10, 44, 880, 400))
  ui:label(body, ui:rect(28, 82, 844, 100), {
    FontSize = 12,
    VTextAlign = "Top",
    WordWrap = true,
    Color = ui:color("mutedText")
  })
end
