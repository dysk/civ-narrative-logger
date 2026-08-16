# Planned changes

Changes the downstream analyst (`civ-strategy-analyst`) needs from the
logger. None of them blocks that project: where a fallback exists it is a
guess this repo could replace with a fact, and where none exists the
analyst simply does without that analysis. Ordered by how much guessing
they remove.

## Emit tourism and cultural influence in the snapshot

The snapshot carries culture per turn but nothing about tourism, so
cultural-victory progress is invisible: who pressures whom, how hard, and
how close anyone is to winning. The Lekmod DLL exposes the full BNW
culture API to Lua (`CvLuaPlayer.cpp`): `GetTourism()` (per-turn output),
`GetInfluenceOn(other)` / `GetLastTurnInfluenceOn(other)` (accumulated
influence, delta gives the rate), `GetInfluenceLevel(other)` (Exotic →
Dominant), `GetInfluenceTrend(other)`, `GetTurnsToInfluential(other)`,
and `GetNumCivsInfluentialOn()`.

Add to `civ.playerStats`: `tourism`, `civs_influential_on`, and an
`influence` list with one entry per living major opponent —
`{civ, points, level, trend}`. That is the one snapshot field that grows
with player count, but at 8–12 majors the record stays small.

Consumer fallback: none. Culture per turn says nothing about tourism
output or influence standings.

## Extend the snapshot with the Demographics screen's inputs

The in-game Demographics screen shows empire-wide figures players watch
as trend indicators, and the snapshot carries only some of their inputs.
The screen's own source (`LEKMOD/Lua/tmp/ui/Replays/Demographics.lua.ignore`
in the mod repo) gives the formula for every row, and each function it
calls is exposed to Lua: production and food are
`CalculateTotalYield(YieldTypes.YIELD_PRODUCTION / YIELD_FOOD)`, GNP is
`CalculateGrossGold()`, population-in-millions is `GetRealPopulation()`,
land is `GetNumPlots() * 10000`, and approval, literacy and army are
arithmetic over fields the snapshot already carries (`happiness`, `techs`,
`military_might`).

Add the four missing raw inputs to `civ.playerStats`: `production`,
`food`, `gross_gold` (the existing `gold_per_turn` is net), and `plots`.
The derived display figures stay on the consumer side — the raw values
are what an analysis wants anyway.

Consumer fallback: none for production, food and land — no event carries
them. Gross gold, approval and literacy are partially derivable, but only
by guessing at expenses and at the ruleset's total tech count.

## Emit World Congress state, so diplomacy stops being invisible

No GameEvents hook covers the World Congress: the only hooks
`CvVotingClasses.cpp` fires are LEKMOD's own multiplayer voting system —
which is what the existing `mp_vote` / `mp_proposal_result` events are
(remap/irr proposals among the human players), not the Congress. The
league itself must be polled: its API is fully exposed to Lua
(`CvLuaLeague.cpp`), reached via `Game.GetActiveLeague()`.

Once per turn (the same poll the city census needs), read:

- league identity: `GetName()`, `IsUnitedNations()`, `GetHostMember()`,
  `GetTurnsUntilSession()`, `GetTurnsUntilVictorySession()`
- per member: `CalculateStartingVotesForMember()` (total delegates) and
  `GetCoreVotesForMember()`
- `GetEnactProposals()` / `GetRepealProposals()` — tables of
  `{ID, Type, ProposerDecision, VoterDecision, ProposalPlayer}`, with
  `Type` resolvable through `GameInfo.Resolutions`
- `GetActiveResolutions()` — same shape minus `ProposalPlayer`
- diplomatic victory: `Game.GetVotesNeededForDiploVictory()` and
  `Game.IsUnitedNationsActive()`

Emit one `congress_snapshot` record per turn (host, delegates per civ,
votes needed for diplomatic victory) rather than duplicating the league
into every player's snapshot, and diff the polled state turn to turn into
events: `congress_founded`, `congress_host_changed`,
`resolution_proposed`, `resolution_passed` / `resolution_failed` /
`resolution_repealed`, `united_nations_formed`.

Limit: how each player voted on a Congress resolution is not exposed as
structured data — `GetMemberDetails()` and `GetResolutionDetails()`
return localized tooltip strings. Without DLL changes the log carries
proposals, proposers, delegate counts and outcomes, not individual votes.

Consumer fallback: none. The `mp_vote` events are unrelated to the
Congress, and no other event mentions it.

## Emit a city census, so razed cities stop haunting the data

The Lekmod DLL fires no hook for a city being destroyed: `CvCity::
DoRazingTurn` calls `CvPlayer::disband` (`CvPlayer.cpp:6778`), which
contains no `CallHook`, and none of the 49 hooks the DLL does fire covers
destruction. A razed city therefore stays in any reconstruction built
from `city_founded` / `city_captured` forever.

`PlayerDoTurn` already runs once per player per turn, and `Player:Cities()`,
`GetNumCities` and `GetCityByID` are all exposed to Lua. Keeping a census
between turns and emitting `city_destroyed` when a known city disappears
closes the gap without touching the DLL, and would also catch anything
else the hooks miss.

Consumer fallback: the per-turn `snapshot` carries `cities`, so the
analyst can tell that a city vanished, and when — but not which one.

## Emit the map dimensions in `session_started`

`Map.GetGridSize()` returns the width and height. Civ 5 maps wrap in X, so
without the width no consumer can measure the distance between two cities
correctly: in the one game logged so far, ignoring the wrap turns a
compact Iroquois empire (span 10 across the seam) into a sprawling one
(span 40).

Add `map_width` / `map_height` to `civ.gameSettings()` in
`src/adapter.lua`, alongside the existing `map_script` and `map_size`.

Consumer fallback: the easternmost plot any event mentions, plus one.
That is a lower bound, not the width — the analyst flags it as an
estimate.

## Emit the active mod's version in `session_started`

`Modding.GetActivatedMods()` returns the mod's ID and version. The
analyst injects LEKMOD ruleset reference data into its prompt and must
know which version's data to use; today the version is passed by hand on
the command line and is simply wrong if the operator misremembers.

Consumer fallback: a `--lekmod-version` flag at import time, which is
where the guessing happens.
