# ocplay problems / rough edges

Observed while building OCAdvancedTODO. Version: `ocplay 0.1.0`. Date: 2026-10-04.
Fixes applied directly in `../OCPlayground` (uncommitted at time of writing).

## 0. Ctrl+C did not force-quit; no host escape hatch  -- FIXED

In interactive mode Ctrl+C was forwarded to the guest as a key event, so a stuck
program could not be escaped. OpenOS itself uses Ctrl+Alt+C to interrupt programs.

- Fix: plain Ctrl+C is now a host-level force-quit (`InputEvent::Quit` in
  `src/term/mod.rs`, handled in `src/run.rs`). Ctrl+Alt+C is still delivered to
  the guest so OpenOS interrupts keep working.
- Verified: sending Ctrl+C exits after the configured `terminateDelay`; the new
  unit tests cover Ctrl+C, Ctrl+Alt+C, plain `c` and key-release.

## 1. `run.interactive: true` silently blocks a non-interactive run  -- FIXED

With `run.interactive: true`, a run with piped output (no TTY) dropped into the
shell and waited forever, rendering nothing.

- Fix: interactive is only enabled when stdout is a usable terminal (`isatty`
  and a non-zero size). Otherwise ocplay prints a warning to stderr and runs
  non-interactively. A zero-size terminal is also treated as non-usable
  (`Output::new` in `src/term/mod.rs`).
- Note: if the Lua program itself blocks (e.g. `event.pull` forever), a
  non-interactive fallback still can't auto-shutdown after it; the warning plus
  working Ctrl+C/SIGINT is the escape. Consider a default timeout if this bites.

## 2. `filesystems.path` is resolved against the CWD, not the config file  -- OPEN

Paths in `computer.yaml` are relative to the process working directory, not to the
`computer.yaml` location. Undocumented and easy to get wrong.

- Repro: a config at `tests/computer.yaml` using `path: .` mounted the project
  root (the CWD), not the `tests/` directory.
- Suggest: document the base directory, or resolve relative to the config.

## 3. Script errors are merged into the rendered screen buffer  -- OPEN

When the autorun script raises, the propagated error/traceback is written into the
screen and then the final frame is dumped as plain text, overlapping and truncating
the UI.

- Suggest: clear the screen first or print the error/traceback on its own line in
  the process output.

## 4. `--timeout` writes a host message into the captured output stream  -- OPEN

On timeout the host prints `ocplay: timed out after 6.0s` interleaved with the
final screen dump, with no separator.

- Suggest: route host diagnostics to stderr with a blank-line separator.

## 5. E2E automation has no built-in input injection  -- OPEN

No supported way to feed scripted keyboard/mouse events to a run; automated UI
tests must mock the input source inside the Lua program.

- Suggest: an option to replay a scripted event list, e.g. `--events events.jsonl`.

## Notes (not bugs)

- **Color trap (caused the real "black screen")**: OpenOS `require("colors")`
  returns palette *indices* (white = 0, black = 15), but `gpu.setForeground`/
  `setBackground` treat a bare number as a packed 24-bit RGB value unless you
  pass the optional `palette` flag. Using `colors.white` (0) therefore painted
  black-on-black. The todo app now uses explicit RGB constants. This matches real
  OpenComputers, so it is not an ocplay bug.
- Lua 5.3: `table.unpack` is correct here; `unpack` is absent.
- OpenOS `keyboard.keys` codes (up `0xC8`, down `0xD0`, enter `0x1C`, back
  `0x0E`, space `0x39`) matched what the emulator delivered.
