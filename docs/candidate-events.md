# Candidate facts

Facts the game exposes that the logger does not yet record, collected
before the first human multiplayer game so that capture is as wide as
it can be while the game is still ahead of us. Nothing here is required
by the analyst today; the argument for each is that the game is played
once and an unrecorded fact is gone.

Every API named below was checked against the Lekmod DLL source
(`LEKMOD_DLL/CvGameCoreDLL_Expansion2`, local checkout) — either at its
`Method(...)` registration in `Lua/CvLua*.cpp` or at its implementation.
Names that are not in that source are not proposed; what that reading
established about the API in general — confirmed semantics, surprising
argument orders, dead ends — is in `lekmod-lua-api.md`.

Two mechanisms already exist and everything below reuses one of them: a
hook extractor (`src/extractors.lua`, one hook → one record) or a
per-turn poller holding cross-turn state (`src/census.lua`,
`src/congress.lua`), diffing its snapshot into events. The congress
poller's turn gate is the pattern for anything game-global, since
`PlayerDoTurn` fires once per living player.

`PlayerDoTurn` fires at the end of `CvPlayer::doTurn`
(`CvPlayer.cpp:5065`) — after that player's growth and yields, before
they act. Every polled record is therefore "start of this player's turn
N", which is the right stamp for a decision-quality analysis: it is the
state the player looked at when deciding.

## Tier 1 — cheap, and lost forever if missed

### The game ending — implemented

Landed as `src/victory.lua` plus `civ.victory()`; see
`design-decisions.md`, "GameCoreTestVictory is a trigger, not an
argument list".

The log has no record of anybody winning. `Game.GetWinner()` (team),
`Game.GetVictory()` and `Game.GetWinningTurn()` are all exposed
(`CvLuaGame.cpp`), so the fact is one read away — the problem is timing:
when a victory fires the game stops, and `PlayerDoTurn` never comes
round again, so a per-turn poll misses exactly the turn it exists for.

`GameCoreTestVictory` is the trigger that does not miss it.
`docs/design-decisions.md` dismissed it as "pushes no arguments, there
is nothing to record" — true of its arguments, but as a *trigger* it is
precisely right: `CvGame::testVictory()` fires the hook before its own
`getVictory() != NO_VICTORY` early return (`CvGame.cpp:9933-9950`), so
it still fires after the game has been decided. It is called once per
game turn from `doTurn` plus on player death, team change and a
concluded Congress vote — a handful of times per turn, so a handler
that reads one integer and compares it to the last one is free.

Emit `game_ended` (winner civs, victory type, turn) once, on change.
The handler must return nothing: the DLL comment at the call site says
the hook exists "to allow a Lua script to set the victory state", and
`logger.attach`'s handlers already return nothing — worth keeping true
deliberately here rather than by accident.

### Players dying — implemented

Landed as `src/roster.lua` plus `civ.livingMajors()` and
`civ.capitalHolder()`.

`civ.playerStats` returns `nil` for a dead player (`src/adapter.lua`),
so a player's elimination shows up as the silent end of their snapshot
stream and nothing else. No hook covers it (`CvPlayer::setAlive` calls
none), so it is a roster poll, in the shape of the city census: keep
the set of living majors, and on a member disappearing emit
`player_eliminated` (turn, civ, and — from the same poll — who held
their original capital, `City:IsOriginalMajorCapital()` /
`GetOriginalOwner()`, already read for `capitals`).

### The diplomatic state between every pair — implemented

Landed as `src/diplomacy.lua` plus `civ.diplomacySnapshot()`, minus
research agreements and denouncement: neither can occur in a Lekmod
game between humans. See `design-decisions.md`, "The diplomacy poller
reads five facts, and the reasons for the rest".

The log records war (`DeclareWar`), peace (`MakePeace`) and first
contact (`TeamMeet`). Everything else two players can agree on is
invisible, which for a game between humans is most of the politics.
All of it is a pairwise read, per turn, diffed:

- team level (`CvLuaTeam.cpp`): `IsAtWar`, `GetNumTurnsAtWar`,
  `GetNumTurnsLockedIntoWar`, `IsForcePeace`,
  `IsAllowsOpenBordersToTeam`, `IsDefensivePact`,
  `IsHasResearchAgreement`, `IsHasTradeAgreement`, `HasEmbassyAtTeam`
- player level (`CvLuaPlayer.cpp`): `IsDoF`, `GetDoFCounter`,
  `IsDenouncedPlayer`, `GetDenouncedPlayerCounter`

