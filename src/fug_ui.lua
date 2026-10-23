-- -----------------------------------------------------------------------------
-- FugUi: shared Q-SYS plugin UI helper layer
-- -----------------------------------------------------------------------------
-- Include-friendly Lua helper table for building Q-SYS plugin layout/graphics
-- tables. Projects should pass their own theme to FugUi.new(theme) and can add
-- project-specific helpers on top of this foundation.

FugUi = FugUi or {}
FugUi.Builder = FugUi.Builder or {}
FugUi.Builder.__index = FugUi.Builder

-- Default theme used by all plugins unless a project overrides individual keys.
FugUi.DefaultTheme = FugUi.DefaultTheme or {
  pageW = 900,
  pageH = 520,
  gap = 8,
  pad = 10,
  rowH = 22,
  buttonH = 24,
  labelH = 18,
  headerH = 28,
  meterW = 18,
  colors = {
    background = {22, 24, 28},
    panel = {32, 35, 40},
    panelAlt = {38, 42, 48},
    stroke = {70, 75, 82},
    text = {230, 235, 240},
    mutedText = {160, 168, 176},
    controlText = {230, 235, 240},
    accent = {30, 135, 220},
    cue = {240, 185, 40},
    test = {170, 90, 245},
    danger = {210, 65, 65},
    ok = {60, 190, 120},
    warning = {235, 150, 45},
    transparent = {0, 0, 0, 0}
  }
}

-- Return true for plain map-like tables; color arrays are treated as leaf values.
function FugUi.isMapTable(value)
  return type(value) == "table" and #value == 0
end

-- Deep-copy a value so per-plugin theme changes never mutate DefaultTheme.
function FugUi.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[k] = FugUi.copy(v)
  end
  return out
end

-- Merge an override table into a base table by key, preserving unspecified keys.
function FugUi.merge(base, override)
  local out = FugUi.copy(base or {})
  for k, v in pairs(override or {}) do
    if FugUi.isMapTable(v) and FugUi.isMapTable(out[k]) then
      out[k] = FugUi.merge(out[k], v)
    else
      out[k] = FugUi.copy(v)
    end
  end
  return out
end

-- Return the effective theme after applying optional project-specific overrides.
function FugUi.theme(overrides)
  return FugUi.merge(FugUi.DefaultTheme, overrides or {})
end

-- Create the layout/graphics accumulator passed through page drawing helpers.
function FugUi.new(themeOverrides)
  return setmetatable({
    layout = {},
    graphics = {},
    theme = FugUi.theme(themeOverrides),
    pageRoots = {},
    contentRight = 0,
    contentBottom = 0,
    backgroundGraphics = {},
    bottomAnchors = {}
  }, FugUi.Builder)
end

-- Store rectangle geometry with named fields for easier layout calculations.
function FugUi.rect(x, y, w, h)
  return {x = x, y = y, w = w, h = h}
end

-- Convert a helper rectangle into Q-SYS Position array format.
function FugUi.pos(rect)
  return {rect.x, rect.y}
end

-- Convert a helper rectangle into Q-SYS Size array format.
function FugUi.size(rect)
  return {rect.w, rect.h}
end

-- Return a rectangle reduced by an equal padding on all sides.
function FugUi.inset(rect, pad)
  return FugUi.rect(rect.x + pad, rect.y + pad, rect.w - (pad * 2), rect.h - (pad * 2))
end

-- Return a rectangle moved by dx/dy without changing size.
function FugUi.offset(rect, dx, dy)
  return FugUi.rect(rect.x + dx, rect.y + dy, rect.w, rect.h)
end

-- Return a rectangle with the same origin but a different size.
function FugUi.resize(rect, w, h)
  return FugUi.rect(rect.x, rect.y, w, h)
end

-- Return a rectangle centered inside a parent rectangle.
function FugUi.center(parent, w, h)
  return FugUi.rect(
    parent.x + math.floor((parent.w - w) / 2),
    parent.y + math.floor((parent.h - h) / 2),
    w,
    h
  )
end

-- Return a rectangle horizontally centered inside a parent, preserving y/h.
function FugUi.centerX(parent, w, y, h)
  return FugUi.rect(parent.x + math.floor((parent.w - w) / 2), y or parent.y, w, h or parent.h)
end

-- Return a rectangle vertically centered inside a parent, preserving x/w.
function FugUi.centerY(parent, h, x, w)
  return FugUi.rect(x or parent.x, parent.y + math.floor((parent.h - h) / 2), w or parent.w, h)
end

-- Align a child rectangle within a parent using Left/Center/Right and Top/Center/Bottom.
function FugUi.align(parent, w, h, hAlign, vAlign)
  local x = parent.x
  local y = parent.y
  local horizontal = hAlign or "Left"
  local vertical = vAlign or "Top"

  if horizontal == "Center" or horizontal == "center" then
    x = parent.x + math.floor((parent.w - w) / 2)
  elseif horizontal == "Right" or horizontal == "right" then
    x = parent.x + parent.w - w
  end

  if vertical == "Center" or vertical == "center" then
    y = parent.y + math.floor((parent.h - h) / 2)
  elseif vertical == "Bottom" or vertical == "bottom" then
    y = parent.y + parent.h - h
  end

  return FugUi.rect(x, y, w, h)
