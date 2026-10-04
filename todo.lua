-- OC Advanced TODO
--
-- A self-contained, interactive todo list for OpenComputers / OpenOS.
-- Copy this single file to your computer and run it (e.g. `todo`, `todo.lua`,
-- or `/home/todo.lua`).
--
-- Controls
--   up / down, wheel      move the selection
--   space / enter / click toggle the clicked/selected todo
--   a  (or [ Add ])       add a todo (type the title, enter to save, esc to cancel)
--   d  (or [ Delete ])    delete the selected todo
--   click [ Quit ] / q    leave the program
--
-- Currently backed by dummy in-memory data. The `Store`/backends section below
-- is the seam where a PocketBase backend will plug in via the `internet`
-- component.

local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local component = require("component")

local args = { ... }

-- ===========================================================================
-- Store: swappable persistence backend
-- ===========================================================================
-- A backend implements:
--   name()            -> string
--   list()            -> array of { id, title, done }
--   add(title)        -> todo
--   setDone(id, b)    -> todo
--   remove(id)        -> boolean

local Store = {}
Store.__index = Store

local memory = {}

local SEED = {
  { title = "Buy groceries", done = false },
  { title = "Write documentation", done = true },
  { title = "Pay the reactor bill", done = false },
  { title = "Refuel the reactor", done = false },
  { title = "Call Steve", done = true },
}

function memory.new(seed)
  local self = setmetatable({ todos = {}, seq = 0 }, { __index = memory })
  for _, item in ipairs(seed or SEED) do
    local todo = self:add(item.title)
    self:setDone(todo.id, item.done)
  end
  return self
end

function memory:name() return "memory (dummy data)" end

function memory:list()
  local out = {}
  for i, t in ipairs(self.todos) do
    out[i] = { id = t.id, title = t.title, done = t.done }
  end
  return out
end

