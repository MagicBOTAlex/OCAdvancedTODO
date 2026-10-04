-- todo.lua (source) -- OC Advanced TODO, built on the `ui` framework.
--
-- Do not run this file directly: build.py bundles it with src/ui.lua into the
-- single-file ../todo.lua that runs on an OpenComputers computer.

local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local component = require("component")

local args = { ... }

--============================================================================
-- Store: swappable persistence backend
--============================================================================
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

--============================================================================
-- App
--============================================================================

local App = {}
App.__index = App

function App.new(store, opts)
  opts = opts or {}
  return setmetatable({
    store = store,
    canvas = opts.canvas,
    input = opts.input,
    keyboard = opts.keyboard and true or false,
    running = true,
    view = "list",
    selected = 1,
    offset = 0,
    multi = false,
    showDone = false,
    detailId = nil,
    adding = false,
    buffer = {},
    message = nil,
    messageFg = ui.theme.warnFg,
  }, App)
end

function App:pull()
  if self.input then return self.input() end
  return event.pull()
end

function App:setMessage(text, fg)
  self.message = text
  self.messageFg = fg or ui.theme.warnFg
end

function App:truncate(text, width)
  text = tostring(text or "")
  if width <= 0 then return "" end
  if #text <= width then return text end
  if width <= 1 then return text:sub(1, width) end
  return text:sub(1, width - 1) .. "~"
end

function App:wrap(text, width)
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

