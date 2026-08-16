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

## No fake DLC of our own: piggyback on LEKMOD's InGame.lua

LEKMOD executes its gameplay Lua by overriding `InGame.lua` (generated
by its `ui_check.bat`) with `ContextPtr:LoadNewContext("<file>")` lines,
and its `.Civ5Pkg` already mounts the `Lua/` directory into the VFS.
We install by copying the built `CivNarrativeLogger.lua` there and
appending one `LoadNewContext` line - only on machines that should log.
Why not our own DLC: multiplayer requires identical DLC lists on every
machine, so a logger DLC would force all players to install it; and a
separate DLC would have to override some always-loaded UI file, racing
LEKMOD/EUI for it. A UI context that only reads state and prints is
local, so machines without it stay perfectly in sync. Costs: LEKMOD
updates/ui_check wipe the line (re-run install), and whether InGame.lua
loads under pitboss mode is a smoke-test question - if it does not, we
hook a context that does.

## The built dist/ file is committed

Windows test machines get no Lua toolchain; the generated
`dist/CivNarrativeLogger.lua` is committed so installing there is a
file copy. Rebuild with `luajit tools/build.lua` after changing src/.

## Hooks we deliberately do not subscribe to

Beyond the blanket rule against decision-query hooks, four eligible-
looking hooks stay out, checked against the Lekmod DLL call sites:

- `GetReligionToFound`, `GetReligionToSpread`,
  `GetFounderBenefitsReligion` - CallAccumulator queries; a
  handler's return value feeds the game's religion decisions.
- `GameCoreTestVictory` - a plain hook, but it pushes no arguments
  and fires every game-core update; there is nothing to record.
- `UnitGetSpecialExploreTarget` - fires inside the AI explorer's
  move selection loop; pure volume with no narrative content.
- `PlayerHappinessChanged` - safe but redundant: it pushes only the
  player id, and every per-turn snapshot already carries happiness.

## Stateful pollers register directly on GameEvents, bypassing logger.attach

The city census (`src/census.lua`) and World Congress poller
(`src/congress.lua`) both need cross-turn state and may emit zero or
more records per `PlayerDoTurn` firing - neither fits the extractors'
contract of one hook, one pure record. Rather than extend that
contract (and the purity guarantee of the other 44 extractors) to
support arrays and state, each is its own module holding its state in
a closure, wired with its own `g.GameEvents.PlayerDoTurn.Add(...)`
call in `main.lua`. GameEvents supports multiple listeners per hook
(that is the whole point of the system over the old override-style
Events), so this coexists with `logger.attach`'s own listener on the
same hook without conflict. The `GameEvents` test fake in
`tests/fakes.lua` models this as a list per hook name, not a single
overwritten slot.

The congress poller additionally gates `congress_snapshot` to once per
turn with a `civ.turn()` tracker, since `PlayerDoTurn` fires once per
living player but the league is turn-global, not per-player.
