-- Specs for the `ui` framework. Bundled with src/ui.lua into tests/ui_test.lua
-- by build.py, then run under ocplay. Exercises layout, drawing, dispatch and
-- the in-memory buffer without needing a real GPU.

local passed, failed = 0, 0
local function check(name, condition)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. name)
  end
end

-- column layout: fixed children plus a growing spacer
local column = ui.column({
  ui.text("top"),
  ui.spacer({ grow = true }),
  ui.text("bottom"),
})
ui.layout(column, 20, 5)
check("column first child bounds", column.children[1].x == 1 and column.children[1].y == 1 and column.children[1].w == 20)
check("column grow spacer absorbs leftover height", column.children[2].h == 3)
check("column last child at bottom row", column.children[3].y == 5)

-- row layout: grow shares leftover width between fixed siblings
local row = ui.row({ ui.button("A"), ui.text("B", { grow = true }), ui.button("C") })
ui.layout(row, 30, 1)
check("row fixed button width", row.children[1].w == 5)
check("row grow child position", row.children[2].x == 6 and row.children[2].w == 20)
check("row last button position", row.children[3].x == 26 and row.children[3].w == 5)

-- drawing into a memory buffer
local canvas = ui.buffer(20, 5)
canvas:clear()
ui.draw(canvas, column)
check("buffer draws text", canvas:row(1):find("top", 1, true) ~= nil)
check("buffer draws bottom text", canvas:row(5):find("bottom", 1, true) ~= nil)

-- button click dispatch
local clicks = 0
local button = ui.button("Go", { onClick = function() clicks = clicks + 1 end })
local buttonTree = ui.column({ button })
ui.layout(buttonTree, 20, 1)
ui.dispatch(buttonTree, { "touch", "screen", 2, 1, 0 })
check("button click dispatched", clicks == 1)

-- list item dispatch resolves the index
local picked = nil
local list = ui.list({
  grow = true,
  items = { "a", "b", "c" },
  renderItem = function(item) return { text = item } end,
  onItemClick = function(_, index) picked = index end,
})
local listTree = ui.column({ list })
ui.layout(listTree, 10, 3)
ui.dispatch(listTree, { "touch", "screen", 1, 2, 0 })
check("list click resolves item index", picked == 2)

-- container backgrounds prevent stale cells leaking between views
local repaint = ui.buffer(10, 1)
ui.draw(repaint, ui.layout(ui.column({ ui.text("AAAAAAAAAA") }), 10, 1))
ui.draw(repaint, ui.layout(ui.column({ ui.text("BB") }), 10, 1))
check("container repaints background over old content", repaint:row(1) == "BB        ")

-- fills never write past the canvas edge (which would wrap on real hardware)
local edge = ui.buffer(10, 1)
edge:fill(8, 1, "ABCDE", 0xFFFFFF, 0x000000)
check("fill clips at the right edge", edge:row(1) == "       ABC")
local offscreen = ui.buffer(5, 1)
offscreen:fill(9, 1, "XX", 0xFFFFFF, 0x000000)
check("fill ignores out-of-bounds x", offscreen:row(1) == "     ")

-- checked checkbox renders a filled box
local checkbox = ui.checkbox("Done", true)
local checkboxCanvas = ui.buffer(12, 1)
ui.draw(checkboxCanvas, ui.layout(ui.row({ checkbox }), 12, 1))
check("checked checkbox renders", checkboxCanvas:row(1):find("[x]", 1, true) ~= nil)

-- disabled buttons do not fire
local disabledClicks = 0
local disabled = ui.button("No", { disabled = true, onClick = function() disabledClicks = disabledClicks + 1 end })
local disabledTree = ui.column({ disabled })
ui.layout(disabledTree, 20, 1)
ui.dispatch(disabledTree, { "touch", "screen", 2, 1, 0 })
check("disabled button ignores clicks", disabledClicks == 0)

print(string.format("%s: ui specs (%d passed, %d failed)",
  failed == 0 and "PASS" or "FAIL", passed, failed))
return failed == 0