Diff into `friendship_declared` / `friendship_ended`, `denounced`,
`open_borders_granted` / `_revoked`, `defensive_pact_signed` / `_ended`,
`research_agreement_signed`, `embassy_established`. At 8 majors that is
28 pairs of half a dozen booleans per turn — the diff is nearly always
empty, so the cost is reads, not records.

Note what stays out of reach: the deal itself. `CvDeal` is only
reachable from Lua as an argument (`CvLuaDeal` has no enumerating
entry point; `CvLuaGame` exposes only `GetPendingIncomingDealSenders`
and `GetDealDuration`), so gold, gold-per-turn and city trades are not
readable as deals. They are partly recoverable from their effects —
see resources below, and the snapshot's gold.

### Buildings sold — implemented

Landed as the `BuildingSold` extractor.

`BuildingSold` is a real notification hook we simply never subscribed
to. It pushes `(ownerId, buildingType, cityId)` — note the type comes
before the city id, unlike `CityConstructed` (`CvCityBuildings.cpp`,
under `LEKMOD_NEW_LUA_EVENTS`). One extractor, `building_sold`. Selling
a building is a cash-crisis tell and currently the log shows the
building still standing forever.

### Snapshot: the stocks behind the flows — implemented

Landed in `civ.playerStats`, resources filtered to strategic and
luxury entries the player has actually touched.

`civ.playerStats` records rates but not the balances the player is
actually deciding with — the delta between "10 faith per turn" and "480
faith banked" is the whole prophet/GP decision. All exposed on
`CvLuaPlayer.cpp`:

- `GetFaith()`, `GetJONSCulture()` (stocks; the snapshot has only the
  per-turn figures), `GetNextPolicyCost()`, `GetNumPolicies()`
- `GetCurrentResearch()` + `GetResearchTurnsLeft()` — what every civ is
  beelining, every turn. The single highest-value field on this list:
  `tech_researched` says what landed, never what was aimed at.
- `GetGoldenAgeTurns()`, `GetGoldenAgeProgressMeter()`,
  `GetGoldenAgeProgressThreshold()` — `golden_age_started` has no end
  and no progress
- `GetAnarchyNumTurns()`, `GetPublicOpinionType()`,
  `GetPublicOpinionUnhappiness()`, `GetPublicOpinionPreferredIdeology()`
  — ideological pressure, invisible today
- `GetGreatPeopleCreated()`, `GetGreatGeneralsCreated()`

Not `GetTotalTimePlayed()`, which looks like the per-player clock a
pitboss game wants and is not: it reports seconds since the machine
booted (see `lekmod-lua-api.md`). Real-time pacing has to come from the
log timestamps below.
- resources: `GetNumResourceTotal`, `GetNumResourceUsed`,
  `GetResourceImport`, `GetResourceExport` per resource. Imports and
  exports are the closest thing to a record of trade deals: a luxury
  appearing in one player's imports and another's exports on the same
  turn is a deal, even though the deal itself is unreadable.

These are all flat scalars on a record that already exists; the
resource lists are the only ones that grow (keep to non-zero entries).

### Wall-clock time, in the parser — implemented

Landed as `t_log` on every record; `tools/parser.lua` rewrites the
prefix instead of stripping it.

`tools/parser.lua` throws the `[1350613.044]` prefix away. It is the
engine's seconds clock, and it is the only real-time signal we have:
how long each turn took, when a session ran, which player stalls the
pitboss. Keeping it as one field (`t_log`) costs nothing at capture
time — it is a change to the parser alone, no game code, no risk — and
turn pacing in a pitboss game is a fact nobody can reconstruct later.

## Tier 2 — real volume, but the layer the analysis actually wants

### A city snapshot — implemented

Landed as `src/cities.lua` plus `civ.cityStats()`, per turn and
without a diff; see `design-decisions.md`, "The city snapshot keeps
no state and diffs nothing".

Cities are the unit of decision-making in Civ and the log describes
them only through the events that happen to them. `CvLuaCity.cpp`
exposes everything a per-city, per-turn record would want:
`GetPopulation`, `GetFood`, `GetFoodTurnsLeft`, `GetYieldRateTimes100`
per yield, `GetProductionUnit` / `GetProductionBuilding` /
`GetProductionProject` with `GetProductionTurnsLeft` (what this city is
building, right now — nothing in the log carries it),
`GetNumBuildings`, `GetSpecialistCount`, `IsPuppet`, `IsOccupied`,
`IsRazing`, `GetResistanceTurns`, `IsBlockaded`, `GetDamage`,
`GetStrengthValue`, `GetReligiousMajority`, `GetNumFollowers`,
`IsCapital`, `GetOriginalOwner`.

