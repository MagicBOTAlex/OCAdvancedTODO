-- Terminal UI for the todo app.
--
-- The UI owns the screen and the input loop. It talks to a Store (lib/store.lua)
-- and never depends on a concrete backend. Input is pulled through an injectable
-- source so the app can be driven by a test harness instead of the keyboard.

local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local component = require("component")

local UI = {}
UI.__index = UI

local K = keyboard.keys

-- Colors are packed 24-bit RGB. Do NOT use `require("colors")` here: that
-- library exposes palette *indices* (white = 0, black = 15), and the GPU treats
-- a bare number as an RGB value, so 0 paints black-on-black. RGB works at every
-- screen depth.
local BG = 0x000000
local FG = 0xFFFFFF
local ACCENT_BG = 0x333399
local ACCENT_FG = 0xFFFFFF
local DONE_FG = 0x808080
local SELECT_BG = 0xCCCCCC
local SELECT_FG = 0x000000
local WARN_FG = 0xFFFF33
local ERROR_FG = 0xFF3333
local LINE_FG = 0x808080

function UI.new(store, opts)
  opts = opts or {}
  local gpu = component.gpu
  local w, h = gpu.getResolution()
  return setmetatable({
    store = store,
    gpu = gpu,
    width = w,
    height = h,
    input = opts.input,
    selected = 1,
    offset = 0,
    message = nil,
    messageColor = WARN_FG,
    running = true,
    adding = false,
    buffer = {},
    buttons = {},
  }, UI)
end

-- Input ----------------------------------------------------------------

function UI:pull(...)
  if self.input then
    return self.input(...)
  end
  return event.pull(...)
end

function UI:readEvent()
  return table.pack(self:pull())
end

-- Drawing --------------------------------------------------------------

