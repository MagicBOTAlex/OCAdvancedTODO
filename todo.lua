-- OC Advanced TODO
--
-- A self-contained, interactive todo list for OpenComputers / OpenOS.
-- Copy this single file to your computer and run it (e.g. `todo`, `todo.lua`,
-- or `/home/todo.lua`).
--
-- Controls (in-game: pointer/touch only)
--   click a task          open its details (or complete it in select mode)
--   click [ Add ]         add a todo
--   click [ Select ]      toggle select mode (checkboxes) for completing tasks
--   click [ ] Completed   show / hide completed todos
--   click [ Quit ]        leave the program
--   wheel / drag          scroll the list
--
-- There is no keyboard in-game: row selection and key handling are disabled by
-- default. Pass keyboard = true to UI.new (as --self-test does) to exercise the
-- selected-task keyboard path during development.
--
-- Completed todos are collapsed by default.
--
-- To start it automatically on boot (in-game), add to /home/.shrc:
--   dofile("/home/todo.lua")
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
--   list()            -> array of
--                        { id, title, done, description, priority, due, created }
--   add(title)        -> todo
--   setDone(id, b)    -> todo
--   remove(id)        -> boolean

local Store = {}
Store.__index = Store

local memory = {}

local SEED = {
  { title = "Buy groceries", done = false, priority = "high", due = "2026-10-06",
    created = "2026-10-01", description = "Milk, eggs, bread and reactor coolant snacks." },
  { title = "Write documentation", done = true, priority = "normal", due = "2026-10-03",
    created = "2026-09-28", description = "Document the store backend interface and the PocketBase plan." },
  { title = "Pay the reactor bill", done = false, priority = "high", due = "2026-10-15",
    created = "2026-10-02", description = "Overdue bills shut the reactor down. Do not let that happen." },
  { title = "Refuel the reactor", done = false, priority = "low", due = "2026-10-20",
    created = "2026-10-02", description = "Two uranium rods should be enough for the next cycle." },
  { title = "Call Steve", done = true, priority = "normal", due = "-",
    created = "2026-09-30", description = "Ask Steve about the redstone wiring." },
}

function memory.copy(t)
  return {
    id = t.id, title = t.title, done = t.done,
    description = t.description, priority = t.priority,
    due = t.due, created = t.created,
  }
end

function memory.new(seed)
  local self = setmetatable({ todos = {}, seq = 0 }, { __index = memory })
  for _, item in ipairs(seed or SEED) do
    self:insert(item)
  end
  return self
end

