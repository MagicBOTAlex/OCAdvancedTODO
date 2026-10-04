-- Store: a thin wrapper around a persistence backend.
--
-- Backends implement this interface (all methods may raise on failure):
--   backend.name()          -> string   human-readable backend description
--   backend.list()          -> array    todos: { id = any, title = string, done = boolean }
--   backend.add(title)      -> todo     create and return the new todo
--   backend.setDone(id, b)  -> todo     update completion state, return updated todo
--   backend.remove(id)      -> boolean  true when a todo was removed
--
-- The only backend today is "memory" (dummy data). The "pocketbase" backend is
-- stubbed and will talk to a PocketBase collection over the internet component.

local Store = {}
Store.__index = Store

local backends = {
  memory = function() return require("backends.memory").new() end,
  pocketbase = function(opts) return require("backends.pocketbase").new(opts) end,
}

function Store.new(kind, opts)
  local factory = backends[kind]
  if not factory then
    error("unknown store backend: " .. tostring(kind), 2)
  end
  return setmetatable({ backend = factory(opts) }, Store)
end

function Store:name()
  return self.backend:name()
end

function Store:list()
  return self.backend:list()
end

function Store:add(title)
  return self.backend:add(title)
end

function Store:setDone(id, done)
  return self.backend:setDone(id, done)
end

function Store:remove(id)
  return self.backend:remove(id)
end

return Store
