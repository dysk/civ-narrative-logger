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

Beyond the blanket rule against decision-query hooks, three eligible-
looking hooks stay out, checked against the Lekmod DLL call sites:

- `GetReligionToFound`, `GetReligionToSpread`,
  `GetFounderBenefitsReligion` - CallAccumulator queries; a
  handler's return value feeds the game's religion decisions.
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

## GameCoreTestVictory is a trigger, not an argument list

This hook was first dismissed for pushing no arguments, which reads the
wrong half of it: what makes it worth subscribing to is *when* it fires,
not what it carries. Nothing else can record the end of the game. The
per-turn pollers cannot, because the game stops on the turn it is
decided and the final `PlayerDoTurn` never arrives, so `Game.GetWinner`
would have to be read on a turn that never gets polled.
`CvGame::testVictory` fires this hook above its own
`if(getVictory() != NO_VICTORY) return;` guard (`CvGame.cpp:9943-9949`),
so it still fires once the game is over. It is called once per game turn
plus on player death, team change and a concluded Congress vote - a
handful of firings per turn for a handler that reads one integer, and
`src/victory.lua` keeps a one-shot flag so only the first decided read
is logged.

The DLL's own comment at that call site says the hook exists "to allow a
Lua script to set the victory state". Our handler therefore returns
nothing, deliberately and under test: a return value here would not just
pollute the log, it could decide the game.

## The diplomacy poller reads five facts, and the reasons for the rest

Only war and peace announce themselves (`DeclareWar`, `MakePeace`).
Everything else two players can agree on is state nobody pushes, so
`src/diplomacy.lua` reads it for every ordered pair of living majors
once per turn and diffs it. What it does *not* read matters as much:

- war and peace stay with their hooks; polling them would duplicate
  records that already exist.
- research agreements cannot happen in Lekmod. Every one of the 82
  technologies sets `ResearchAgreementTradingAllowed` to false
  (`LEKMOD/Override/CIV5Units.xml`), so `IsHasResearchAgreement` can
  never turn true and the read would be pure cost.
- denouncement is unreachable in an all-human game. Its only Lua entry
  point is `Player:DoForceDenounce` (`CvLuaPlayer.cpp:8733`), called
  from `DiscussionDialog.lua` - the AI leader screen. The human-to-human
  diplomacy screen has no such button. Add `IsDenouncedPlayer` back to
  `diplomacyPair` if a game ever includes AI majors; the poller's
  one-sided path already fits it.
- the counters (`GetNumTurnsAtWar`, `GetDoFCounter`, timers) are
  per-turn numbers, not events, and belong in a snapshot if they are
  ever wanted.

Which facts are mutual is a DLL question, not a modelling preference.
The DLL sets DoF on both players (`CvDiplomacyAI.cpp:11038-11039`), as
it does defensive pacts and trade agreements, so those are one fact
about a pair: they are diffed from the lower player id only and logged
with a `civs` array. Open borders and embassies belong to the side that
granted them and are logged per direction with `civ`/`other_civ`.

The first poll of a session records a baseline and emits nothing, the
way the city census does. Re-announcing every standing friendship on
each reload is exactly the defect `congress_founded` has, and this
poller would multiply it by every pair.

## The city snapshot keeps no state and diffs nothing

Cities are where the decisions happen, and until now the log described
them only through the events that befell them. Nothing carried what a
city was building - so a wonder race, and the turn somebody lost it and
switched production, was unreadable - nor how much damage it was taking
under siege, nor whether it could be governed at all.

`src/cities.lua` writes one `city_snapshot` per city per turn. Unlike
the other pollers it holds no state: there is no diff, no baseline and
no reload seam, because every city is written every turn. That follows
the repo's standing decision to capture everything and filter
downstream, and it is also the honest shape for the data - a city's
yields and production change continuously, so "emit on change" would
emit almost every turn anyway while costing a comparison per field.

