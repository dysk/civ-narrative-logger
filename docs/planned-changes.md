# Planned changes

Changes the downstream analyst (`civ-strategy-analyst`) needs from the
logger. Each one has a working fallback on the consumer side, so none of
them blocks that project — but every fallback is a guess where this repo
could supply a fact. Ordered by how much guessing they remove.

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
