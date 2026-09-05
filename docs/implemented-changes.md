# Implemented changes

Changes made for the downstream analyst (`civ-strategy-analyst`), which
needed none of them to function: where a fallback existed it was a guess
this repo could replace with a fact, and where none existed the analyst
simply did without that analysis. Originally ordered by how much
guessing each removed; all of the below have since been implemented.

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

## Emit domination and space-race victory progress in the snapshot

The mod's own victory screen (`LEKMOD/Lua/tmp/ui/VotingSystem/
VictoryProgress.lua.ignore`) shows the recipe for both, and every call it
makes is exposed to Lua:

- domination: iterate a player's cities and count those where
  `IsOriginalMajorCapital()` is true, recording `GetOriginalOwner()` —
  original capitals of majors only, exactly what the victory checks care
  about (`CvLuaCity.cpp` exposes both).
- space race: `Team:GetProjectCount()` per project — 1 for
  `PROJECT_APOLLO_PROGRAM` once unlocked, then the four part counts
  (`PROJECT_SS_BOOSTER` needs 3, `_SS_COCKPIT`, `_SS_STASIS_CHAMBER`,
  `_SS_ENGINE` need 1 each). Parts count only once *added* to the
  spaceship at the capital, and no hook fires on adding (`CvUnit.cpp`
  kills the unit without a `CallHook`) — so this too is per-turn polling.

Add to `civ.playerStats`: `capitals` (list of original owners of major
capitals the player controls, own included) and `spaceship`
(`{apollo, booster, cockpit, stasis_chamber, engine}`). Both are
team-level facts repeated per player, which is fine — snapshots are
per-player and teams of one are the common case.

Consumer fallback: partial for domination — `city_captured` carries a
`capital` flag, so capital control is reconstructable from events, but
only by replaying every capture correctly. None for the space race:
`unit_trained` shows a part being *built*, but a built part can be lost
in transit — assembly is what wins, and no event carries it. Apollo and
Manhattan already arrive as `project_completed` (the `CityCreated` hook
covers city-built projects; spaceship parts are units, not projects,
until assembled).

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

## Report the outcome of one-shot resolutions, or admit it is unknown

`diffResolved` decided whether a vanished proposal passed by asking
whether an active resolution now sat under its ID. That question only
has an answer for resolutions with ongoing effects. `CvLeague::
DoEnactResolution` (`CvVotingClasses.cpp:6160`) reads:

```cpp
// Active Resolutions with only one-time effects immediately expire
if (resolution.HasOngoingEffects())
{
    m_vActiveResolutions.push_back(resolution);
}
```

A resolution whose effects are all one-time never joins
`m_vActiveResolutions`, so the ID test answered "no" whatever the vote
did — and the logger wrote `resolution_failed` for a resolution that
passed. Classifying every resolution in LEKMOD 34.15 by the column list
in `CvResolutionEffects::HasOngoingEffects` (`CvVotingClasses.cpp:245`)
gives five affected types out of seventeen:

| Resolution | Why it is one-shot | Recoverable signal |
|---|---|---|
| `RESOLUTION_WORLD_FAIR` | `LeagueProjectEnabled` only | project becomes active |
| `RESOLUTION_WORLD_GAMES` | `LeagueProjectEnabled` only | project becomes active |
| `RESOLUTION_INTERNATIONAL_SPACE_STATION` | `LeagueProjectEnabled` only | project becomes active |
| `RESOLUTION_CHANGE_LEAGUE_HOST` | `ChangeLeagueHost` only | host change, ambiguous |
| `RESOLUTION_DIPLOMATIC_VICTORY` | `DiplomaticVictory` only | the game ends |

The last two also carry `NoProposalByPlayer=true` — they are the
automatic proposals of a special session rather than anything a player
chose. This was a separate defect from the repeal inversion fixed in
`8ed34c0`, which did not address it.

The adapter now classifies resolutions from `GameInfo.Resolutions` using
the same columns `HasOngoingEffects` tests, rather than hardcoding five
IDs the mod is free to change, and `congressSnapshot()` carries one
`{active, complete}` entry per row of `GameInfo.LeagueProjects`.
`diffResolved` reads a decision table instead of a single test: a
resolution with ongoing effects keeps the active-resolution test; a
one-shot with a league project passed iff that project became active or
complete this poll; a one-shot without one is `resolution_undetermined`,
a new event saying the vote concluded with a result nothing can read.
Emitting nothing would have been cheaper, but the analyst renders a
missing outcome as "pending", which is a different and equally false
claim about a vote that certainly happened.

Both halves of the real-game experiment were run: the same save,
replayed on each build, reported the same World's Fair as
`resolution_failed` and then as `resolution_passed`, both on turn 187.
The identical turn settles the second question — the decision is taken
on the poll right after the session, not several turns later when the
project completes, so `IsProjectActive` answers true as soon as
`DoEnactResolution` has called `StartProject`. A rejected project
resolution was not replayed; that branch is the one the pre-change build
already exercised for every outcome.

Every `resolution_failed` recorded for one of the five types before this
change is unreliable. In the one game we hold it was Babylon's World's
Fair, proposed turn 101 and recorded failed on turn 117, in
`examples/babylon-domination.jsonl` and the same game imported on both
machines. The log cannot distinguish the two cases, but the player
remembers the vote carrying, so the record was corrected to
`resolution_passed` rather than left unknown.

Consumer fallback: none. A passed one-shot resolution left no trace in
any event the analyst received.

## Free buildings

`src/free_buildings.lua`, registered on `PlayerDoTurn` beside the other
pollers, emits `building_granted` for a building a city holds without
having built it, and one `free_buildings_ready` per session naming the
candidate set it will scan.

```json
{"all_buildings":412,"buildings":135,"classes":["BUILDINGCLASS_AQUEDUCT", ...],"event":"free_buildings_ready","turn":0}
{"building":"BUILDING_UNIVERSITY","city":"Babylon","civ":"Babylon","event":"building_granted","source":"diff","turn":74}
{"building":"BUILDING_WORKSHOP","city":"Akkad","civ":"Babylon","event":"building_granted","source":"new_city","turn":41}
```

`source` says how the poller knows: `diff` for a building that appeared
between two turns, `new_city` for one standing in a city we had never
seen that had just been founded. A city-state buyout looks like a
founding to the DLL and keeps its buildings, so it emits a burst of
`new_city` records that a reader should drop.

`civ.grantableBuildings` reads the six schema columns that name a granted
building plus the four policy counters whose building the DLL chooses,
and expands each to every version of its class; `civ.freeBuildings` asks
each city `GetNumFreeBuilding` for those candidates. The why, the cost
and the seeding rule are in `design-decisions.md`.

The counters were added after the first real game: Carthage's free
harbours came through on turn 1, the Tradition finisher's aqueducts did
not, because `NumCitiesFreeFoodBuilding` counts a building without ever
naming one. Legalism's culture buildings and Fine Arts' schools were the
same shape and are covered by the same change.

Consumer fallback: the analyst carries `EarlyGame::GRANTED_BY`, which
accepts Angkor Wat as evidence of the University it grants. That covers
logs recorded before this change - `examples/babylon-domination.jsonl`
among them - and stays until they are all replaced.

## Record tourism per city now that Lekmod makes it a yield

The snapshot has carried empire-wide `tourism` since the culture change
above, but nothing said which city produced it, so a cultural push read
as one number with no geography behind it. Until Lekmod v35.2 that was
the only reading available: tourism lived in `CvPlayerCulture` and the
per-city figure was reachable only through `GetCityCulture()` helpers
that the DLL never bound to Lua.

v35.2 defines `LEK_YIELD_TOURISM` and `STANDARDIZE_YIELDS`
(`LEKMOD_DLL/CvGameCoreDLL_Expansion2/_Defines.h:1137,1294`) and adds
`YIELD_TOURISM` to the `Yields` table as ID 7, appended after
`YIELD_GOLDEN_AGE_POINTS` rather than inserted, so no existing yield was
renumbered. A city now answers `GetYieldRateTimes100(YIELD_TOURISM)`
through the same generic path as every other yield
(`CvCity.cpp:12685`), including the tourism-only modifiers for the
Congress and International Games (`CvCity.cpp:12467,12472`).

So the change is one entry in `CITY_YIELDS` (`src/adapter.lua:314`):
`yield_tourism`, alongside the six that were already there. The loop and
the divide by 100 were already generic, which is also why a city that
produces no tourism reports `0` rather than omitting the field - the
analyst reads these as a per-turn series, and a missing field is a gap
in it, not a zero.

Empire-wide `tourism` in `playerStats` is unaffected and stays worth
keeping: `GetTourism()` now delegates to
`getYieldTimes100(YIELD_TOURISM) / 100`
(`CvCultureClasses.cpp:3036-3041`), so its scale is unchanged, and it
counts non-city sources that summing the cities would miss.

Consumer fallback: none. Empire tourism says nothing about where it
comes from, and the city that carries a cultural victory is exactly the
one an analyst wants named.

## Break each yield down into where it came from

The snapshot has carried one number per yield - `science`, `culture`,
`faith`, `tourism` - and nothing about their composition, so two civs on
48 science looked identical whether the science came from twenty cities
or from three cities and a religion. `yield_sources` names the parts:

```json
"yield_sources":{
  "science":{"cities":44.5,"city_states":2,"happiness":1.5,"gold":0.5,
             "research_agreements":1,"deficit":-1.5},
  "culture":{"cities":24,"happiness":2,"religion":3,"minor_civs":1},
  "faith":{"cities":7,"minor_civs":2,"religion":1},
  "tourism":{"cities":38,"traits":2,"religion":5}
}
```

### Two APIs answer this, and they disagree

v35.2 added a generic breakdown - `GetYieldFrom{Cities,OtherPlayers,
Happiness,Traits,Religion,MinorCivs}Times100` and
`GetYieldPenaltiesTimes100` - decomposing `CvPlayer::getYieldTimes100`
(`CvPlayer.cpp:22096`). It is tempting to read every yield through it.
That would be wrong for most of them: the game only runs that path for
culture (`CvPlayer.cpp:12450`, the `#else` under `STANDARDIZE_YIELDS`)
and tourism (`CvCultureClasses.cpp:3038`). Science and faith keep their
own older totals - `GetScienceTimes100` (`:22310`) and
`GetTotalFaithPerTurn` (`:14406`) - which `STANDARDIZE_YIELDS` does not
touch, so the generic getters compute a parallel figure for them that
nothing in the game uses.