It is the largest thing in the log by an order of magnitude: 8 players
× ~12 cities × 300 turns is around 29k records, against ~6k for a whole
game today. Two consequences are deliberate. City-states and barbarians
are skipped in `civ.cityStats` - `PlayerDoTurn` fires for them too, and
their cities would multiply the count for a fraction of the value. And
the analyst's import path needs work before it swallows a log this
size; that is written up in its own repo as `docs/import-volume.md`
rather than guessed at here.

## Free buildings are polled, because the DLL never announces them

A city can hold a building nobody built. Angkor Wat hands its city a
University, Hagia Sophia a Temple, Carthage's trait a Harbor in every
coastal city the moment it is founded, and a policy can do the same
across an empire. None of it reaches `CityConstructed`: the grant paths
end in `SetNumFreeBuilding` (`CvCity.cpp:486` for the trait loop, `525`
for the policy loop, `7391` for a wonder's `FreeBuildingThisCity`), and
the hook has three call sites, none of them on that road.

The cost was not theoretical. The analyst read Babylon's development
phase as closing on turn 77, on a University built in Akkad, three turns
after Angkor Wat had already put one in the capital.

`city:GetNumBuildings()` cannot gate the scan: `ChangeNumBuildings` is
reached from `SetNumRealBuilding` alone (`CvBuildingClasses.cpp:3542`),
so a free building never moves it. There is no cheap change signal, only
the per-building question.

Asking it of every building type would be ~500 questions per city per
turn. Instead `civ.grantableBuildings` derives, once, the buildings any
rule can grant, and asks only about those - a scan the same order of
magnitude as the field count `cities.lua` already reads per city. Turn
time on a pitboss server is the reason to keep it narrow; the full scan
is the fallback if the derivation ever gets too hard to trust.

Two families of rule have to be read, and the second one cost us a miss
before it was understood. The first names a building: `Buildings`
(`FreeBuildingThisCity`, `FreeBuilding`), `Traits` (`FreeBuilding`,
`FreeCapitalBuilding`, `FreeBuildingOnConquest`), `Policies`
(`FreeBuildingOnConquest`). Those six are the complete set of columns in
the info classes that point at a building.

The second only counts them, and the DLL picks: `CvPlayer::AwardFreeBuildings`
(`CvPlayer.cpp:8586-8666`) reads five counters off the adopted policies
and calls a chooser for each. `POLICY_TRADITION_FINISHER` carries
`NumCitiesFreeFoodBuilding=4`, and which building that is lives in
`CvCity::ChooseFreeFoodBuilding` - under `#define AQUEDUCT_FIX`
(`_Defines.h:1263`), the aqueduct class. Nothing in the schema says so,
so the first version of this poller watched Carthage's free harbours
correctly and missed every free aqueduct in the game.

`COUNTED_COLUMNS` mirrors the four choosers that matter:
`NumCitiesFreeFoodBuilding` to the aqueduct class,
`NumCitiesFreePietyGardens` to the garden class,
`NumCitiesFreeAestheticsSchools` to Scriptorium, Gallery and
Conservatory, and `NumCitiesFreeCultureBuilding` to every non-wonder
class with a culture yield, because `ChooseFreeCultureBuilding` weighs
culture against cost across all of them. `NumCitiesFreeWalls` is left
out deliberately: it hands over a *real* building (`CvPlayer.cpp:8631`),
which no scan of free buildings can see, and no Lekmod policy uses it.

"Non-wonder" has to answer all three caps. Civ 5 limits a wonder per
world, per team or per player, and reading only the first and the last
made Oxford University - Lekmod's one per-team building class - look
ordinary: it yields culture, so it joined the candidates, while
`ChooseFreeCultureBuilding` can never pick it
(`LEKMOD_NO_FREE_TEAM_WONDERS`, `CvCity.cpp:11331`). The same reading
fills the `wonder` field of `building_constructed`, where the cost was
larger - every Oxford was logged as a plain building.

The set is expanded by class rather than resolved per player. A column
may name a class or one civ's version of it, and the grant resolves to
the owner's version (`CvCity.cpp:7391`), so every version of a grantable
class is a candidate and no per-player resolution is needed. Resolving
per player would also be wrong the other way round for anyone reading
this later expecting captured cities to keep foreign uniques - they do
not: `CvPlayer::acquireCity` rebuilds surviving buildings as the new
owner's version of their class (`CvPlayer.cpp:3103`), world wonders
excepted.

The derivation is the one place this couples to the schema, so the
poller announces it: one `free_buildings_ready` per session carrying the
candidate count and the classes covered. A grant path we failed to
enumerate shows up as a short list in the log rather than as a wrong
conclusion months later.

Seeding follows the census, with one exception. The first poll of a
player records a baseline silently, or a reload would date every free
building in the empire to the turn of the reload - the same defect that
made this poller necessary. But that is only right past turn 1: at the
start of a game nothing has been granted yet, so there is nothing to
seed and everything to report, and a capital founded before the first
`PlayerDoTurn` would otherwise be swallowed.

A third family of rule needed a different answer entirely. Lekmod hands
out some buildings from its own Lua: `POLICY_RESETTLEMENT` gives a newly
founded city a Workshop, Granary, Aqueduct, Monument and Library through
`SetNumRealBuildingClass` (`LEKMOD/Lua/Lekmod_policies.lua:4-21`). Those
are *real* buildings, so `GetNumFreeBuilding` reads zero, and the Lua
setter is nowhere near the three `CityConstructed` call sites. No scan of
free buildings can ever see them.

What can see them is the city's own age. A city founded since the last
poll was built by nobody, so everything standing in it was handed over -
whatever the mechanism, DLL or mod script, free or real. That city gets
one scan of every building the ruleset defines, which is affordable
precisely because it happens once per city rather than once per turn.
Telling a founded city from a captured one is the DLL's own bookkeeping:
a captured city keeps the founding turn of whoever founded it
(`CvPlayer.cpp:2851`) while its acquired turn moves, so the two agreeing
means this player founded it.

One case defeats that test, and the record says so rather than guessing.
Buying out a city-state is deliberately dressed up as a founding
(`CvPlayer.cpp:2836-2843`: previous owner cleared, original owner set to
the buyer, founding turn set to now) while the city keeps everything it
had. Every grant therefore carries `source`: `new_city` for "this stood
in a city we had never seen, which had just been founded", `diff` for
"this appeared between two turns". A buyout produces a burst of
`new_city` records that a reader can recognise and drop, which is the
repo's standing trade - capture everything, filter downstream.

Two consequences to know downstream. A grant made while a player acts
lands in the log on the following turn, because `PlayerDoTurn` for that
turn has already fired - a city founded on turn 40 reports its free
Harbor on turn 41. And city ids come from a free list, so an entry is
matched on id *and* name; a recycled id otherwise hides the new city's
grants behind the old city's state.

## Elimination is polled, and the parser keeps the log's own clock

Two facts closed the first tier, and neither is pushed by the game.

`CvPlayer::setAlive` calls no hook, and a dead player takes no turn, so
an elimination has never appeared in the log at all: `civ.playerStats`
simply starts returning nil and that civ's snapshots stop. `src/roster.lua`
polls the living majors once per turn and reports whoever left the list,
with `capital_held_by` - the original capital outlives its owner, so the
question can still be asked after the fact, and the answer separates a
conquest from a collapse. Like the diplomacy poller it takes the first
poll of a session as a baseline, so a reload does not report everyone
who fell before it.

The parser used to throw the `[1350613.044]` prefix away. Nothing in
the game exposes real time to Lua - `Player:GetTotalTimePlayed` reports
seconds since the machine booted (`lekmod-lua-api.md`) - so that prefix
is the only record of how long a turn took and when a session ran,
which on a pitboss is the difference between "the game was slow" and
"one player sat on their turn for two days". It is now kept as `t_log`,
written in front of the payload's own keys: the parser has no JSON
decoder, and the stamp is a fact about the log line rather than about
the game. The raw text goes through unconverted, since a float
round-trip only risks losing digits it cannot gain.