end

-- Return a rectangle docked to one edge of a parent rectangle.
function FugUi.dock(parent, edge, size)
  if edge == "top" or edge == "Top" then
    return FugUi.rect(parent.x, parent.y, parent.w, size)
  elseif edge == "bottom" or edge == "Bottom" then
    return FugUi.rect(parent.x, parent.y + parent.h - size, parent.w, size)
  elseif edge == "left" or edge == "Left" then
    return FugUi.rect(parent.x, parent.y, size, parent.h)
  elseif edge == "right" or edge == "Right" then
    return FugUi.rect(parent.x + parent.w - size, parent.y, size, parent.h)
  end
  return FugUi.copy(parent)
end

-- Split a parent rectangle into evenly-sized row rectangles.
function FugUi.rows(parent, count, gap)
  local rects = {}
  local spacing = gap or 0
  local rowH = math.floor((parent.h - ((count - 1) * spacing)) / count)
  for i = 1, count do
    table.insert(rects, FugUi.rect(parent.x, parent.y + ((i - 1) * (rowH + spacing)), parent.w, rowH))
  end
  return rects
end

-- Split a parent rectangle into evenly-sized column rectangles.
function FugUi.cols(parent, count, gap)
  local rects = {}
  local spacing = gap or 0
  local colW = math.floor((parent.w - ((count - 1) * spacing)) / count)
  for i = 1, count do
    table.insert(rects, FugUi.rect(parent.x + ((i - 1) * (colW + spacing)), parent.y, colW, parent.h))
  end
  return rects
end

-- Split a parent rectangle into a row-major grid of rectangles.
function FugUi.grid(parent, rowCount, colCount, gapX, gapY)
  local cells = {}
  local xGap = gapX or 0
  local yGap = gapY or xGap
  local cellW = math.floor((parent.w - ((colCount - 1) * xGap)) / colCount)
  local cellH = math.floor((parent.h - ((rowCount - 1) * yGap)) / rowCount)

  for row = 1, rowCount do
    for col = 1, colCount do
      table.insert(cells, FugUi.rect(
        parent.x + ((col - 1) * (cellW + xGap)),
        parent.y + ((row - 1) * (cellH + yGap)),
        cellW,
        cellH
      ))
    end
  end

  return cells
end

-- Resolve a counted control name to Q-SYS's `Name N` convention.
function FugUi.controlName(base, count, index)
  if count and count > 1 then
    return base .. " " .. index
  end
  return base
end

-- Return a theme color with a fallback.
function FugUi.color(ui, name, fallback)
  local theme = ui.theme or {}
  local colors = theme.colors or {}
  return colors[name] or fallback or {255, 255, 255}
end

-- Expand the builder's measured content bounds to include a rendered rectangle.
function FugUi.trackBounds(ui, rect)
  ui.contentRight = math.max(ui.contentRight or 0, rect.x + rect.w)
  ui.contentBottom = math.max(ui.contentBottom or 0, rect.y + rect.h)
end

-- Add a control layout entry that binds a GetControls control to a UI widget.
function FugUi.control(ui, name, style, rect, opts)
  local item = opts or {}
  item.Style = style
  item.Position = FugUi.pos(rect)
  item.Size = FugUi.size(rect)
  ui.layout[name] = item
  FugUi.trackBounds(ui, rect)
end

-- Add a hidden layout entry for controls that need pins/runtime access but no UI.
function FugUi.hiddenControl(ui, name)
  ui.layout[name] = {
    Style = "None",
    Position = {0, 0},
    Size = {0, 0}
  }
end

-- Add static text graphics; labels do not create runtime controls or pins.
function FugUi.label(ui, text, rect, opts)
  local item = opts or {}
  item.Type = "Label"
  item.Text = text
  item.Position = FugUi.pos(rect)
  item.Size = FugUi.size(rect)
  item.Color = item.Color or FugUi.color(ui, "text")
  item.Fill = item.Fill or {0, 0, 0, 0}
  item.FontSize = item.FontSize or 10
  item.HTextAlign = item.HTextAlign or "Left"
  item.VTextAlign = item.VTextAlign or "Center"
  table.insert(ui.graphics, item)
  FugUi.trackBounds(ui, rect)
end

-- Add a panel/group graphic used to visually organize related controls.
function FugUi.group(ui, text, rect, opts)
  local item = opts or {}
  item.Type = "GroupBox"
  item.Text = text or ""
  item.Position = FugUi.pos(rect)
  item.Size = FugUi.size(rect)
  item.Fill = item.Fill or FugUi.color(ui, "panel", {40, 40, 40})
  item.StrokeColor = item.StrokeColor or FugUi.color(ui, "stroke", {80, 80, 80})
  item.StrokeWidth = item.StrokeWidth or 1
  item.CornerRadius = item.CornerRadius or 6
  item.Color = item.Color or FugUi.color(ui, "text")
  item.FontSize = item.FontSize or 11
  item.HTextAlign = item.HTextAlign or "Left"
  table.insert(ui.graphics, item)
  FugUi.trackBounds(ui, rect)
end