Worse, the same words mean different things across the two. In the old
science path `OtherPlayers` is Scholasticism from city-states; in the
generic one it is research agreements, and city-states live under
`MinorCivs` instead. The generic `getYieldFromMinorCivsTimes100` also
falls through from `YIELD_SCIENCE` into `YIELD_CULTURE` for want of a
`break` (`CvPlayer.cpp:22219-22222`).

So science and faith are read through their own getters, which have been
exposed to Lua since v35 and were simply never used here; culture and
tourism through the generic ones. Gold is absent: it is not computed as
a yield at all but through `CvTreasury`, and would need its own reading.
Production and food have no empire-level sources beyond their cities.

### Religion takes an argument

`GetYieldFromReligionTimes100(yield, prevTotal)` is not a flat source.
Its founder-belief modifier applies to everything counted ahead of it as
well as to itself (`CvPlayer.cpp:22283-22290`), so the DLL hands it the
running subtotal, and the adapter sums the four sources before it to do
the same. Passing zero instead fails silently and understates every
religion-led empire, which is why a test pins the argument rather than
the answer.

### Reading the record

Sources that contribute nothing are omitted - most only ever apply to
one yield, and spelling out the rest as zeroes would multiply the size
of the record to say nothing.

The parts add up to the total the snapshot already carries, with three
exceptions worth knowing, all of them informative rather than defects.
Under a golden age the modifier applies only to the sources ahead of
`penalties` and `minor_civs` (`CvPlayer.cpp:22115-22125`), so the total
exceeds their sum; `golden_age_turns` in the same record says when.
During anarchy every total returns 0 while the sources do not;
`anarchy_turns` says when. And science clamps at zero (`max(iValue, 0)`)
while `deficit` keeps running negative, which is how deep a bankruptcy
runs rather than how much science was lost.

