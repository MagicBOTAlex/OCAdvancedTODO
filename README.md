# OCAdvancedTODO

An interactive todo list for OpenComputers / OpenOS, plus `ui` — a small
component-based terminal UI framework that is reusable in other projects.

## Layout

| Path | Purpose |
| --- | --- |
| `src/ui.lua` | The `ui` framework (reusable, dependency-free, returns a module). |
| `src/ui_spec.lua` | Framework specs, run against the in-memory buffer. |
| `src/todo.lua` | The todo app, written against `ui`. |
| `build.py` | Bundles `src/ui.lua` + an app into one runnable Lua file. |
| `todo.lua` | **Generated.** Self-contained app to drop on an OC computer. |
| `tests/ui_test.lua` | **Generated.** Framework spec bundle. |
| `tests/computer.yaml` | Non-interactive test machine config. |
| `computer.yaml` | Interactive dev config (60x30, boots into the app). |
| `problems.md` | Notes on the `ocplay` emulator. |

## Build and test

```sh
python3 build.py     # regenerate todo.lua and tests/ui_test.lua
./run-tests.sh       # build, then run the app self-test and ui specs
```

`run-tests.sh` uses [`ocplay`](https://github.com/MagicBOTAlex/OCPlayground).

## Running

- Dev: `ocplay --interactive ./computer.yaml` (boots straight into the app).
- In-game: copy `todo.lua` to the computer and run `todo`, or add
  `dofile("/home/todo.lua")` to `/home/.shrc`.

## Controls (in-game: pointer only)

- Click a task to open its details (or to complete it while in select mode).
- `[ Add ]` add a task, `[ Select ]` toggle checkboxes, `[ ] Completed`
  show/hide done tasks, `[ Quit ]` exit.
- Completed tasks are collapsed by default.
- There is no keyboard in-game, so row selection is disabled. Pass
  `keyboard = true` to `UI.new` (as `--self-test` does) to use the keyboard
  path during development.

## The `ui` framework

`src/ui.lua` is standalone and `return`s its module, so other projects can use
it directly. Build a view as a tree of plain-table nodes, then run:

```lua
local ui = require("ui")
ui.run({
  canvas = ui.canvas(component.gpu),
  view = function() return ui.column({ ui.text("hi"), ui.button("ok", { onClick = ... }) }) end,
  pull = function() return event.pull() end,
})
```

Nodes: `text`, `button`, `checkbox`, `spacer`, `column`, `row`, `list`.
Cells support `grow` to share leftover space. `ui.layout`, `ui.draw` and
`ui.dispatch` are exposed separately, and `ui.buffer(w, h)` renders to memory
for headless tests.
