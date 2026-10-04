-- In-memory todo backend seeded with dummy data.
-- Data lives only for the session; swap in backends/pocketbase.lua later
-- without touching the app.

local Memory = {}
Memory.__index = Memory

local SEED = {
  { title = "Buy groceries", done = false },
  { title = "Write documentation", done = true },
  { title = "Pay the reactor bill", done = false },
  { title = "Refuel the reactor", done = false },
  { title = "Call Steve", done = true },
}

function Memory.new(seed)
  local self = setmetatable({ todos = {}, nextId = 1, seq = 0 }, Memory)
  for _, item in ipairs(seed or SEED) do
    self:add(item.title)
    local last = self.todos[#self.todos]
    if last then last.done = item.done and true or false end
  end
  return self
end

function Memory:name()
  return "memory (dummy data)"
end

function Memory:list()
  local out = {}
  for i, t in ipairs(self.todos) do
    out[i] = { id = t.id, title = t.title, done = t.done }
  end
  return out
end

function Memory:add(title)
  title = tostring(title or "")
  if title == "" then
    error("cannot add an empty todo", 2)
  end
  self.seq = self.seq + 1
  local todo = { id = "t" .. self.seq, title = title, done = false }
  self.todos[#self.todos + 1] = todo
  return { id = todo.id, title = todo.title, done = todo.done }
end

function Memory:setDone(id, done)
  for _, t in ipairs(self.todos) do
    if t.id == id then
      t.done = done and true or false
      return { id = t.id, title = t.title, done = t.done }
    end
  end
  return nil
end

function Memory:remove(id)
  for i, t in ipairs(self.todos) do
    if t.id == id then
      table.remove(self.todos, i)
      return true
    end
  end
  return false
end

return Memory