Consumer fallback: none. A single figure per yield cannot distinguish a
wide empire from a tall one running on beliefs, which is most of what
separates two strategies on the same score.

## Name what each city-state is before anyone allies with it

`session_started` carries a second roster beside `players`:

```json
"city_states":[
  {"civ":"Geneva","trait":"MINOR_TRAIT_CULTURED","x":30,"y":8,
   "personality":"MINOR_CIV_PERSONALITY_PACIFISTIC"},
  {"civ":"Sparta","trait":"MINOR_TRAIT_MILITARISTIC","x":12,"y":44,
   "personality":"MINOR_CIV_PERSONALITY_HOSTILE","unique_unit":"UNIT_HOPLITE"}
]
```

The log already names city-states 131 times in a single recorded game -
`city_state_friendship_changed`, `city_state_ally_changed`,
`city_state_alliance_changed` - and never said what any of them was.
`civ` is `GetCivilizationShortDescription`, the same string those three
events carry, so the roster joins to them directly.

### Personality is Lekmod's, and only the save has it

`Minor_Civ_Personalities` (`LEKMOD/Override/CIV5Units.xml:57`) is a
Lekmod table of ten personalities - FRIENDLY, NEUTRAL, HOSTILE,
IRRATIONAL (disabled), WEALTHY, IMPOVERISHED, PIRATE_REPUBLIC,
THEOCRATIC, PACIFISTIC, ISOLATIONIST - and it decides behaviour, not
flavour. HOSTILE sheds 150 influence a turn unprompted and accepts only
bully quests; FRIENDLY decays at 75% and pays 125% on quests; WEALTHY
adds a third to trade-route gold while making gold gifts buy a quarter
less influence. Other columns block tribute, quests, gifts and allied
war support outright.

