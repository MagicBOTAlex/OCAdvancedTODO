-- PocketBase backend stub.
--
-- TODO: implement the Store backend interface by talking to a PocketBase
-- collection over the internet component. The planned collection shape is:
--
--   collection: "todos"
--   fields: id (string), title (text), done (bool)
--
-- Endpoints (see https://pocketbase.io/docs/api-records/):
--   GET    {url}/api/collections/todos/records          list
--   POST   {url}/api/collections/todos/records          create
--   PATCH  {url}/api/collections/todos/records/{id}     update done
--   DELETE {url}/api/collections/todos/records/{id}     remove
--
-- Auth (optional): POST {url}/api/collections/users/auth-with-password
-- and send the returned token as the "Authorization" header.
--
-- This stub only records its configuration so the wiring can be tested before
-- the HTTP/JSON layer is written.

local PocketBase = {}
PocketBase.__index = PocketBase

function PocketBase.new(opts)
  opts = opts or {}
  local self = setmetatable({
    url = opts.url or "http://127.0.0.1:8090",
    collection = opts.collection or "todos",
    token = opts.token,
  }, PocketBase)
  return self
end

function PocketBase:name()
  return "pocketbase (" .. self.url .. "/" .. self.collection .. ") [not implemented]"
end

local function todo()
  error("pocketbase backend is not implemented yet", 2)
end

PocketBase.list = todo
PocketBase.add = todo
PocketBase.setDone = todo
PocketBase.remove = todo

return PocketBase
