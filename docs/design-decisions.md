# Design decisions

Decisions with a "why" that the code alone can't express. Newest at the bottom.

## Storage: print() to Lua.log, parsed externally

Civ 5's Lua sandbox has no `io`/`os` libraries, so mods cannot write files
directly. Events are printed as one JSON line per record with a `CIVLOG|`
prefix; an external script on the server tails `Logs/Lua.log` into a clean
`events.jsonl`. Requires `LoggingEnabled = 1` in the game's `config.ini`.
Fallback if log parsing ever proves flimsy: `Modding.OpenUserData` (SQLite).
JSONL was chosen because both consumers want it: LLMs read it directly for
the chronicle, and analysis tooling loads it trivially.

## Server-only logging is an opt-in gate, not host detection

GameEvents fire on every machine in multiplayer (the simulation is
synchronous everywhere; fog of war is UI-only). Logging is enabled by a
local flag only the pitboss server sets, rather than unreliable in-game
host detection. The same flag doubles as the single-player test mode.
Note the gate only prevents casual leaks - every client machine already
holds full game state; that is inherent to Civ 5 MP.

## Event list source of truth: the Lekmod DLL source

Our games run the Lekmod DLL, so the authoritative list of available hooks
is what that DLL invokes (see lekmod-gameevents.md), not the modiki wiki.
Never subscribe to decision-query hooks (`Can*`, `Get*` - TestAll/
Accumulator style): their return values feed back into game logic, so a
listener could alter gameplay or desync multiplayer.

## Capture everything, filter downstream

Extractors do not judge what is "interesting" (all buildings are logged,
not just wonders). Storage is cheap and the strategy-analysis project
needs the mundane decisions. Presentation-level filtering belongs in the
chronicle generator. An extractor may still return nil for "nothing to
log" (e.g. snapshot of a dead player) - that is a data decision, not a
taste decision.

## Resolve ids to names at capture time

Records carry display names ("Poland", "Warsaw") and DB Type strings
("TECH_POTTERY") instead of numeric ids. The log stays human/LLM-readable
without the game database at hand, and Lekmod's custom content gets its
proper names for free. Religions resolve through `Game.GetReligionName`
so player-renamed religions keep their in-game names.

## The adapter is the only seam to the game API

`src/adapter.lua` is the single place that touches `Game`/`Players`/`Map`/
`GameInfo`/`Teams`/`PreGame`/`GameDefines`, receiving them as an injected
table. Everything else is pure Lua tested against fakes. The adapter tests
double as documentation of the exact game API surface we depend on,
including quirks (Times100 rates, unit instance vs unit type ids,
team-held techs).

## Logging must never break the game

Extractor failures become `logger_error` records in the log instead of
raised errors. A crash inside a GameEvents handler could break or desync
the game; a lost record is always the lesser evil.

## Naming convention: extractor case decides hook vs helper

Every DLL hook name is UpperCamelCase (`CityCaptureComplete`), so the
extractors module uses lowerCamelCase for non-hook helpers
(`sessionStarted`) and `logger.attach` skips lowercase-named entries.
This lets the entry point pass the whole extractors module to `attach`
without accidentally subscribing helpers to hooks that never fire.

## session_started instead of game_started

The DLL exposes no reliable one-shot "game started" hook, so the identity
record (settings + player roster) is emitted every time the logger
attaches: new game, reload, pitboss restart, reconnect. The name is
honest about this; `turn` makes records distinguishable and deduping is
the parser's job. Handicap is per-player (MP allows mixed difficulties),
so it lives on the roster entries, not the settings.

## Records are flat, with `event` and `turn` on every record

Flat keys (no nested stats object) load straight into dataframes for the
analysis project. JSON object keys are emitted sorted so output is
deterministic and exact-string testable.

## Tests run on LuaJIT with a homegrown harness

LuaJIT implements Lua 5.1, matching Civ 5. The ~70-line harness avoids a
luarocks/busted dependency so the suite runs anywhere with a single
binary: `luajit tests/run.lua`.

## Known constraint: no require() in-game

Civ 5 mod Lua loads files via `include()` or as separate entry points;
`require` only works in our test environment. Packaging needs a build
step that concatenates `src/` into one addin file (or rewrites to
`include()`), while tests keep using modules.
