# Planned changes

Changes the logger still owes the downstream analyst
(`civ-strategy-analyst`). Implemented ones move to
`implemented-changes.md`.

## Report the outcome of one-shot resolutions, or admit it is unknown

### The problem

`diffResolved` decides whether a vanished proposal passed by asking
whether an active resolution now sits under its ID. That question only
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
`m_vActiveResolutions`, so the ID test answers "no" whatever the vote
did — and the logger writes `resolution_failed` for a resolution that
passed.

Classifying every resolution in LEKMOD 34.15 by the column list in
`CvResolutionEffects::HasOngoingEffects` (`CvVotingClasses.cpp:245`)
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
chose, so their outcome matters less than the three project ones.

This is a separate defect from the repeal inversion fixed in `8ed34c0`,
and that fix does not address it: for a one-shot enactment the branch
still lands on "no active resolution under this ID, therefore failed".

Confirmed in a throwaway test game on the current build: a World's Fair
that was enacted by the session was logged as

```json
{"event":"resolution_failed","resolution":"RESOLUTION_WORLD_FAIR","turn":187}
```

so the reasoning below no longer rests on the DLL source alone. That log
was neither kept nor imported, so it needs no repair.

### Known bad data

Any `resolution_failed` recorded for one of those five types, in any log
captured before this change, is unreliable — it may be a resolution that
passed. In the one log we hold it is `RESOLUTION_WORLD_FAIR`, proposed
turn 101 by Babylon, recorded failed on turn 117
(`examples/babylon-domination.jsonl` in the analyst repo, and the same
game imported on both machines). Nothing in the log distinguishes the two
cases; the signal was never captured.

### The signals that exist

`CvLuaLeague::PushMethods` (`CvLuaLeague.cpp:67-68`) exposes
`IsProjectActive` and `IsProjectComplete`, and `DoEnactResolution` calls
`StartProject` immediately on enactment, so an enacted project
resolution is observable on the next poll. `GameInfo.Resolutions` is
already reachable from the adapter (the game globals table in
`tools/build.lua` passes `GameInfo`), so the logger can read
`LeagueProjectEnabled` and the ongoing-effect columns itself and
reproduce the DLL's classification instead of hardcoding five IDs — the
mod can add resolutions, and a hardcoded list would silently rot.

There is no "results of the last session" API. `GetEnactProposals`,
`GetRepealProposals` and `GetActiveResolutions` are the whole surface,
which is why the outcome has to be inferred from state at all.

### Approach

1. **Adapter — classify resolutions and expose project state.**
   `civ.congressSnapshot()` gains `projects`, one entry per row of
   `GameInfo.LeagueProjects` (`{active, complete}`), and each proposal
   record gains `ongoing_effects` (computed from
   `GameInfo.Resolutions` using the same columns
   `HasOngoingEffects` tests) and `league_project`
   (`LeagueProjectEnabled`, or nil). Three projects and one boolean per
   proposal: the snapshot stays small.

2. **`diffResolved` — one decision table instead of one test.**
   - ongoing effects: unchanged, the active-resolution test, already
     correct for both enactments and repeals.
   - one-shot with a league project: passed iff that project is active
     or complete in the current snapshot and was not in the previous
     one.
   - one-shot without one: undetermined (see below).

3. **Say "undetermined" rather than guessing.** New event
   `resolution_undetermined`, carrying the resolution type and turn like
   its two siblings. Emitting nothing instead would be cheaper, but the
   analyst renders a missing outcome as "pending", which is a different
   and equally false claim about a vote that certainly concluded. The
   analyst side then needs the type in its known-event list, an
   `:undetermined` outcome in `CongressTimeline`, and a word for it in
   the Congress view and `KeyMomentsHelper`.

4. **Repair the known bad data** the same way the repeal inversion was
   repaired: rewrite `resolution_failed` to `resolution_undetermined`
   for the five one-shot types in both databases and in
   `examples/babylon-domination.jsonl`. Two of the five can be resolved
   by hand instead where the rest of the log settles it — a
   `congress_host_changed` in the same turn for `CHANGE_LEAGUE_HOST`, a
   game that kept running for `DIPLOMATIC_VICTORY`.

Steps 1–3 are test-first against fakes as usual; step 4 is a one-off
script.

### Verification

The suite cannot prove this one, because the fakes are our own model of
the API. Confirm in a real game: pass a World's Fair, then check the log
shows `resolution_passed` and not `resolution_failed`, and that a
`league_project`-derived decision fires on the poll after the session
rather than several turns later when the project completes. The
pre-change half of that experiment is already done and is what the
problem statement above quotes.
