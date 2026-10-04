-- Non-interactive self-test for the todo UI.
-- Drives the UI with a scripted mix of keyboard and pointer events and asserts
-- the resulting store.  Run with:
--   ocplay ./tests/computer.yaml ./tests/self_test.lua

package.path = "/app/?.lua;/app/lib/?.lua;" .. package.path

local Store = require("store")
local UI = require("ui")

local function key(char, code)
  return { "key_down", "keyboard", char or 0, code or 0, "player" }
end
local function touch(x, y, button)
  return { "touch", "screen", x, y, button or 0 }
end
local function scroll(x, y, delta)
  return { "scroll", "screen", x, y, delta }
end

local queue = {
  touch(5, 3),                                  -- click first row: select + toggle open -> done
  scroll(5, 3, -1),                             -- wheel down: select next row
  key(97, 30),                                  -- a: begin add
  key(78, 0), key(101, 0), key(119, 0), key(32, 0), key(116, 0), -- "New t"
  key(0, 28),                                   -- enter: commit add
  touch(25, 24),                                -- click the "Quit" button ([ Quit ] at x 23..30)
}

local function input()
  local item = table.remove(queue, 1)
  if item then return table.unpack(item) end
  return table.unpack(key(113, 16))
end

local function fail(msg)
  print("FAIL: " .. msg)
end

local function main()
  local store = Store.new("memory")
  local ui = UI.new(store, { input = input })
  ui:loop()

  local todos = store:list()
  local open = 0
  for _, t in ipairs(todos) do if not t.done then open = open + 1 end end

  local ok = true
  if #todos ~= 6 then fail("expected 6 todos, got " .. #todos); ok = false end
  if open ~= 3 then fail("expected 3 open, got " .. open); ok = false end
  if not (todos[1] and todos[1].done) then fail("click should have toggled todo #1 done"); ok = false end
  if not (todos[2] and todos[2].done) then fail("todo #2 should stay done"); ok = false end

  print(ok and "PASS: todo self-test" or "SELF-TEST FAILED")
  return ok
end

local ok, err = xpcall(main, debug and debug.traceback or tostring)
if not ok then
  print("ERROR: " .. tostring(err))
end
