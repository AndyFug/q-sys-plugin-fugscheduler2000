FugSchedulerUi = FugSchedulerUi or {}

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

-- Draw one labeled control row in the Override details panel.
function FugSchedulerUi.overrideField(ui, label, controlName, style, y, options)
  ui:label(label, ui:rect(350, y + 2, 104, 22), {Color = ui:color("mutedText")})
  if style == "Text" then
    ui:textControl(controlName, ui:rect(458, y, 408, 26), options or {})
  else
    ui:control(controlName, style, ui:rect(458, y, 408, 26), options or {})
  end
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
