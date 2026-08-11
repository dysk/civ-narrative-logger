# civ-narrative-logger

A Civilization V addon that records game events from a long-running
multiplayer game as structured JSONL, so that afterwards:

- an LLM can turn the log into a game chronicle;
- a separate analysis project can mine it for winning strategies and
  pivotal decisions.

Runs as a fake-DLC modpack alongside [LEKMOD](https://github.com/EnormousApplePie/Lekmod),
with logging active only on the pitboss server (Linux/wine). A local
opt-in flag enables the same logging for single-player testing.

## Status

The pure Lua core is complete and tested: event extractors (18 record
types), JSON encoder, error-safe logger wiring, and the adapter that
isolates the Civ 5 API. Not yet built: the in-game entry point
(sink + opt-in gate), the fake-DLC packaging, and the server-side
Lua.log → events.jsonl parser.

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
| `tests/` | test suite + ~70-line harness (`tests/run.lua`) |
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