function memory:insert(fields)
  self.seq = self.seq + 1
  local todo = {
    id = "t" .. self.seq,
    title = tostring(fields.title or ""),
    done = fields.done and true or false,
    description = fields.description or "",
    priority = fields.priority or "normal",
    due = fields.due or "-",
    created = fields.created or "-",
  }
  self.todos[#self.todos + 1] = todo
  return memory.copy(todo)
end

function memory:name() return "memory (dummy data)" end

function memory:list()
  local out = {}
  for i, t in ipairs(self.todos) do
    out[i] = memory.copy(t)
  end
  return out
end

function memory:add(title)
  title = tostring(title or "")
  if title == "" then error("cannot add an empty todo", 2) end
  return self:insert({ title = title })
end

function memory:setDone(id, done)
  for _, t in ipairs(self.todos) do
    if t.id == id then
      t.done = done and true or false
      return memory.copy(t)
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
    view = "list",
    detailId = nil,
    multi = false,
    showDone = false,
    keyboard = opts.keyboard and true or false,
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

-- The rows shown in the list: open todos only, unless completed ones are
-- expanded. Selection indices always refer to this filtered list.
function UI:visible()
  local all = self.store:list()
  if self.showDone then return all end
  local out = {}
  for _, t in ipairs(all) do
    if not t.done then out[#out + 1] = t end
  end
  return out
end

function UI:drawList()
  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  local todos = self:visible()
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
      if idx == self.selected and self.keyboard then
        fg = SELECT_FG
        bg = SELECT_BG
      end
      if self.multi then
        local box = todo.done and "[x] " or "[ ] "
        self:fill(1, y, "  " .. box .. self:truncate(todo.title, self.width - 7), fg, bg)
      else
        self:fill(1, y, "  " .. self:truncate(todo.title, self.width - 4), fg, bg)
      end
    end
  end
end

function UI:wrap(text, width)
  local lines = {}
  for paragraph in tostring(text):gmatch("[^\n]+") do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      if line == "" then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    lines[#lines + 1] = line
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

function UI:detailTodo()
  local list = self.store:list()
  for _, t in ipairs(list) do
    if t.id == self.detailId then return t end
  end
  return list[self.selected]
end

function UI:drawDetails()
  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  for y = top, bottom do self:fill(1, y, "", FG, BG) end

  local todo = self:detailTodo()
  if not todo then
    self.view = "list"
    return
  end

  local x, w = 3, self.width - 4
  self:fill(x, top, self:truncate(todo.title, w), ACCENT_FG, ACCENT_BG, w)

  local y = top + 2
  local function field(label, value, fg)
    if y > bottom then return end
    self:fill(x, y, label, LINE_FG, BG)
    self:fill(x + 11, y, self:truncate(tostring(value), w - 11), fg or FG, BG)
    y = y + 1
  end
  field("Status:", todo.done and "done" or "open", todo.done and DONE_FG or FG)
  field("Priority:", todo.priority)
  field("Due:", todo.due)
  field("Created:", todo.created)
  field("ID:", todo.id)

  y = y + 1
  if y <= bottom then
    self:fill(x, y, "Description:", LINE_FG, BG)
    y = y + 1
  end
  for _, line in ipairs(self:wrap(todo.description or "", w)) do
    if y > bottom then break end
    self:fill(x, y, line, FG, BG)
    y = y + 1
  end
end

function UI:drawStatus()
  local y = self.height - 3
  local msg, fg = self.message, self.messageColor
  if self.adding then
    msg = "New todo: " .. table.concat(self.buffer)
    fg = ACCENT_FG
  elseif not msg then
    if self.view == "details" then
      msg = self.keyboard and "space completes, enter/esc back" or "use the buttons below"
    elseif self.multi then
      msg = "select mode: click a task to complete it"
    else
      msg = "click a task to open details"
    end
  end
  self:fill(1, y, msg or "", fg, BG)
end

function UI:drawHelp()
  local y = self.height - 1
  self:fill(1, y, "", LINE_FG, BG)
  self.buttons = {}
  local x = 2
  local function button(label, action)
    local text = "[ " .. label .. " ]"
    self:fill(x, y, text, ACCENT_FG, ACCENT_BG, #text)
    self.buttons[#self.buttons + 1] = { x1 = x, x2 = x + #text - 1, action = action }
    x = x + #text + 2
  end
  local function raw(text, action, fg)
    self:fill(x, y, text, fg or ACCENT_FG, ACCENT_BG, #text)
    self.buttons[#self.buttons + 1] = { x1 = x, x2 = x + #text - 1, action = action }
    x = x + #text + 2
  end
  if self.view == "details" then
    button("Back", "back")
    button("Complete", "toggle")
    button("Delete", "delete")
    button("Quit", "quit")
    if self.keyboard then
      self:fill(x, y, "enter/esc back, space completes", LINE_FG, BG)
    end
  else
    button("Add", "add")
    button(self.multi and "Select:on" or "Select", "select")
    button("Quit", "quit")
    raw(self.showDone and "[x] Completed" or "[ ] Completed", "showdone")
  end

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
  if self.view == "details" then
    self:drawDetails()
  else
    self:drawList()
  end
  self:drawStatus()
  self:drawHelp()
end

function UI:setMessage(text, color)
  self.message = text
  self.messageColor = color or WARN_FG
end

function UI:currentId()
  local todo = self:visible()[self.selected]
  return todo and todo.id or nil
end

function UI:toggleSelected()
  if not self.multi then
    self:setMessage("enable Select to complete tasks")
    return
  end
  local todo = self:visible()[self.selected]
  if todo then self.store:setDone(todo.id, not todo.done) end
end

function UI:toggleMulti()
  self.multi = not self.multi
  self:setMessage(self.multi and "select mode on" or "select mode off", LINE_FG)
end

function UI:toggleShowDone()
  self.showDone = not self.showDone
  self.offset = 0
  self.selected = 1
  self:setMessage(self.showDone and "showing completed" or "hiding completed", LINE_FG)
end

function UI:deleteSelected()
  local id = self:currentId()
  if id then
    self.store:remove(id)
    self:setMessage("deleted todo")
  end
end

function UI:openDetails()
  self.detailId = self:currentId()
  if self.detailId then self.view = "details" end
end

function UI:closeDetails()
  self.view = "list"
end

function UI:toggleDetail()
  local todo = self:detailTodo()
  if todo then self.store:setDone(todo.id, not todo.done) end
end

function UI:deleteDetail()
  local todo = self:detailTodo()
  if todo then
    self.store:remove(todo.id)
    self:setMessage("deleted todo")
    self.view = "list"
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
  self.selected = #self:visible()
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

function UI:handleDetailsKey(char, code)
  if code == K.enter or code == 28 or code == 1 then
    self:closeDetails()
  elseif code == K.space or code == 57 then
    self:toggleDetail()
  elseif code == K.up or code == 200 then
    self.selected = self.selected - 1
    self.detailId = self:currentId()
  elseif code == K.down or code == 208 then
    self.selected = self.selected + 1
    self.detailId = self:currentId()
  elseif code == 0x20 or char == 100 then
    self:deleteDetail()
  elseif code == 0x10 or char == 113 then
    self.running = false
  end
end

function UI:handleKey(char, code)
  if not self.keyboard then return end
  if self.adding then return self:handleAddKey(char, code) end
  if self.view == "details" then return self:handleDetailsKey(char, code) end

  if code == K.up or code == 200 then
    self.selected = self.selected - 1
  elseif code == K.down or code == 208 then
    self.selected = self.selected + 1
  elseif code == K.space or code == 57 then
    if self.multi then self:toggleSelected() else self:openDetails() end
  elseif code == K.enter or code == 28 then
    self:openDetails()
  elseif code == 0x1E or char == 97 then
    self:beginAdd()
  elseif code == 0x20 or char == 100 then
    self:deleteSelected()
  elseif code == 0x32 or char == 109 then
    self:toggleMulti()
  elseif code == 0x2E or char == 99 then
    self:toggleShowDone()
  elseif code == 0x10 or char == 113 or code == 1 then
    self.running = false
  end
end

function UI:invokeAction(action)
  if action == "add" then
    if self.adding then self:cancelAdd() else self:beginAdd() end
  elseif action == "details" then
    self:openDetails()
  elseif action == "back" then
    self:closeDetails()
  elseif action == "select" then
    self:toggleMulti()
  elseif action == "showdone" then
    self:toggleShowDone()
  elseif action == "toggle" then
    if self.view == "details" then self:toggleDetail() elseif self.multi then self:toggleSelected() end
  elseif action == "delete" then
    if self.view == "details" then self:deleteDetail() else self:deleteSelected() end
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

  if self.adding or self.view == "details" then return end

  local top, bottom = self:sidebarTop(), self:sidebarBottom()
  if y >= top and y <= bottom then
    local idx = self.offset + (y - top + 1)
    if self:visible()[idx] then
      self.selected = idx
      if self.multi then
        self:toggleSelected()
      else
        self:openDetails()
      end
    end
  end
end

function UI:handleScroll(_, _, delta)
  if delta > 0 then
    self.selected = self.selected - 1
  elseif delta < 0 then
    self.selected = self.selected + 1
  end
  if self.view == "details" then
    self.detailId = self:currentId()
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
    touch(5, 3),                                   -- click row 1: open details (not toggle)
    key(0, 57),                                    -- space in details: mark t1 complete
    key(0, 1),                                     -- esc: back to the list (t1 now hidden)
    key(109, 50),                                  -- m: enable select mode
    key(0, 57),                                    -- space: complete the selected (t3)
    key(97, 30), key(78), key(101), key(119), key(32), key(116), -- a + "New t"
    key(0, 28),                                    -- enter: commit add (t6)
    key(99, 46),                                   -- c: show completed
    key(113, 16),                                  -- q: quit
  }
  local function input()
    local item = table.remove(queue, 1)
    if item then return table.unpack(item) end
    return table.unpack(key(113, 16))
  end

  local store = Store.new("memory")
  local ui = UI.new(store, { input = input, keyboard = true })
  ui:loop()

  local todos = store:list()
  local open = 0
  for _, t in ipairs(todos) do if not t.done then open = open + 1 end end

  local ok = #todos == 6 and open == 2
    and todos[1] and todos[1].done
    and todos[2] and todos[2].done
    and todos[3] and todos[3].done
  print(ok and "PASS: todo self-test" or "SELF-TEST FAILED")
  print(string.format("  total=%d open=%d done={%s,%s,%s}",
    #todos, open,
    tostring(todos[1] and todos[1].done),
    tostring(todos[2] and todos[2].done),
    tostring(todos[3] and todos[3].done)))
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
