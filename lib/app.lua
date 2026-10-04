-- Application wiring: builds a UI around a Store and runs the input loop.

local UI = require("ui")

local App = {}

function App.run(store, opts)
  opts = opts or {}
  local ui = UI.new(store, { input = opts.input })
  return ui:loop()
end

return App