`CvMinorCivAI::DoPickPersonality` draws it at random once per game
(`CvMinorCivAI.cpp:1991-2023`) and stores it in the save alone. Nothing
in the mod files reconstructs it afterwards, which is the whole argument
for recording it.

`GetMinorCivPersonalityType` answers with the type string rather than an
index (`CvLuaPlayer.cpp:6596`), and with the empty string on a build
without the table - read as absence, so a vanilla-personality game
simply has no such field.

Known limitation: ISOLATIONIST carries `TransformsAtEra = ERA_MODERN`,
so a personality is not fixed for the whole game. A roster written once
per session picks the change up at the next reload and not before. The
poller below is where a same-session change would be caught.

### The plot travels with the identity

City-states are placed at map generation, so no `city_founded` ever
fires for them and the log otherwise never says where they are - which
decides who can reach one at all. `GetCapitalCity` can answer nil; the
entry then carries no plot rather than a made-up one.

### What this deliberately leaves to a poller

The roster is what a city-state *is*. What it is *to each major* -
ally, influence and its trend, friendship level, pledges to protect,
and the active quests with their targets and remaining turns - changes
every turn and belongs to a per-turn poller, still to be written.

### Killing and liberating one need no new hook

`CityCaptureComplete` fires from `CvPlayer::acquireCity` for every
acquisition, not just conquest, pushing `bConquest` as an argument
(`CvPlayer.cpp:3586-3600`); liberation reaches it through
`DoLiberatePlayer` -> `acquireCity(pCity, false, true)`
(`CvPlayer.cpp:3998`). So both already land as `city_captured`: a
city-state dying is one with `old_owner` set to it and
`conquest: true`, a liberation one with `new_owner` set to it and
`conquest: false`. What was missing was never the event - it was
knowing that the name belonged to a city-state, which this roster
supplies.

No `player_eliminated` is emitted for a minor: `src/roster.lua` polls
living majors, and the capture record already carries the death.
