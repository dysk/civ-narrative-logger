# civ-narrative-logger

A Civilization V addon that records game events from a long-running
multiplayer game as structured JSONL, so that afterwards:

- an LLM can turn the log into a game chronicle;
- a separate analysis project can mine it for winning strategies and
  pivotal decisions.

There is no DLC of its own: the logger installs into the existing
[LEKMOD](https://github.com/EnormousApplePie/Lekmod) folder on the
machines that should log (the pitboss server, or a local machine for
single-player testing) and stays inert without a local opt-in flag.
Multiplayer clients install nothing. See `tools/README.md` for
install and enablement steps.

## Status

Complete and tested: event extractors (18 record types), JSON
encoder, error-safe logger wiring, the Civ 5 API adapter, the gated
entry point, the single-file build (`luajit tools/build.lua`, output
committed in `dist/`) and the LEKMOD install path. Not yet built: the
server-side Lua.log → events.jsonl parser, and the first in-game
smoke test.

## Running the tests

```
luajit tests/run.lua
```

That's the whole toolchain: LuaJIT implements Lua 5.1 (what Civ 5
embeds) and the test harness is dependency-free. On macOS:
`brew install luajit`.

The suite is pure — no game installation needed. Everything that
touches the real game API is behind `src/adapter.lua`, which receives
the game globals as a parameter and is tested against fakes.

## Layout

| Path | Purpose |
|---|---|
| `src/extractors.lua` | GameEvents hook args → narrative records |
| `src/adapter.lua` | the only seam to the Civ 5 Lua API |
| `src/logger.lua` | subscribes extractors to hooks, streams JSON to a sink |
| `src/json.lua` | minimal deterministic JSON encoder (sandbox has none) |
| `src/main.lua` | entry point: opt-in gate, CIVLOG| print-sink, wiring |
| `tests/` | test suite + ~70-line harness (`tests/run.lua`) |
| `tools/` | build script, LEKMOD installer, enable-flag file + install docs |
| `dist/` | the generated game-loadable file (committed; rebuild after src changes) |
| `docs/design-decisions.md` | every non-obvious choice and its why |
| `docs/lekmod-gameevents.md` | authoritative hook list, extracted from the Lekmod DLL source |

## Working on it

Read `docs/design-decisions.md` first — it explains the constraints
that shape the code (no file I/O in the sandbox, multiplayer desync
rules, why capture is unfiltered, the hook-vs-helper naming
convention). New hooks must be verified against the Lekmod DLL source
push order before an extractor is written, and never subscribe to
decision-query hooks (`Can*`/`Get*`).

Development is test-first: red tests get reviewed before
implementation.