function memory:add(title)
  title = tostring(title or "")
  if title == "" then error("cannot add an empty todo", 2) end
  self.seq = self.seq + 1
  local todo = { id = "t" .. self.seq, title = title, done = false }
  self.todos[#self.todos + 1] = todo
  return { id = todo.id, title = todo.title, done = todo.done }
end

function memory:setDone(id, done)
  for _, t in ipairs(self.todos) do
    if t.id == id then
      t.done = done and true or false
      return { id = t.id, title = t.title, done = t.done }
    end
  end
  return nil
end

function memory:remove(id)
  for i, t in ipairs(self.todos) do
    if t.id == id then
      table.remove(self.todos, i)
      return true
    end
  end
  return false
end

-- PocketBase backend placeholder. Planned collection "todos" with fields
-- id/title/done, accessed over HTTP through the `internet` component once the
-- request/JSON layer is written.
local pocketbase = {}
pocketbase.__index = pocketbase

function pocketbase.new(opts)
  opts = opts or {}
  return setmetatable({
    url = opts.url or "http://127.0.0.1:8090",
    collection = opts.collection or "todos",
  }, pocketbase)
end
function pocketbase:name() return "pocketbase (not implemented)" end
local function todo() error("pocketbase backend is not implemented yet", 2) end
pocketbase.list = todo
pocketbase.add = todo
pocketbase.setDone = todo
pocketbase.remove = todo

function Store.new(kind, opts)
  if kind == "memory" or kind == nil then
    return setmetatable({ backend = memory.new(opts) }, Store)
  elseif kind == "pocketbase" then
    return setmetatable({ backend = pocketbase.new(opts) }, Store)
  end
  error("unknown store backend: " .. tostring(kind), 2)
end

Store.name = function(self) return self.backend:name() end
Store.list = function(self) return self.backend:list() end
Store.add = function(self, title) return self.backend:add(title) end
Store.setDone = function(self, id, done) return self.backend:setDone(id, done) end
Store.remove = function(self, id) return self.backend:remove(id) end

-- ===========================================================================
-- UI
-- ===========================================================================

local UI = {}
UI.__index = UI

local K = keyboard.keys

-- Packed 24-bit RGB. Do NOT use require("colors"): it returns palette indices
-- (white = 0) and the GPU treats a bare number as RGB, so 0 paints black.
local BG = 0x000000
local FG = 0xFFFFFF
local ACCENT_BG = 0x333399
local ACCENT_FG = 0xFFFFFF
local DONE_FG = 0x808080
local SELECT_BG = 0xCCCCCC
local SELECT_FG = 0x000000
local WARN_FG = 0xFFFF33
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

function UI:pull(...)
  if self.input then return self.input(...) end
  return event.pull(...)
end

function UI:readEvent()
  return table.pack(self:pull())
end

function UI:fill(x, y, text, fg, bg, width)
  text = tostring(text or "")
  width = width or self.width
  if #text > width then text = text:sub(1, width) end
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
  local bwidth = math.min(#backend, self.width)
  self:fill(self.width - bwidth + 1, 1, backend, ACCENT_FG, ACCENT_BG, bwidth)
  self:fill(1, 2, string.rep("-", self.width), LINE_FG, BG)
end

function UI:drawList()
  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  local todos = self.store:list()
  local visible = bottom - top + 1

  if self.selected > #todos then self.selected = #todos end
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
      local fg = todo.done and DONE_FG or FG
      local bg = BG
      if idx == self.selected then
        fg = SELECT_FG
        bg = SELECT_BG
      end
      local box = todo.done and "[x] " or "[ ] "
      self:fill(1, y, "  " .. box .. self:truncate(todo.title, self.width - 7), fg, bg)
    end
  end
end

function UI:drawStatus()
  local y = self.height - 3
  local msg, fg = self.message, self.messageColor
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
  self:fill(1, y + 1, string.format("  %d open / %d total", counts.open, counts.total), LINE_FG, BG)
end

function UI:counts()
  local open = 0
  local todos = self.store:list()
  for _, t in ipairs(todos) do if not t.done then open = open + 1 end end
  return { open = open, total = #todos }
end

function UI:draw()
  self:drawHeader()
  self:drawList()
  self:drawStatus()
  self:drawHelp()
end

function UI:setMessage(text, color)
  self.message = text
  self.messageColor = color or WARN_FG
end

function UI:currentId()
  local todo = self.store:list()[self.selected]
  return todo and todo.id or nil
end

function UI:toggleSelected()
  local todo = self.store:list()[self.selected]
  if todo then self.store:setDone(todo.id, not todo.done) end
end

function UI:deleteSelected()
  local id = self:currentId()
  if id then
    self.store:remove(id)
    self:setMessage("deleted todo")
  end
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
  if self.adding then return self:handleAddKey(char, code) end

  if code == K.up or code == 200 then
    self.selected = self.selected - 1
  elseif code == K.down or code == 208 then
    self.selected = self.selected + 1
  elseif code == K.space or code == 57 or code == K.enter or code == 28 then
    self:toggleSelected()
  elseif code == 0x1E or char == 97 then
    self:beginAdd()
  elseif code == 0x20 or char == 100 then
    self:deleteSelected()
  elseif code == 0x10 or char == 113 or code == 1 then
    self.running = false
  end
end

function UI:invokeAction(action)
  if action == "add" then
    if self.adding then self:cancelAdd() else self:beginAdd() end
  elseif action == "delete" then
    self:deleteSelected()
  elseif action == "quit" then
    self.running = false
  end
end

function UI:handleTouch(x, y, button)
  if button ~= 0 then return end

  if y == self.height - 1 then
    for _, b in ipairs(self.buttons) do
      if x >= b.x1 and x <= b.x2 then
        self:invokeAction(b.action)
        return
      end
    end
    return
  end

  if self.adding then return end

  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  if y >= top and y <= bottom then
    local idx = self.offset + (y - top + 1)
    if self.store:list()[idx] then
      self.selected = idx
      self:toggleSelected()
    end
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

-- ===========================================================================
-- Entry
-- ===========================================================================

local function runSelfTest()
  local function key(c, code) return { "key_down", "keyboard", c or 0, code or 0, "player" } end
  local function touch(x, y) return { "touch", "screen", x, y, 0 } end
  local queue = {
    touch(5, 3),                                   -- click first row: toggle done
    { "scroll", "screen", 5, 3, -1 },              -- wheel down
    key(97, 30), key(78), key(101), key(119), key(32), key(116), -- a + "New t"
    key(0, 28),                                    -- enter
    touch(25, 24),                                 -- Quit button
  }
  local function input()
    local item = table.remove(queue, 1)
    if item then return table.unpack(item) end
    return table.unpack(key(113, 16))
  end

  local store = Store.new("memory")
  local ui = UI.new(store, { input = input })
  ui:loop()

  local todos = store:list()
  local open = 0
  for _, t in ipairs(todos) do if not t.done then open = open + 1 end end

  local ok = #todos == 6 and open == 3 and todos[1] and todos[1].done and todos[2] and todos[2].done
  print(ok and "PASS: todo self-test" or "SELF-TEST FAILED")
  print(string.format("  total=%d open=%d firstDone=%s", #todos, open, tostring(todos[1] and todos[1].done)))
  return ok
end

local function main()
  if args[1] == "--self-test" then
    return runSelfTest()
  end
  local store = Store.new("memory")
  local ok, err = pcall(function() return UI.new(store):loop() end)
  if not ok then
    term.clear()
    term.setCursor(1, 1)
    print("todo error: " .. tostring(err))
    return false
  end
  return true
end

return main()