-- Paint the full plugin canvas before page-specific graphics are added.
function FugUi.background(ui)
  local theme = ui.theme or {}
  FugUi.group(ui, "", FugUi.rect(0, 0, theme.pageW or 760, theme.pageH or 520), {
    Fill = FugUi.color(ui, "background", {32, 34, 38}),
    StrokeColor = FugUi.color(ui, "background", {32, 34, 38}),
    CornerRadius = 0,
    StrokeWidth = 0
  })
  table.insert(ui.backgroundGraphics, ui.graphics[#ui.graphics])
end

-- Draw a common page title and optional right-aligned subtitle.
function FugUi.header(ui, title, subtitle)
  local theme = ui.theme or {}
  local pageW = theme.pageW or 760
  FugUi.label(ui, title, FugUi.rect(10, 6, math.floor(pageW * 0.45), 24), {
    FontSize = 16,
    IsBold = true,
    Color = FugUi.color(ui, "text")
  })
  if subtitle then
    FugUi.label(ui, subtitle, FugUi.rect(math.floor(pageW * 0.45), 8, pageW - math.floor(pageW * 0.45) - 10, 20), {
      FontSize = 10,
      Color = FugUi.color(ui, "mutedText", {170, 170, 170}),
      HTextAlign = "Right"
    })
  end
end

-- Place a shared status text control at the bottom of a page.
function FugUi.statusBar(ui, controlName)
  local theme = ui.theme or {}
  local pageW = theme.pageW or 760
  local pageH = theme.pageH or 520
  local name = controlName or "Status"
  FugUi.control(ui, name, "Text", FugUi.rect(10, pageH - 30, pageW - 20, 22), {
    PrettyName = "Status",
    TextBoxStyle = "NoBackground",
    IsReadOnly = true,
    FontSize = 10,
    TextColor = FugUi.color(ui, "text"),
    HTextAlign = "Left"
  })
  table.insert(ui.bottomAnchors, {name = name, bottom = 8, left = 10, right = 10, height = 22})
end

-- Convenience wrapper for a button control.
function FugUi.button(ui, name, rect, opts)
  FugUi.control(ui, name, "Button", rect, opts or {})
end

-- Convenience wrapper for a text control.
function FugUi.textControl(ui, name, rect, opts)
  FugUi.control(ui, name, "Text", rect, opts or {})
end

-- Convenience wrapper for a knob control.
function FugUi.knob(ui, name, rect, opts)
  FugUi.control(ui, name, "Knob", rect, opts or {})
end

-- Convenience wrapper for a meter control.
function FugUi.meter(ui, name, rect, opts)
  local item = opts or {}
  item.MeterStyle = item.MeterStyle or "Level"
  item.ShowTextbox = item.ShowTextbox or false
  FugUi.control(ui, name, "Meter", rect, item)
end

-- Draw simple column labels for table-like plugin pages.
function FugUi.tableHeader(ui, columns, x, y, h)
  local cursor = x
  for _, col in ipairs(columns) do
    FugUi.label(ui, col.text or "", FugUi.rect(cursor, y, col.w, h or 18), {
      FontSize = col.fontSize or 10,
      HTextAlign = col.align or "Center",
      Color = col.color or FugUi.color(ui, "mutedText", {170, 170, 170})
    })
    cursor = cursor + col.w + (col.gap or 0)
  end
end

-- Draw a compact horizontal meter bank with numeric captions.
function FugUi.meterBank(ui, baseName, count, rect, opts)
  local item = opts or {}
  local gap = item.gap or 4
  local inner = FugUi.inset(rect, item.pad or 12)
  local meterW = math.max(8, math.floor((inner.w - ((count - 1) * gap)) / count))

  if item.group ~= false then
    FugUi.group(ui, item.title or "Meter Bank", rect)
  end

  for i = 1, count do
    local x = inner.x + ((i - 1) * (meterW + gap))
    FugUi.meter(ui, FugUi.controlName(baseName, count, i), FugUi.rect(x, inner.y + 18, meterW, inner.h - 40), item.meterOptions or {})
    FugUi.label(ui, tostring(i), FugUi.rect(x, inner.y + inner.h - 18, meterW, 14), {
      FontSize = 8,
      HTextAlign = "Center",
      Color = FugUi.color(ui, "mutedText", {170, 170, 170})
    })
  end
end


-- -----------------------------------------------------------------------------
-- Box layout API
-- -----------------------------------------------------------------------------
-- Boxes compute absolute Q-SYS rectangles from a parent/content model. They do
-- not create runtime containers; they provide a div-like layout layer before the
-- final absolute layout/graphics tables are emitted.

FugUi.Box = FugUi.Box or {}
FugUi.Box.__index = FugUi.Box

-- Normalize numeric or per-edge spacing into a full edge table.
function FugUi.spacing(value)
  if type(value) == "number" then
    return {top = value, right = value, bottom = value, left = value}
  end
  local item = value or {}
  return {
    top = item.top or item.y or item.vertical or 0,
    right = item.right or item.x or item.horizontal or 0,
    bottom = item.bottom or item.y or item.vertical or 0,
    left = item.left or item.x or item.horizontal or 0
  }
end

-- Create a layout box around an absolute rectangle with optional padding/title.
function FugUi.box(ui, rect, opts, parent)
  local item = opts or {}
  return setmetatable({
    ui = ui,
    rect = rect and FugUi.copy(rect) or nil,
    parent = parent,
    children = {},
    items = {},
    opts = item,
    direction = item.direction or item.layout,
    padding = FugUi.spacing(item.padding or 0),
    margin = FugUi.spacing(item.margin or 0),
    title = item.title,
    groupOptions = item.groupOptions,
    drawGroup = item.group == true or item.title ~= nil,
    retained = item.retained == true or (parent and parent.retained) or false
  }, FugUi.Box)
end

-- Return the root page box, normally used as the layout parent for a page.
function FugUi.page(ui, opts)
  local item = opts or {}
  local theme = ui.theme or {}
  local margin = FugUi.spacing(item.margin or 0)
  local retained = item.retained == true or item.height == "auto" or item.width == "auto" or item.direction ~= nil or item.layout ~= nil
  item.retained = retained

  local rect = FugUi.rect(
    margin.left,
    margin.top,
    (theme.pageW or 900) - margin.left - margin.right,
    (theme.pageH or 520) - margin.top - margin.bottom
  )
  local page = FugUi.box(ui, rect, item)
  page.pageMargin = margin
  if retained then
    table.insert(ui.pageRoots, page)
  end
  return page
end

-- Return the inner content rectangle after padding has been applied.
function FugUi.Box:contentRect()
  return FugUi.rect(
    self.rect.x + self.padding.left,
    self.rect.y + self.padding.top,
    self.rect.w - self.padding.left - self.padding.right,
    self.rect.h - self.padding.top - self.padding.bottom
  )
end

-- Return a child box covering this box's content rectangle.
function FugUi.Box:content(opts)
  return FugUi.box(self.ui, self:contentRect(), opts or {})
end

-- Convert a rectangle relative to this box's content area into an absolute rect.
function FugUi.Box:relative(x, y, w, h)
  local content = self:contentRect()
  return FugUi.rect(content.x + x, content.y + y, w, h)
end

-- Return this box's content rectangle for controls that should fill the box.
function FugUi.Box:fill()
  return self:contentRect()
end

-- Draw this box as a titled or untitled group graphic.
function FugUi.Box:group(title, opts)
  FugUi.group(self.ui, title or self.title or "", self.rect, opts or self.groupOptions or {})
  return self
end

-- Draw this box's configured group if requested by its spec.
function FugUi.Box:draw()
  if self.drawGroup then
    self:group(self.title, self.groupOptions)
  end
  return self
end

-- Split this box's content rectangle into horizontal children.
function FugUi.Box:splitRow(specs, opts)
  return FugUi.splitBoxes(self, "row", specs, opts)
end

-- Split this box's content rectangle into vertical children.
function FugUi.Box:splitColumn(specs, opts)
  return FugUi.splitBoxes(self, "column", specs, opts)
end

-- HTML-ish aliases for horizontal rows and vertical columns.
function FugUi.Box:row(specs, opts)
  if specs and specs[1] then
    return self:splitRow(specs, opts)
  end
  return self:flowRow(specs or {})
end

function FugUi.Box:column(specs, opts)
  if specs and specs[1] then
    return self:splitColumn(specs, opts)
  end
  return self:flowColumn(specs or {})
end

-- Allocate a fixed-height box from the top of this box's content area.
function FugUi.Box:takeTop(height, gap, opts)
  local content = self:contentRect()
  return FugUi.box(self.ui, FugUi.rect(content.x, content.y, content.w, height), opts or {})
end

-- Return the remaining content after a fixed top region is reserved.
function FugUi.Box:below(topHeight, gap, opts)
  local content = self:contentRect()
  local spacing = gap or 0
  local y = content.y + topHeight + spacing
  return FugUi.box(self.ui, FugUi.rect(content.x, y, content.w, content.h - topHeight - spacing), opts or {})
end

-- Allocate a fixed-height box from the bottom of this box's content area.
function FugUi.Box:takeBottom(height, gap, opts)
  local content = self:contentRect()
  return FugUi.box(self.ui, FugUi.rect(content.x, content.y + content.h - height, content.w, height), opts or {})
end

-- Return the remaining content after a fixed bottom region is reserved.
function FugUi.Box:above(bottomHeight, gap, opts)
  local content = self:contentRect()
  local spacing = gap or 0
  return FugUi.box(self.ui, FugUi.rect(content.x, content.y, content.w, content.h - bottomHeight - spacing), opts or {})
end

-- Allocate a fixed-width box from the left of this box's content area.
function FugUi.Box:takeLeft(width, gap, opts)
  local content = self:contentRect()
  return FugUi.box(self.ui, FugUi.rect(content.x, content.y, width, content.h), opts or {})
end

-- Return the remaining content after a fixed left region is reserved.
function FugUi.Box:rightOf(leftWidth, gap, opts)
  local content = self:contentRect()
  local spacing = gap or 0
  local x = content.x + leftWidth + spacing
  return FugUi.box(self.ui, FugUi.rect(x, content.y, content.w - leftWidth - spacing, content.h), opts or {})
end

-- Allocate a fixed-width box from the right of this box's content area.
function FugUi.Box:takeRight(width, gap, opts)
  local content = self:contentRect()
  return FugUi.box(self.ui, FugUi.rect(content.x + content.w - width, content.y, width, content.h), opts or {})
end

-- Return the remaining content after a fixed right region is reserved.
function FugUi.Box:leftOf(rightWidth, gap, opts)
  local content = self:contentRect()
  local spacing = gap or 0
  return FugUi.box(self.ui, FugUi.rect(content.x, content.y, content.w - rightWidth - spacing, content.h), opts or {})
end

-- Compute fixed/percentage/grow child boxes in a row or column.
function FugUi.splitBoxes(parent, direction, specs, opts)
  local item = opts or {}
  local gap = item.gap or 0
  local content = parent:contentRect()
  local horizontal = direction == "row"
  local mainSize = horizontal and content.w or content.h
  local crossSize = horizontal and content.h or content.w
  local gapTotal = math.max(0, #specs - 1) * gap
  local available = mainSize - gapTotal
  local fixed = 0
  local grow = 0
  local sizes = {}
  local growIndexes = {}

  for index, spec in ipairs(specs) do
    local size = horizontal and spec.width or spec.height
    if size then
      sizes[index] = size
      fixed = fixed + size
    elseif spec.percent then
      sizes[index] = math.floor(available * (spec.percent / 100))
      fixed = fixed + sizes[index]
    else
      local weight = spec.grow or 1
      grow = grow + weight
      table.insert(growIndexes, index)
    end
  end

  local remaining = math.max(0, available - fixed)
  local growAllocated = 0
  for _, index in ipairs(growIndexes) do
    local spec = specs[index]
    local size = math.floor(remaining * ((spec.grow or 1) / grow))
    sizes[index] = size
    growAllocated = growAllocated + size
  end
  if #growIndexes > 0 then
    local lastGrow = growIndexes[#growIndexes]
    sizes[lastGrow] = sizes[lastGrow] + (remaining - growAllocated)
  end

  local totalChildren = 0
  for _, size in ipairs(sizes) do
    totalChildren = totalChildren + size
  end

  local slack = math.max(0, mainSize - totalChildren - gapTotal)
  local justify = item.justify or "left"
  local cursor = horizontal and content.x or content.y
  local effectiveGap = gap
  if justify == "right" or justify == "Right" or justify == "bottom" or justify == "Bottom" then
    cursor = cursor + slack
  elseif justify == "center" or justify == "Center" then
    cursor = cursor + math.floor(slack / 2)
  elseif justify == "space-between" and #specs > 1 then
    effectiveGap = gap + math.floor(slack / (#specs - 1))
  end

  local boxes = {}
  for index, spec in ipairs(specs) do
    local main = sizes[index] or 0
    local cross = horizontal and (spec.height or crossSize) or (spec.width or crossSize)
    local x = horizontal and cursor or content.x
    local y = horizontal and content.y or cursor
    local w = horizontal and main or cross
    local h = horizontal and cross or main

    local align = spec.align or item.align
    if horizontal and cross < crossSize then
      if align == "center" or align == "Center" then
        y = content.y + math.floor((crossSize - cross) / 2)
      elseif align == "bottom" or align == "Bottom" then
        y = content.y + crossSize - cross
      end
    elseif (not horizontal) and cross < crossSize then
      if align == "center" or align == "Center" then
        x = content.x + math.floor((crossSize - cross) / 2)
      elseif align == "right" or align == "Right" then
        x = content.x + crossSize - cross
      end
    end

    local margin = FugUi.spacing(spec.margin or 0)
    x = x + margin.left
    y = y + margin.top
    w = w - margin.left - margin.right
    h = h - margin.top - margin.bottom

    local child = FugUi.box(parent.ui, FugUi.rect(x, y, w, h), spec)
    child:draw()
    table.insert(boxes, child)
    cursor = cursor + main + effectiveGap
  end

  local unpackFn = table.unpack or unpack
  return unpackFn(boxes)
end

-- Return a numeric dimension from fixed, percentage, fill, or auto sizing rules.
function FugUi.resolveDimension(value, available, fallback)
  if type(value) == "number" then return value end
  if type(value) == "string" then
    local percent = string.match(value, "^(%-?[%d%.]+)%%$")
    if percent and available then
      return math.floor(available * (tonumber(percent) / 100))
    elseif value == "fill" then
      return available
    elseif value == "auto" then
      return nil
    end
  end
  return fallback
end

-- Return the local rectangle stored on a retained control/graphic item.
function FugUi.itemRect(geometry)
  if geometry.rect then return FugUi.copy(geometry.rect) end
  return FugUi.rect(
    geometry.x or 0,
    geometry.y or 0,
    geometry.width or geometry.w or 0,
    geometry.height or geometry.h or 0
  )
end

-- Add a retained control or graphic to a box using coordinates local to its content.
function FugUi.Box:addItem(kind, name, geometry, opts)
  local item = {
    kind = kind,
    name = name,
    rect = FugUi.itemRect(geometry or {}),
    opts = opts or {}
  }
  table.insert(self.items, item)
  return item
end

-- Add a retained label to this box.
function FugUi.Box:label(text, geometry, opts)
  return self:addItem("label", text, geometry, opts)
end

-- Add a retained generic control to this box.
function FugUi.Box:control(name, style, geometry, opts)
  local item = self:addItem("control", name, geometry, opts)
  item.style = style
  return item
end

-- Add retained convenience controls to this box.
function FugUi.Box:button(name, geometry, opts)
  return self:addItem("button", name, geometry, opts)
end

function FugUi.Box:textControl(name, geometry, opts)
  return self:addItem("text", name, geometry, opts)
end

function FugUi.Box:knob(name, geometry, opts)
  return self:addItem("knob", name, geometry, opts)
end

function FugUi.Box:meter(name, geometry, opts)
  return self:addItem("meter", name, geometry, opts)
end

-- Add a retained child container; its final rectangle is calculated at result().
function FugUi.Box:div(opts)
  local child = FugUi.box(self.ui, nil, opts or {}, self)
  child.retained = true
  table.insert(self.children, child)
  return child
end

-- Create a retained horizontal flow container.
function FugUi.Box:flowRow(opts)
  local item = FugUi.copy(opts or {})
  item.direction = "row"
  return self:div(item)
end

-- Create a retained vertical flow container.
function FugUi.Box:flowColumn(opts)
  local item = FugUi.copy(opts or {})
  item.direction = "column"
  return self:div(item)
end

-- Measure content that has an intrinsic size before percentage/grow allocation.
function FugUi.intrinsicSize(box)
  local padding = box.padding
  local itemRight = 0
  local itemBottom = 0
  for _, item in ipairs(box.items) do
    local itemW = type(item.rect.w) == "number" and item.rect.w or 0
    local itemH = type(item.rect.h) == "number" and item.rect.h or 0
    itemRight = math.max(itemRight, item.rect.x + itemW)
    itemBottom = math.max(itemBottom, item.rect.y + itemH)
  end

  local childW = 0
  local childH = 0
  local gap = box.opts.gap or 0
  for index, child in ipairs(box.children) do
    local w, h = FugUi.intrinsicSize(child)
    w = FugUi.resolveDimension(child.opts.width, nil, w) or w
    h = FugUi.resolveDimension(child.opts.height, nil, h) or h
    local margin = child.margin
    w = w + margin.left + margin.right
    h = h + margin.top + margin.bottom
    if box.direction == "row" then
      childW = childW + w + (index > 1 and gap or 0)
      childH = math.max(childH, h)
    else
      childW = math.max(childW, w)
      childH = childH + h + (index > 1 and gap or 0)
    end
  end

  local contentW = math.max(itemRight, childW)
  local contentH = math.max(itemBottom, childH)
  local width = contentW + padding.left + padding.right
  local height = contentH + padding.top + padding.bottom
  width = math.max(box.opts.minWidth or 0, width)
  height = math.max(box.opts.minHeight or 0, height)
  if box.opts.maxWidth then width = math.min(width, box.opts.maxWidth) end
  if box.opts.maxHeight then height = math.min(height, box.opts.maxHeight) end
  return width, height
end

-- Allocate one flow axis across fixed, percentage, auto, and grow children.
function FugUi.allocateAxis(children, direction, available, gap)
  local sizes = {}
  local fixed = 0
  local growTotal = 0
  local growIndexes = {}
  local usable = math.max(0, available - math.max(0, #children - 1) * gap)

  for index, child in ipairs(children) do
    local value = direction == "row" and child.opts.width or child.opts.height
    local intrinsicW, intrinsicH = FugUi.intrinsicSize(child)
    local intrinsic = direction == "row" and intrinsicW or intrinsicH
    local size = value == "fill" and nil or FugUi.resolveDimension(value, usable, nil)
    local marginSize = direction == "row" and child.margin.left + child.margin.right or child.margin.top + child.margin.bottom
    if size then
      sizes[index] = size + marginSize
      fixed = fixed + sizes[index]
    elseif value == "auto" then
      sizes[index] = intrinsic + marginSize
      fixed = fixed + sizes[index]
    else
      local grow = child.opts.grow or 1
      growTotal = growTotal + grow
      table.insert(growIndexes, index)
    end
  end

  local remaining = math.max(0, usable - fixed)
  local allocated = 0
  for _, index in ipairs(growIndexes) do
    local size = math.floor(remaining * ((children[index].opts.grow or 1) / growTotal))
    sizes[index] = size
    allocated = allocated + size
  end
  if #growIndexes > 0 then
    sizes[growIndexes[#growIndexes]] = sizes[growIndexes[#growIndexes]] + (remaining - allocated)
  end
  return sizes
end

-- Calculate retained box rectangles recursively from the root down.
function FugUi.layoutRetainedBox(box, x, y, availableW, availableH, forcedW, forcedH)
  local intrinsicW, intrinsicH = FugUi.intrinsicSize(box)
  local width = forcedW or FugUi.resolveDimension(box.opts.width, availableW, nil)
  local height = forcedH or FugUi.resolveDimension(box.opts.height, availableH, nil)
  if not width then width = box.opts.width == "auto" and intrinsicW or availableW or intrinsicW end
  if box.opts.minWidth then width = math.max(width, box.opts.minWidth) end
  if box.opts.maxWidth then width = math.min(width, box.opts.maxWidth) end

  local padding = box.padding
  local innerW = math.max(0, width - padding.left - padding.right)
  local innerH = height and math.max(0, height - padding.top - padding.bottom) or nil
  local gap = box.opts.gap or 0
  local direction = box.direction or "column"
  local mainAvailable = direction == "row" and innerW or (innerH or math.max(0, intrinsicH - padding.top - padding.bottom))
  local axisSizes = FugUi.allocateAxis(box.children, direction, mainAvailable, gap)
  local totalAxis = math.max(0, #box.children - 1) * gap
  for _, size in ipairs(axisSizes) do totalAxis = totalAxis + size end
  local slack = math.max(0, mainAvailable - totalAxis)
  local justify = box.opts.justify or "left"
  local effectiveGap = gap
  local cursor = 0
  if justify == "right" or justify == "bottom" then
    cursor = slack
  elseif justify == "center" then
    cursor = math.floor(slack / 2)
  elseif justify == "space-between" and #box.children > 1 then
    effectiveGap = gap + math.floor(slack / (#box.children - 1))
  end
  local childrenRight = 0
  local childrenBottom = 0

  for index, child in ipairs(box.children) do
    local margin = child.margin
    local childX = padding.left
    local childY = padding.top
    local childW
    local childH

    if direction == "row" then
      childX = childX + cursor + margin.left
      childY = childY + margin.top
      childW = math.max(0, axisSizes[index] - margin.left - margin.right)
      childH = FugUi.resolveDimension(child.opts.height, innerH, nil)
    else
      childX = childX + margin.left
      childY = childY + cursor + margin.top
      childW = FugUi.resolveDimension(child.opts.width, innerW, nil)
      if not childW then
        childW = child.opts.width == "auto" and select(1, FugUi.intrinsicSize(child)) or innerW - margin.left - margin.right
      end
      childH = math.max(0, axisSizes[index] - margin.top - margin.bottom)
    end

    FugUi.layoutRetainedBox(child, x + childX, y + childY, childW or innerW, innerH, childW, childH)
    local align = child.opts.align or box.opts.align
    if direction == "row" and innerH and child.rect.h + margin.top + margin.bottom < innerH then
      if align == "center" then
        child.rect.y = y + padding.top + math.floor((innerH - child.rect.h) / 2)
      elseif align == "bottom" then
        child.rect.y = y + padding.top + innerH - child.rect.h - margin.bottom
      end
    elseif direction == "column" and child.rect.w + margin.left + margin.right < innerW then
      if align == "center" then
        child.rect.x = x + padding.left + math.floor((innerW - child.rect.w) / 2)
      elseif align == "right" then
        child.rect.x = x + padding.left + innerW - child.rect.w - margin.right
      end
    end

    local outerW = child.rect.w + margin.left + margin.right
    local outerH = child.rect.h + margin.top + margin.bottom
    cursor = cursor + (direction == "row" and outerW or outerH) + effectiveGap
    childrenRight = math.max(childrenRight, childX + child.rect.w + margin.right)
    childrenBottom = math.max(childrenBottom, childY + child.rect.h + margin.bottom)
  end

  local itemRight = 0
  local itemBottom = 0
  for _, item in ipairs(box.items) do
    local itemW = FugUi.resolveDimension(item.rect.w, innerW, 0) or 0
    local itemH = FugUi.resolveDimension(item.rect.h, innerH, 0) or 0
    itemRight = math.max(itemRight, padding.left + item.rect.x + itemW)
    itemBottom = math.max(itemBottom, padding.top + item.rect.y + itemH)
  end

  if not height then
    height = math.max(intrinsicH, childrenBottom + padding.bottom, itemBottom + padding.bottom)
  end
  if box.opts.minHeight then height = math.max(height, box.opts.minHeight) end
  if box.opts.maxHeight then height = math.min(height, box.opts.maxHeight) end
  box.rect = FugUi.rect(x, y, width, height)
end

-- Render retained containers and their local controls after final geometry exists.
function FugUi.renderRetainedBox(box)
  if box.drawGroup then box:group(box.title, box.groupOptions) end
  local content = box:contentRect()

  for _, item in ipairs(box.items) do
    local itemW = FugUi.resolveDimension(item.rect.w, content.w, 0) or 0
    local itemH = FugUi.resolveDimension(item.rect.h, content.h, 0) or 0
    local rect = FugUi.rect(content.x + item.rect.x, content.y + item.rect.y, itemW, itemH)
    if item.kind == "label" then
      FugUi.label(box.ui, item.name, rect, item.opts)
    elseif item.kind == "button" then
      FugUi.button(box.ui, item.name, rect, item.opts)
    elseif item.kind == "text" then
      FugUi.textControl(box.ui, item.name, rect, item.opts)
    elseif item.kind == "knob" then
      FugUi.knob(box.ui, item.name, rect, item.opts)
    elseif item.kind == "meter" then
      FugUi.meter(box.ui, item.name, rect, item.opts)
    else
      FugUi.control(box.ui, item.name, item.style, rect, item.opts)
    end
  end

  for _, child in ipairs(box.children) do
    FugUi.renderRetainedBox(child)
  end
end

-- Lay out and render all retained pages, returning their furthest extents.
function FugUi.renderRetainedPages(ui)
  local maxRight = 0
  local maxBottom = 0
  for _, page in ipairs(ui.pageRoots) do
    local margin = page.pageMargin or FugUi.spacing(0)
    local availableW = (ui.theme.pageW or 900) - margin.left - margin.right
    local availableH = (ui.theme.pageH or 520) - margin.top - margin.bottom
    local pageW = FugUi.resolveDimension(page.opts.width, availableW, availableW)
    local pageH = FugUi.resolveDimension(page.opts.height, availableH, nil)
    FugUi.layoutRetainedBox(page, margin.left, margin.top, availableW, availableH, pageW, pageH)
    FugUi.renderRetainedBox(page)
    maxRight = math.max(maxRight, page.rect.x + page.rect.w + margin.right)
    maxBottom = math.max(maxBottom, page.rect.y + page.rect.h + margin.bottom)
  end
  return maxRight, maxBottom
end

-- -----------------------------------------------------------------------------
-- Builder method API
-- -----------------------------------------------------------------------------
-- These methods keep the procedural helpers available while allowing page code to
-- use a lighter object-style syntax: `local ui = FugUi.new(theme); ui:header(...)`.

function FugUi.Builder:rect(x, y, w, h)
  return FugUi.rect(x, y, w, h)
end

function FugUi.Builder:pos(rect)
  return FugUi.pos(rect)
end

function FugUi.Builder:size(rect)
  return FugUi.size(rect)
end

function FugUi.Builder:inset(rect, pad)
  return FugUi.inset(rect, pad)
end

function FugUi.Builder:offset(rect, dx, dy)
  return FugUi.offset(rect, dx, dy)
end

function FugUi.Builder:resize(rect, w, h)
  return FugUi.resize(rect, w, h)
end

function FugUi.Builder:center(parent, w, h)
  return FugUi.center(parent, w, h)
end

function FugUi.Builder:centerX(parent, w, y, h)
  return FugUi.centerX(parent, w, y, h)
end

function FugUi.Builder:centerY(parent, h, x, w)
  return FugUi.centerY(parent, h, x, w)
end

function FugUi.Builder:align(parent, w, h, hAlign, vAlign)
  return FugUi.align(parent, w, h, hAlign, vAlign)
end

function FugUi.Builder:dock(parent, edge, size)
  return FugUi.dock(parent, edge, size)
end

function FugUi.Builder:rows(parent, count, gap)
  return FugUi.rows(parent, count, gap)
end

function FugUi.Builder:cols(parent, count, gap)
  return FugUi.cols(parent, count, gap)
end

function FugUi.Builder:grid(parent, rowCount, colCount, gapX, gapY)
  return FugUi.grid(parent, rowCount, colCount, gapX, gapY)
end

function FugUi.Builder:controlName(base, count, index)
  return FugUi.controlName(base, count, index)
end

function FugUi.Builder:color(name, fallback)
  return FugUi.color(self, name, fallback)
end

function FugUi.Builder:control(name, style, rect, opts)
  return FugUi.control(self, name, style, rect, opts)
end

function FugUi.Builder:hiddenControl(name)
  return FugUi.hiddenControl(self, name)
end

function FugUi.Builder:label(text, rect, opts)
  return FugUi.label(self, text, rect, opts)
end

function FugUi.Builder:group(text, rect, opts)
  return FugUi.group(self, text, rect, opts)
end

function FugUi.Builder:background()
  return FugUi.background(self)
end

function FugUi.Builder:header(title, subtitle)
  return FugUi.header(self, title, subtitle)
end

function FugUi.Builder:statusBar(controlName)
  return FugUi.statusBar(self, controlName)
end

function FugUi.Builder:button(name, rect, opts)
  return FugUi.button(self, name, rect, opts)
end

function FugUi.Builder:textControl(name, rect, opts)
  return FugUi.textControl(self, name, rect, opts)
end

function FugUi.Builder:knob(name, rect, opts)
  return FugUi.knob(self, name, rect, opts)
end

function FugUi.Builder:meter(name, rect, opts)
  return FugUi.meter(self, name, rect, opts)
end

function FugUi.Builder:tableHeader(columns, x, y, h)
  return FugUi.tableHeader(self, columns, x, y, h)
end

function FugUi.Builder:meterBank(baseName, count, rect, opts)
  return FugUi.meterBank(self, baseName, count, rect, opts)
end

function FugUi.Builder:page(opts)
  return FugUi.page(self, opts)
end

function FugUi.Builder:box(rect, opts)
  return FugUi.box(self, rect, opts)
end

function FugUi.Builder:result()
  if not self.finalized then
    local retainedRight, retainedBottom = FugUi.renderRetainedPages(self)
    local pageW = math.max(self.theme.pageW or 0, self.contentRight or 0, retainedRight or 0)
    local pageH = math.max(self.theme.pageH or 0, self.contentBottom or 0, retainedBottom or 0)

    for _, graphic in ipairs(self.backgroundGraphics) do
      graphic.Size = {pageW, pageH}
    end

    for _, anchor in ipairs(self.bottomAnchors) do
      local item = self.layout[anchor.name]
      if item then
        item.Position = {anchor.left, pageH - anchor.bottom - anchor.height}
        item.Size = {pageW - anchor.left - anchor.right, anchor.height}
      end
    end

    self.pageW = pageW
    self.pageH = pageH
    self.finalized = true
  end
  return self.layout, self.graphics
end