function UI:fill(x, y, text, fg, bg, width)
  text = tostring(text or "")
  width = width or self.width
  if #text > width then
    text = text:sub(1, width)
  end
  self.gpu.setForeground(fg)
  self.gpu.setBackground(bg)
  self.gpu.set(x, y, text .. string.rep(" ", width - #text))
end

function UI:sidebarTop() return 3 end
function UI:sidebarBottom() return self.height - 4 end

function UI:truncate(text, width)
  if #text <= width then return text end
  if width <= 1 then return text:sub(1, width) end
  return text:sub(1, width - 1) .. "~"
end

function UI:drawHeader()
  local title = " OC Advanced TODO"
  local backend = self.store:name() .. " "
  self:fill(1, 1, title, ACCENT_FG, ACCENT_BG)
  self:fill(1 + #title, 1, "", ACCENT_FG, ACCENT_BG, self.width - #title)
  local bwidth = math.min(#backend, self.width)
  self:fill(self.width - bwidth + 1, 1, backend, ACCENT_FG, ACCENT_BG, bwidth)
  self:fill(1, 2, string.rep("-", self.width), LINE_FG, BG)
end

function UI:drawList()
  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  local todos = self.store:list()
  local visible = bottom - top + 1

  if self.selected > #todos then
    self.selected = #todos
  end
  if self.selected < 1 then self.selected = 1 end

  if self.selected - 1 < self.offset then
    self.offset = self.selected - 1
  elseif self.selected > self.offset + visible then
    self.offset = self.selected - visible
  end

  for row = 1, visible do
    local y = top + row - 1
    local todo = todos[self.offset + row]
    if not todo then
      self:fill(1, y, "", FG, BG)
    else
      local idx = self.offset + row
      local isSel = idx == self.selected
      local fg = todo.done and DONE_FG or FG
      local bg = BG
      if isSel then
        fg = SELECT_FG
        bg = SELECT_BG
      end
      local box = todo.done and "[x] " or "[ ] "
      local line = "  " .. box .. self:truncate(todo.title, self.width - 7)
      self:fill(1, y, line, fg, bg)
    end
  end
end

function UI:drawStatus()
  local y = self.height - 3
  local msg = self.message
  local fg = self.messageColor
  if self.adding then
    msg = "New todo: " .. table.concat(self.buffer)
    fg = ACCENT_FG
  end
  self:fill(1, y, msg or "", fg, BG)
end

function UI:drawHelp()
  local y = self.height - 1
  self.buttons = {}
  local x = 2
  local function button(label, action)
    local text = "[ " .. label .. " ]"
    self:fill(x, y, text, ACCENT_FG, ACCENT_BG, #text)
    self.buttons[#self.buttons + 1] = { x1 = x, x2 = x + #text - 1, action = action }
    x = x + #text + 2
  end
  button("Add", "add")
  button("Delete", "delete")
  button("Quit", "quit")
  self:fill(x, y, "click a row to toggle, wheel to scroll", LINE_FG, BG)

  local counts = self:counts()
  local summary = string.format("  %d open / %d total", counts.open, counts.total)
  self:fill(1, y + 1, summary, LINE_FG, BG)
end

function UI:counts()
  local todos = self.store:list()
  local open = 0
  for _, t in ipairs(todos) do
    if not t.done then open = open + 1 end
  end
  return { open = open, total = #todos }
end

function UI:draw()
  self:drawHeader()
  self:drawList()
  for y = self:sidebarBottom() + 1, self.height do
    if y == self.height - 3 or y == self.height - 1 or y == self.height then
      -- drawn below
    else
      self:fill(1, y, "", FG, BG)
    end
  end
  self:drawStatus()
  self:drawHelp()
end

-- Actions --------------------------------------------------------------

function UI:setMessage(text, color)
  self.message = text
  self.messageColor = color or WARN_FG
end

function UI:currentId()
  local todos = self.store:list()
  local todo = todos[self.selected]
  return todo and todo.id or nil
end

function UI:toggleSelected()
  local todos = self.store:list()
  local todo = todos[self.selected]
  if not todo then return end
  self.store:setDone(todo.id, not todo.done)
end

function UI:deleteSelected()
  local id = self:currentId()
  if not id then return end
  self.store:remove(id)
  self:setMessage("deleted todo")
end

function UI:beginAdd()
  self.adding = true
  self.buffer = {}
  self:setMessage(nil)
end

function UI:commitAdd()
  local title = table.concat(self.buffer)
  self.adding = false
  self.buffer = {}
  if title == "" then
    self:setMessage("nothing to add")
    return
  end
  self.store:add(title)
  self.selected = #self.store:list()
  self:setMessage("added: " .. title, LINE_FG)
end

function UI:cancelAdd()
  self.adding = false
  self.buffer = {}
  self:setMessage("add cancelled")
end

function UI:reload()
  self:setMessage("reloaded", LINE_FG)
end

-- Key handling ---------------------------------------------------------

function UI:handleAddKey(char, code)
  if code == K.enter or code == 28 then
    self:commitAdd()
  elseif code == K.back or code == 14 then
    table.remove(self.buffer)
  elseif code == 1 then
    self:cancelAdd()
  elseif char and char > 0 and char < 128 then
    self.buffer[#self.buffer + 1] = string.char(char)
  end
end

function UI:handleKey(char, code)
  if self.adding then
    return self:handleAddKey(char, code)
  end

  if code == K.up or code == 200 then
    self.selected = self.selected - 1
  elseif code == K.down or code == 208 then
    self.selected = self.selected + 1
  elseif code == K.space or code == 57 or code == K.enter or code == 28 then
    self:toggleSelected()
  elseif code == 0x1E or char == 97 then -- a
    self:beginAdd()
  elseif code == 0x20 or char == 100 then -- d
    self:deleteSelected()
  elseif code == 0x13 or char == 114 then -- r
    self:reload()
  elseif code == 0x10 or char == 113 or code == 1 then -- q / escape
    self.running = false
  end
end

-- Pointer handling -----------------------------------------------------
-- OpenOS delivers mouse input as screen signals:
--   touch  <screen> <x> <y> <button>
--   scroll <screen> <x> <y> <delta>

function UI:rowAt(y)
  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  if y < top or y > bottom then return nil end
  return self.offset + (y - top + 1)
end

function UI:invokeAction(action)
  if action == "add" then
    if self.adding then
      self:cancelAdd()
    else
      self:beginAdd()
    end
  elseif action == "delete" then
    self:deleteSelected()
  elseif action == "quit" then
    self.running = false
  end
end

function UI:handleTouch(x, y, button)
  if button ~= 0 then return end -- left button only

  if y == self.height - 1 then
    for _, b in ipairs(self.buttons or {}) do
      if x >= b.x1 and x <= b.x2 then
        self:invokeAction(b.action)
        return
      end
    end
    return
  end

  if self.adding then return end

  local idx = self:rowAt(y)
  local todos = self.store:list()
  if idx and todos[idx] then
    self.selected = idx
    self:toggleSelected()
  end
end

function UI:handleScroll(_, _, delta)
  if delta > 0 then
    self.selected = self.selected - 1
  elseif delta < 0 then
    self.selected = self.selected + 1
  end
end

function UI:handleEvent(ev)
  local name = ev[1]
  if name == "key_down" then
    self:handleKey(ev[3], ev[4])
  elseif name == "touch" then
    self:handleTouch(ev[3], ev[4], ev[5])
  elseif name == "scroll" then
    self:handleScroll(ev[3], ev[4], ev[5])
  end
end

function UI:loop()
  term.clear()
  while self.running do
    self:draw()
    self:handleEvent(self:readEvent())
  end
  term.clear()
  term.setCursor(1, 1)
  return true
end

UI.keys = K
UI.colors = { BG = BG, FG = FG, ACCENT_BG = ACCENT_BG, ACCENT_FG = ACCENT_FG, SELECT_BG = SELECT_BG, SELECT_FG = SELECT_FG, DONE_FG = DONE_FG }

return UI
