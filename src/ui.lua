-- ui.lua -- a small component-based terminal UI framework.
--
-- Designed for OpenComputers / OpenOS but with no hard dependencies: it draws
-- through any object exposing the GPU-ish surface below, and ships an
-- in-memory `ui.buffer` so layouts can be rendered and asserted in tests.
--
-- Concepts
--   node      A plain table describing a component (kind + props + children).
--   canvas    A drawing surface: `ui.canvas(gpu)` or `ui.buffer(w, h)`.
--   view      A function returning a fresh node tree for the current state.
--   layout    Assigns bounds (x, y, w, h) to every node, top-down.
--   draw      Paints a laid-out tree onto a canvas.
--   dispatch  Routes an event to the node under the pointer (or to focus).
--
-- Typical use
--   local ui = require("ui")
--   local canvas = ui.canvas(component.gpu)
--   ui.run({
--     canvas = canvas,
--     running = function() return not quit end,
--     view = function() return ui.column({ ui.text("hi"), ui.button("ok", {...}) }) end,
--     pull = function() return event.pull() end,
--   })
--
-- Returning `ui` makes the file loadable with require()/dofile() in any project.

local ui = {}

ui.VERSION = "0.1.0"

--============================================================================
-- Theme
--============================================================================

-- Packed 24-bit RGB. Do NOT use require("colors"): it returns palette indices
-- (white = 0) and the GPU treats a bare number as RGB, so 0 paints black.
ui.theme = {
  fg = 0xFFFFFF,
  bg = 0x000000,
  accentFg = 0xFFFFFF,
  accentBg = 0x333399,
  mutedFg = 0x808080,
  okFg = 0x33CC33,
  okBg = 0x1E5A1E,
  selectFg = 0x000000,
  selectBg = 0xCCCCCC,
  warnFg = 0xFFFF33,
}

-- Merge overrides into the active theme, e.g. ui.setTheme({ accentBg = 0x006600 }).
function ui.setTheme(overrides)
  for key, value in pairs(overrides or {}) do
    ui.theme[key] = value
  end
  return ui.theme
end

--============================================================================
-- Canvas
--============================================================================

local Canvas = {}
Canvas.__index = Canvas

local function clip_text(text, width)
  text = tostring(text or "")
  if #text > width then return text:sub(1, width) end
  return text
end

-- Surface backed by an OpenComputers GPU component.
function ui.canvas(gpu)
  local width, height = gpu.getResolution()
  return setmetatable({ gpu = gpu, width = width, height = height }, Canvas)
end

-- Surface backed by memory. Useful for headless tests and previews.
function ui.buffer(width, height)
  local canvas = setmetatable({ width = width, height = height, cells = {} }, Canvas)
  for y = 1, height do
    canvas.cells[y] = {}
    for x = 1, width do
      canvas.cells[y][x] = { " ", ui.theme.fg, ui.theme.bg }
    end
  end
  return canvas
end

