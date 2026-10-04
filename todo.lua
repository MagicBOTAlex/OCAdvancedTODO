-- OCAdvancedTODO entry point.
-- This file is copied by ocplay to /home/ocplay_autorun.lua and executed once
-- OpenOS has booted. The project directory is mounted at /app (see computer.yaml).

package.path = "/app/?.lua;/app/lib/?.lua;/app/lib/?/init.lua;" .. package.path

local Store = require("store")
local App = require("app")

local store = Store.new("memory")

local ok, err = pcall(App.run, store)
if not ok then
  print("todo error: " .. tostring(err))
  return 1
end