The census poller already walks every player's cities each turn, so
this is a wider record from a loop that exists. It is also the largest
addition here: 8 players × ~12 cities × 300 turns ≈ 29k records, an
order of magnitude over everything else in the log. Still small in
bytes, and city damage per turn is a siege that no event describes.

If volume needs cutting, emit on change rather than per turn — but
prefer the simple version first; "capture everything, filter
downstream" is the repo's standing decision.

### Trade routes

`Player:GetTradeRoutes()` returns, per route, origin and destination
city and owner plus the gold/food/production/science each side earns
(`CvLuaPlayer.cpp:lGetTradeRoutes`), and `GetTradeRoutesToYou()` the
mirror. Diff turn to turn into `trade_route_established` /
`trade_route_ended`. Today the log has one `trade_route_plundered`
event and no idea what was plundered or who lost it.

### City-state relations - the roster half implemented

The static half landed as `civ.cityStateRoster()`, carried by
`session_started`: trait, Lekmod personality, unique unit and plot. See
`implemented-changes.md`, "Name what each city-state is before anyone
allies with it". What follows is the per-turn half, still owed.

Hooks cover the transitions (`SetAlly`, `MinorFriendsChanged`,
`MinorAlliesChanged`) but not the standing state or its causes:
`GetAlly()`, `GetMinorCivFriendshipWithMajor()`,
`GetMinorCivFriendshipLevelWithMajor()`, `IsProtectedByMajor()`,
`GetMinorCivTrait()`, and the quests —
`IsMinorCivActiveQuestForPlayer(player, questType)` with
`GetQuestData1/2` and `GetQuestTurnsRemaining`. Who is being asked for
what, and who delivered, explains most city-state swings.

### Espionage

Entirely absent from the log. `Player:GetEspionageSpies()` returns each
spy's name, rank, state (`TXT_KEY_SPY_STATE_*`), city coordinates,
turns until the state completes and whether surveillance is
established; `GetEspionageCityStatus()` covers the other side.
A per-turn spy roster, diffed, gives spy moved / coup / tech steal
without a single hook.

## Tier 3 — considered and left out, with the reason

- `UnitSetXY`: fires on every tile of every move of every unit. Pure
  volume; the interesting derivative (armies massing on a border) is
  better served by a periodic military-unit census than by the firehose.
- A per-unit position census: real analytic value for pre-war reads,
  but ~50k records and questionable signal-to-noise. Worth revisiting
  after the first game shows whether the existing unit events suffice.
- `UnitHealed`: fires from `ChangeDamage` when damage decreases; a
  low-value derivative of combat we already record from both sides.
- `PlayerHappinessChanged`: still redundant — pushes only a player id,
  and the snapshot carries happiness. The unhappiness *breakdown*
  (`GetUnhappinessFromCityCount`, `...FromPublicOpinion`, etc.) would
  be new, but belongs in the snapshot, not on this hook.
- `GatherPerTurnReplayStats`: an end-of-turn twin of `PlayerDoTurn`
  (`CvPlayer.cpp:5435`). Only interesting if we ever want before/after
  pairs for the same turn; one poll point is enough today.
- UI-side `Events.*` (combat results, notifications): a UI context can
  subscribe, but these are the local machine's view and some are scoped
  to what the active player sees. On a pitboss server with no active
  human, whether they fire at all is unknown. Do not build on them
  without a smoke test.
- Individual Congress votes: still not exposed as structured data
  (`GetMemberDetails` returns localized tooltip strings) — unchanged
  since `docs/implemented-changes.md` recorded it.

## Order of work

Tier 1 is done. Every item in it was a fact that cannot be recovered
from a finished game - the ending, the deaths, the treaties, what
everyone was researching, and when each turn actually happened - and
all of them now land in the log before the first human game.

The city snapshot from Tier 2 landed with them, because production is
the one thing that shows a wonder race and the turn somebody lost it.
What remains in Tier 2 is trade routes, city-state relations with their
quests, and espionage: none of it harder than what is already here,
only bigger, and each of them leaves at least some indirect trace in a
finished log, which is why they waited. Tier 3 stays as written - the
reasons for leaving those out have not changed.

Before adding more volume, note that the analyst's import path is the
binding constraint now, not the logger: see `docs/import-volume.md` in
that repo.