-- Rows shown in the list: open todos only, unless completed ones are expanded.
function App:visible()
  local all = self.store:list()
  if self.showDone then return all end
  local out = {}
  for _, t in ipairs(all) do
    if not t.done then out[#out + 1] = t end
  end
  return out
end

function App:counts()
  local open = 0
  local todos = self.store:list()
  for _, t in ipairs(todos) do
    if not t.done then open = open + 1 end
  end
  return { open = open, total = #todos }
end

function App:detailTodo()
  local list = self.store:list()
  for _, t in ipairs(list) do
    if t.id == self.detailId then return t end
  end
  return list[self.selected]
end

function App:currentId()
  local todo = self:visible()[self.selected]
  return todo and todo.id or nil
end

function App:clampSelection(total)
  if self.selected > total then self.selected = total end
  if self.selected < 1 then self.selected = 1 end
  local viewport = self.canvas.height - 5
  if self.selected - 1 < self.offset then
    self.offset = self.selected - 1
  elseif self.selected > self.offset + viewport then
    self.offset = self.selected - viewport
  end
end

--============================================================================
-- Actions
--============================================================================

function App:toggleSelected()
  if not self.multi then
    self:setMessage("enable Select to complete tasks")
    return
  end
  local todo = self:visible()[self.selected]
  if todo then self.store:setDone(todo.id, not todo.done) end
end

function App:deleteSelected()
  local id = self:currentId()
  if id then
    self.store:remove(id)
    self:setMessage("deleted todo")
  end
end

function App:openDetails()
  self.detailId = self:currentId()
  if self.detailId then self.view = "details" end
end

function App:closeDetails()
  self.view = "list"
end

function App:toggleDetail()
  local todo = self:detailTodo()
  if todo then self.store:setDone(todo.id, not todo.done) end
end

function App:deleteDetail()
  local todo = self:detailTodo()
  if todo then
    self.store:remove(todo.id)
    self:setMessage("deleted todo")
    self.view = "list"
  end
end

function App:toggleMulti()
  self.multi = not self.multi
  self:setMessage(self.multi and "select mode on" or "select mode off", ui.theme.mutedFg)
end

function App:toggleShowDone()
  self.showDone = not self.showDone
  self.selected = 1
  self.offset = 0
  self:setMessage(self.showDone and "showing completed" or "hiding completed", ui.theme.mutedFg)
end

function App:beginAdd()
  self.adding = true
  self.buffer = {}
  self:setMessage(nil)
end

function App:commitAdd()
  local title = table.concat(self.buffer)
  self.adding = false
  self.buffer = {}
  if title == "" then
    self:setMessage("nothing to add")
    return
  end
  self.store:add(title)
  self.selected = #self:visible()
  self:setMessage("added: " .. title, ui.theme.mutedFg)
end

function App:cancelAdd()
  self.adding = false
  self.buffer = {}
  self:setMessage("add cancelled")
end

--============================================================================
-- Views (pure functions of state -> node tree)
--============================================================================

function App:headerView()
  local title = ui.text(" OC Advanced TODO",
    { grow = true, style = { fg = ui.theme.accentFg, bg = ui.theme.accentBg } })
  local backend = ui.text(" " .. self.store:name() .. " ",
    { style = { fg = ui.theme.accentFg, bg = ui.theme.accentBg } })
  return ui.row({ title, backend })
end

function App:listView()
  local todos = self:visible()
  self:clampSelection(#todos)
  local multi = self.multi
  local width = self.canvas.width
  return ui.list({
    grow = true,
    items = todos,
    offset = self.offset,
    renderItem = function(item, index)
      local fg = item.done and ui.theme.mutedFg or ui.theme.fg
      local bg = ui.theme.bg
      if index == self.selected and self.keyboard then
        fg, bg = ui.theme.selectFg, ui.theme.selectBg
      end
      local indent = multi and "  " or "    "
      local prefix = multi and (item.done and "[x] " or "[ ] ") or "  "
      local text = indent .. prefix .. self:truncate(item.title, width - #indent - #prefix)
      return { text = text, fg = fg, bg = bg }
    end,
    onItemClick = function(_, index)
      self.selected = index
      if self.multi then self:toggleSelected() else self:openDetails() end
    end,
  })
end

function App:detailsView()
  local todo = self:detailTodo()
  if not todo then
    self.view = "list"
    return self:listView()
  end
  local width = self.canvas.width
  local w = width - 4
  local function field(label, value, fg)
    return ui.text(string.format("   %-11s%s", label, self:truncate(tostring(value), w - 11)),
      { style = { fg = fg or ui.theme.fg } })
  end
  local children = {
    ui.text(" " .. self:truncate(todo.title, width - 1),
      { style = { fg = ui.theme.accentFg, bg = ui.theme.accentBg } }),
    ui.spacer({ h = 1 }),
    field("Status:", todo.done and "done" or "open", todo.done and ui.theme.mutedFg or ui.theme.fg),
    field("Priority:", todo.priority),
    field("Due:", todo.due),
    field("Created:", todo.created),
    field("ID:", todo.id),
    ui.spacer({ h = 1 }),
    ui.text("   Description:", { style = { fg = ui.theme.mutedFg } }),
  }
  for _, line in ipairs(self:wrap(todo.description or "", w)) do
    children[#children + 1] = ui.text("   " .. line)
  end
  children[#children + 1] = ui.spacer({ grow = true })
  return ui.column(children, { grow = true })
end

function App:statusView()
  local msg, fg = self.message, self.messageFg
  if self.adding then
    msg = "New todo: " .. table.concat(self.buffer)
    fg = ui.theme.accentFg
  elseif not msg then
    if self.view == "details" then
      msg = self.keyboard and "space completes, enter/esc back" or "use the buttons below"
    elseif self.multi then
      msg = "select mode: click a task to complete it"
    else
      msg = "click a task to open details"
    end
  end
  return ui.text(" " .. (msg or ""), { style = { fg = fg } })
end

function App:listButtons()
  return ui.row({
    ui.spacer({ w = 1 }),
    ui.button("Add", { onClick = function() self:beginAdd() end }),
    ui.button(self.multi and "Select:on" or "Select", { onClick = function() self:toggleMulti() end }),
    ui.button("Quit", { onClick = function() self.running = false end }),
    ui.checkbox("Completed", self.showDone, { onClick = function() self:toggleShowDone() end }),
  }, { gap = 2 })
end

function App:detailButtons()
  return ui.row({
    ui.spacer({ w = 1 }),
    ui.button("Back", { onClick = function() self:closeDetails() end }),
    ui.button("Complete", { onClick = function() self:toggleDetail() end }),
    ui.button("Delete", { onClick = function() self:deleteDetail() end }),
    ui.button("Quit", { onClick = function() self.running = false end }),
  }, { gap = 2 })
end

function App:buildView()
  local width = self.canvas.width
  local children = {
    self:headerView(),
    ui.text(string.rep("-", width), { style = { fg = ui.theme.mutedFg } }),
  }
  if self.view == "details" then
    children[#children + 1] = self:detailsView()
  else
    children[#children + 1] = self:listView()
  end
  children[#children + 1] = self:statusView()
  children[#children + 1] = (self.view == "details") and self:detailButtons() or self:listButtons()
  local counts = self:counts()
  children[#children + 1] = ui.text(string.format("  %d open / %d total", counts.open, counts.total),
    { style = { fg = ui.theme.mutedFg } })
  return ui.column(children, { gap = 0 })
end

--============================================================================
-- Event handling
--============================================================================

function App:handleKey(char, code)
  if not self.keyboard then return end
  if self.adding then
    if code == keyboard.keys.enter or code == 28 then
      self:commitAdd()
    elseif code == keyboard.keys.back or code == 14 then
      table.remove(self.buffer)
    elseif code == 1 then
      self:cancelAdd()
    elseif char and char > 0 and char < 128 then
      self.buffer[#self.buffer + 1] = string.char(char)
    end
    return
  end

  if self.view == "details" then
    if code == keyboard.keys.enter or code == 28 or code == 1 then
      self:closeDetails()
    elseif code == keyboard.keys.space or code == 57 then
      self:toggleDetail()
    elseif code == keyboard.keys.up or code == 200 then
      self.selected = self.selected - 1
      self.detailId = self:currentId()
    elseif code == keyboard.keys.down or code == 208 then
      self.selected = self.selected + 1
      self.detailId = self:currentId()
    elseif code == 0x20 or char == 100 then
      self:deleteDetail()
    elseif code == 0x10 or char == 113 then
      self.running = false
    end
    return
  end

  if code == keyboard.keys.up or code == 200 then
    self.selected = self.selected - 1
  elseif code == keyboard.keys.down or code == 208 then
    self.selected = self.selected + 1
  elseif code == keyboard.keys.space or code == 57 then
    if self.multi then self:toggleSelected() else self:openDetails() end
  elseif code == keyboard.keys.enter or code == 28 then
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

function App:handleScroll(_, _, delta)
  if delta > 0 then
    self.selected = self.selected - 1
  elseif delta < 0 then
    self.selected = self.selected + 1
  end
  self:clampSelection(#self:visible())
  if self.view == "details" then
    self.detailId = self:currentId()
  end
end

function App:handleEvent(ev)
  local name = ev[1]
  if name == "key_down" then
    self:handleKey(ev[3], ev[4])
    return true
  elseif name == "scroll" then
    self:handleScroll(ev[3], ev[4], ev[5])
    return true
  end
  return false
end

function App:run()
  ui.run({
    canvas = self.canvas,
    running = function() return self.running end,
    view = function() return self:buildView() end,
    pull = function() return self:pull() end,
    onEvent = function(ev) return self:handleEvent(ev) end,
  })
  if self.canvas.gpu then
    term.clear()
    term.setCursor(1, 1)
  end
  return true
end

--============================================================================
-- Entry
--============================================================================

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
  local canvas = ui.buffer(80, 25)
  local app = App.new(store, { canvas = canvas, input = input, keyboard = true })
  app:run()

  local todos = store:list()
  local open = 0
  for _, t in ipairs(todos) do
    if not t.done then open = open + 1 end
  end

  local rendered = canvas:row(1):find("OC Advanced TODO", 1, true) ~= nil
  local listed = false
  for y = 1, 25 do
    if canvas:row(y):find("Buy groceries", 1, true) then listed = true end
  end

  local ok = #todos == 6 and open == 2
    and todos[1] and todos[1].done
    and todos[2] and todos[2].done
    and todos[3] and todos[3].done
    and rendered and listed
  print(ok and "PASS: todo self-test" or "SELF-TEST FAILED")
  print(string.format("  total=%d open=%d done={%s,%s,%s} rendered=%s listed=%s",
    #todos, open,
    tostring(todos[1] and todos[1].done),
    tostring(todos[2] and todos[2].done),
    tostring(todos[3] and todos[3].done),
    tostring(rendered), tostring(listed)))
  return ok
end

local function main()
  if args[1] == "--self-test" then
    return runSelfTest()
  end
  local ok, err = pcall(function()
    term.clear()
    local canvas = ui.canvas(component.gpu)
    local app = App.new(Store.new("memory"), { canvas = canvas })
    return app:run()
  end)
  if not ok then
    term.clear()
    term.setCursor(1, 1)
    print("todo error: " .. tostring(err))
    return false
  end
  return true
end

return main()
