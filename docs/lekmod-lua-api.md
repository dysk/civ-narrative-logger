# What the Lekmod Lua API exposes

Notes from reading the Lekmod DLL source, kept so the next question
about "can we log X" is answered from a file instead of from the C++
again. Companion to `lekmod-gameevents.md`, which covers the push side
(hooks); this covers the pull side (what a poller can read) and the
dead ends.

Source: local checkout of https://github.com/EnormousApplePie/Lekmod at
commit `62d32ba` (2026-08-13), directory
`LEKMOD_DLL/CvGameCoreDLL_Expansion2`. Bindings live in `Lua/CvLua*.cpp`
and register with a `Method(Name)` macro, so
`grep -aoE '^\s*Method\([A-Za-z0-9_]+\)'` over one of those files is the
authoritative list of what that class offers Lua.

Practical note for grepping: `Lua/CvLuaGame.cpp` and `Lua/CvLuaDeal.cpp`
are not UTF-8 (a copyright line in the header), so `grep` calls them
binary and prints nothing useful. Use `grep -a`, and `LC_ALL=C awk` for
range extraction.

## Surface, by class

| Class | Methods | The parts that matter to us |
|---|---:|---|
| `CvLuaPlayer` | 822 | everything empire-level: yields, stocks, research, policies, religion, culture/tourism, trade routes, espionage, city-state relations, resources, happiness breakdown |
| `CvLuaCity` | 388 | per-city state: population, yields, current production, damage, puppet/occupied/razing, religion, buildings, specialists |
| `CvLuaUnit` | 388 | per-unit state; we use almost none of it (unit events carry what we need) |
| `CvLuaGame` | 285 | game-global: turn, winner/victory, active league, turn timers |
| `CvLuaPlot` | 192 | tile state; improvements and ownership already reach us as events |
| `CvLuaTeam` | 143 | the pairwise diplomatic state: war, treaties, agreements, embassies |
| `CvLuaDeal` | 56 | full deal contents — but unreachable, see below |
| `CvLuaLeague` | 52 | World Congress, already consumed by `src/congress.lua` |

## Confirmed semantics worth remembering

Things whose names promise something other than what they do, checked
at the implementation rather than guessed from the name:

- **`Player:IsFriends(ePlayer)` is city-state friendship**, not a
  Declaration of Friendship — it calls `GetMinorCivAI()->IsFriends()`.
  The DoF between majors is `Player:IsDoF(ePlayer)`, with
  `GetDoFCounter`. Denouncement is `IsDenouncedPlayer` /
  `IsDenouncingPlayer` with `GetDenouncedPlayerCounter`.
- **`Player:GetResourceImport/GetResourceExport(eResource)` are totals,
  not per-partner.** They say a resource is flowing in or out, never
  with whom. Pairing one player's import against another's export on
  the same turn is an inference, not a reading.
- **`Player:GetActiveQuestForPlayer` is an alias** for
  `IsMinorCivActiveQuestForPlayer(ePlayer, eQuestType)` — a boolean per
  quest type, so reading quests means iterating `MinorCivQuestTypes`
  and pulling `GetQuestData1/2` and `GetQuestTurnsRemaining` for the
  ones that answer true.
- **`Player:GetTotalTimePlayed()` is broken and must not be used.** It
  returns `(timeGetTime() - m_uiStartTime)/1000` (`CvPlayer.cpp:20579`)
  and nothing in the DLL ever calls `setStartTime`, leaving
  `m_uiStartTime` at 0 — so it reports seconds since the *machine*
  booted, not time in the game. The member carries an `XXX save these?`
  comment from Firaxis (`CvPlayer.cpp:407`).
- **`Game.GetTurnTimeElapsed()` is milliseconds into the current turn**
  (`getTimeElapsed() * 1000`), fed by the turn timer and compiled under
  `TURN_TIMER_PAUSE_BUTTON`. Untested on a pitboss server.
  `Game.GetPitbossTurnTime()` is the *configured* hours per turn, not
  an elapsed figure (`CvGame.cpp:5131-5143`).
- **`Player:GetTradeRoutes()` returns rich rows**: `FromCityName`,
  `ToCityName`, `FromID`/`ToID`, `Domain`, and gold/food/production/
  science values for both ends (`CvLuaPlayer.cpp:lGetTradeRoutes`).
  `GetTradeRoutesToYou()` is the mirror. Enough to log routes without
  any hook.
- **`Player:GetEspionageSpies()` returns each spy** as `Name`, `Rank`
  (`TXT_KEY_SPY_RANK_*`), `State` (`TXT_KEY_SPY_STATE_*`), `CityX`/
  `CityY`, `TurnsLeft`, `PercentComplete`, `EstablishedSurveillance`,
  `IsDiplomat`. Ranks and states arrive as text keys, not integers.
- **Snapshot timing**: `PlayerDoTurn` fires at the very end of
  `CvPlayer::doTurn` (`CvPlayer.cpp:5065`) — after that player's growth
  and yields are applied, before they act. Everything polled from it is
  "start of turn N, before decisions". `GatherPerTurnReplayStats`
  (`CvPlayer.cpp:5435`) is the end-of-turn counterpart if we ever want
  before/after pairs.
- **`CvGame::testVictory()` fires `GameCoreTestVictory` before its own
  early return** (`CvGame.cpp:9933-9950`), so the hook still fires once
  the game is decided. It is called once per game turn from `doTurn`
  plus on player death, team change and a concluded Congress vote — a
  handful of firings per turn, cheap enough to poll `Game.GetWinner()`
  from. The call site comment says the hook exists "to allow a Lua
  script to set the victory state", so a handler there must return
  nothing.

## Hook argument orders that break the pattern

- `BuildingSold` (`CvBuildingClasses.cpp`) pushes
  `(ownerId, buildingType, cityId)` — type *before* city id, unlike
  `CityConstructed`'s `(owner, city, building, gold, faith)`.
- `UnitHealed` (`CvUnit.cpp`) pushes `(owner, unitId, change, x, y)` and
  fires from `ChangeDamage` when the change is negative, i.e. on
  healing.
- `PlayerHappinessChanged` pushes only the player id.

## Dead ends

Established as unreachable from Lua, so nobody re-derives them:

- **Deal contents.** `CvLuaDeal` exposes the full item list, but no API
  hands you a deal: it is only ever reached as a function argument
  (`CvLuaDeal::GetInstance`), and `CvLuaGame` offers only
  `GetPendingIncomingDealSenders` and `GetDealDuration`. Gold,
  gold-per-turn and city trades between players cannot be read
  directly; only their effects (Team treaty flags, resource import/
  export counts, the gold in the snapshot).
- **Individual Congress votes.** `GetMemberDetails` /
  `GetResolutionDetails` return localized tooltip strings, not
  structured data — unchanged from what `implemented-changes.md`
  recorded when the congress poller was written.
- **Razing a city fires no hook** (`CvCity::DoRazingTurn` →
  `CvPlayer::disband` contains no `CallHook`), which is why
  `src/census.lua` exists. Player elimination is the same shape:
  `CvPlayer::setAlive` calls no hook either.

## Hook list currency

Re-checked against this checkout: 65 `LuaSupport::CallHook` call sites,
52 distinct hook names, and every one of them already appears in
`lekmod-gameevents.md`. The remaining entries in that file are the
`Can*`/`Get*` query hooks (`CallTestAll`/`CallAccumulator`), which we
must never subscribe to. The file is current; no new hooks have
appeared since it was written.