function Canvas:fill(x, y, text, fg, bg, width)
  if y < 1 or y > self.height then return end
  width = width or (self.width - x + 1)
  if width <= 0 then return end
  fg = fg or ui.theme.fg
  bg = bg or ui.theme.bg
  text = tostring(text or "")
  -- Trim anything off the left edge, then clamp to the right edge so a long
  -- node can never make the GPU wrap onto the next line.
  if x < 1 then
    local drop = 1 - x
    text = text:sub(drop + 1)
    width = width - drop
    x = 1
  end
  local max_width = self.width - x + 1
  if width <= 0 or max_width <= 0 then return end
  if width > max_width then width = max_width end
  text = clip_text(text, width)
  if self.gpu then
    self.gpu.setForeground(fg)
    self.gpu.setBackground(bg)
    self.gpu.set(x, y, text .. string.rep(" ", width - #text))
  else
    for i = 1, width do
      local cx = x + i - 1
      local ch = i <= #text and text:sub(i, i) or " "
      self.cells[y][cx] = { ch, fg, bg }
    end
  end
end

function Canvas:clear(bg)
  bg = bg or ui.theme.bg
  if self.gpu then
    self.gpu.setForeground(ui.theme.fg)
    self.gpu.setBackground(bg)
    self.gpu.fill(1, 1, self.width, self.height, " ")
  else
    for y = 1, self.height do
      for x = 1, self.width do
        self.cells[y][x] = { " ", ui.theme.fg, bg }
      end
    end
  end
end

-- Text of a whole row (buffer canvases only). Handy for assertions.
function Canvas:row(y)
  local out = {}
  local cells = self.cells[y] or {}
  for x = 1, self.width do
    out[x] = (cells[x] and cells[x][1]) or " "
  end
  return table.concat(out)
end

--============================================================================
-- Nodes
--============================================================================

local function make(kind, props)
  props = props or {}
  props.kind = kind
  if props.children == nil then props.children = {} end
  return props
end

-- A run of text. `w`/`h` default to the text size; `grow` expands in a cell.
function ui.text(text, props)
  props = props or {}
  props.text = tostring(text or "")
  props.w = props.w or #props.text
  props.h = props.h or 1
  return make("text", props)
end

-- A clickable `[ label ]` button. `props.onClick(node, event)`.
function ui.button(label, props)
  props = props or {}
  props.label = tostring(label or "")
  props.w = props.w or (#props.label + 4)
  props.h = props.h or 1
  return make("button", props)
end

-- A clickable `[x] label` checkbox. `props.onClick` is called on toggle.
function ui.checkbox(label, checked, props)
  props = props or {}
  props.label = tostring(label or "")
  props.checked = checked and true or false
  props.w = props.w or (#props.label + 4)
  props.h = props.h or 1
  return make("checkbox", props)
end

-- Blank space. Combine with `grow` to push siblings apart.
function ui.spacer(props)
  props = props or {}
  props.w = props.w or 1
  props.h = props.h or 1
  return make("spacer", props)
end

-- Vertical stack. Children may set `grow` to share leftover height.
function ui.column(children, props)
  props = props or {}
  props.children = children or {}
  props.gap = props.gap or 0
  return make("column", props)
end

-- Horizontal stack. Children may set `grow` to share leftover width.
function ui.row(children, props)
  props = props or {}
  props.children = children or {}
  props.gap = props.gap or 0
  return make("row", props)
end

-- A scrollable list. Props:
--   items         array of arbitrary items
--   offset        index of the first visible item (1-based)
--   renderItem    function(item, index, node) -> { text, fg, bg }
--   onItemClick   function(item, index, node, event)
--   onScroll      function(delta, node)
--   grow          usually true, so it fills the remaining height
function ui.list(props)
  props = props or {}
  props.items = props.items or {}
  props.offset = props.offset or 0
  return make("list", props)
end

--============================================================================
-- Layout
--============================================================================

local function distribute(kids, total, size_key, gap)
  local used = 0
  local growers = 0
  for _, c in ipairs(kids) do
    if c.grow then growers = growers + 1 else used = used + (c[size_key] or 1) end
  end
  used = used + (gap or 0) * math.max(0, #kids - 1)
  local share = growers > 0 and math.max(0, math.floor((total - used) / growers)) or 0
  return share
end

local function place(node, x, y, w, h)
  node.x, node.y, node.w, node.h = x, y, w, h
  local kind = node.kind
  if kind == "column" then
    local gap = node.gap or 0
    local share = distribute(node.children, h, "h", gap)
    local cy = y
    for _, child in ipairs(node.children) do
      local ch = child.grow and share or (child.h or 1)
      place(child, x, cy, w, ch)
      cy = cy + ch + gap
    end
  elseif kind == "row" then
    local gap = node.gap or 0
    local share = distribute(node.children, w, "w", gap)
    local cx = x
    for _, child in ipairs(node.children) do
      local cw = child.grow and share or (child.w or 1)
      place(child, cx, y, cw, h)
      cx = cx + cw + gap
    end
  end
end

-- Assign bounds to every node in the tree.
function ui.layout(root, width, height)
  place(root, 1, 1, width or root.w or 1, height or root.h or 1)
  return root
end

--============================================================================
-- Draw
--============================================================================

local function fg_bg(node)
  local style = node.style or {}
  return style.fg or ui.theme.fg, style.bg or ui.theme.bg
end

local function draw_node(canvas, node)
  local kind = node.kind
  if kind == "column" or kind == "row" then
    -- Paint the container background first so stale cells from a previous
    -- view can never leak through gaps between children.
    local _, bg = fg_bg(node)
    for row = 0, node.h - 1 do
      canvas:fill(node.x, node.y + row, "", ui.theme.fg, bg, node.w)
    end
    for _, child in ipairs(node.children) do
      draw_node(canvas, child)
    end
  elseif kind == "text" then
    local fg, bg = fg_bg(node)
    canvas:fill(node.x, node.y, node.text, fg, bg, node.w)
  elseif kind == "spacer" then
    for row = 0, node.h - 1 do
      canvas:fill(node.x, node.y + row, "", ui.theme.fg, ui.theme.bg, node.w)
    end
  elseif kind == "button" then
    local style = node.style or {}
    local fg = node.disabled and ui.theme.mutedFg or (style.fg or ui.theme.accentFg)
    local bg = node.disabled and ui.theme.bg or (style.bg or ui.theme.accentBg)
    canvas:fill(node.x, node.y, "[ " .. node.label .. " ]", fg, bg, node.w)
  elseif kind == "checkbox" then
    local fg, bg = fg_bg(node)
    canvas:fill(node.x, node.y, (node.checked and "[x] " or "[ ] ") .. node.label, fg, bg, node.w)
  elseif kind == "list" then
    for row = 1, node.h do
      local index = node.offset + row
      local item = node.items[index]
      if item then
        local info = node.renderItem and node.renderItem(item, index, node) or {}
        canvas:fill(node.x, node.y + row - 1, info.text or tostring(item),
          info.fg or ui.theme.fg, info.bg or ui.theme.bg, node.w)
      else
        canvas:fill(node.x, node.y + row - 1, "", ui.theme.fg, ui.theme.bg, node.w)
      end
    end
  end
end

function ui.draw(canvas, root)
  draw_node(canvas, root)
end

--============================================================================
-- Events
--============================================================================

local function contains(node, x, y)
  return node.x and x >= node.x and x <= node.x + node.w - 1
    and y >= node.y and y <= node.y + node.h - 1
end

local function collect(node, x, y, out)
  if not contains(node, x, y) then return end
  if node.kind == "column" or node.kind == "row" then
    for i = #node.children, 1, -1 do
      collect(node.children[i], x, y, out)
    end
  end
  out[#out + 1] = node
end

-- First node marked `focused` in the tree, if any.
function ui.findFocused(root)
  if root.focused then return root end
  for _, child in ipairs(root.children or {}) do
    local found = ui.findFocused(child)
    if found then return found end
  end
  return nil
end

-- Route an event (as delivered by event.pull) to the tree.
-- Returns true if a node consumed it.
function ui.dispatch(root, event)
  local name = event[1]
  if name == "touch" then
    local x, y, button = event[3], event[4], event[5]
    if button and button ~= 0 then return false end
    local hits = {}
    collect(root, x, y, hits)
    for _, node in ipairs(hits) do
      if node.kind == "list" and node.onItemClick then
        local index = node.offset + (y - node.y + 1)
        if node.items[index] then
          node.onItemClick(node.items[index], index, node, event)
          return true
        end
      elseif node.onClick and not node.disabled then
        node.onClick(node, event)
        return true
      end
    end
  elseif name == "scroll" then
    local x, y, delta = event[3], event[4], event[5]
    local hits = {}
    collect(root, x, y, hits)
    for _, node in ipairs(hits) do
      if node.kind == "list" and node.onScroll then
        node.onScroll(delta, node)
        return true
      end
    end
  elseif name == "key_down" then
    local focused = ui.findFocused(root)
    if focused and focused.onKey then
      focused.onKey(event[3], event[4], focused)
      return true
    end
  end
  return false
end

--============================================================================
-- Runner
--============================================================================

-- Redraw-and-pull loop. All callbacks are optional except view:
--   canvas   surface to draw on (required)
--   view     function() -> node tree (required)
--   pull     function() -> event (defaults to event.pull)
--   running  function() -> boolean (defaults to always true)
--   onEvent  function(event, tree) -> handled? (runs before dispatch)
function ui.run(opts)
  local canvas = opts.canvas
  local view = opts.view
  local pull = opts.pull or require("event").pull
  local running = opts.running or function() return true end
  local onEvent = opts.onEvent

  canvas:clear()
  while running() do
    local tree = view()
    ui.layout(tree, canvas.width, canvas.height)
    ui.draw(canvas, tree)
    local event = table.pack(pull())
    local handled = onEvent and onEvent(event, tree)
    if not handled then
      ui.dispatch(tree, event)
    end
  end
  return true
end

return ui
