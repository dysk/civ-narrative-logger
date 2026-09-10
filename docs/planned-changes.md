# Planned changes

Changes the logger still owes the downstream analyst
(`civ-strategy-analyst`). Implemented ones move to
`implemented-changes.md`.

## Carry the Congress across a reload seam

### The problem

`congress.new` builds its state fresh — `{ turn = nil, snapshot = nil }`
(`src/congress.lua:103`) — so the first poll of a session has nothing to
diff against and skips the diff. Nothing carries the previous session's
snapshot across the seam, because nothing persists between sessions at
all: the census keeps its `known` table the same way
(`src/census.lua:17`).

The false founding that poll used to announce has been dropped
(`implemented-changes.md`). The skipped diff has not, and it is the
expensive half: it costs every event type `diff` produces, so a host
change, a repeal, a UN formation or a resolution decided across that
seam is never written, and a vote that concluded there stays "pending"
in the analyst forever — the same false claim `resolution_undetermined`
was added to avoid.

How much falls in the seam depends on how far the loaded save sits from
the last poll. When a session resumes the turn it saved on, the skipped
diff spans nothing and only the false founding is emitted. That is the
common case, and the reason this has stayed cheap so far.

The same log holds one symptom this reading does not explain: Babylon's
repeal of `RESOLUTION_WORLD_RELIGION`, proposed on turn 189, never gets
an outcome, though the log runs to turn 203 and the league is polled
through turn 200. The turn-190 seam does not account for it — the
proposal was already in flight when the session before it last polled
on 189. `congress_snapshot` carries only host, delegates and votes, so
the log cannot say what the proposals list held afterwards. Worth
settling while in this code, rather than assuming the same cause.

### Approach

The capture run shrank this. A resuming session rebuilds its baseline from `civ.congressSnapshot()`,
which reads the proposals list live from the league rather than from
the log, so a proposal still in flight across a seam is recovered for
free: in `espionage-test.jsonl` one resolution was proposed on turn 150,
crossed the turn-153 seam and still had its `resolution_passed` written
on 168, and another crossed three seams before failing on 181. The only
loss left is a vote that both starts and resolves inside one seam.

Closing that needs no new read path after all. The proposals, active
resolutions and project states are already in `snapshot` and are simply
not written out; putting them in `congress_snapshot` lets the analyst
reconstruct an outcome the poller could not see. A bigger record, but
an existing one.

### Verification

The fakes can drive it: a poll sequence interrupted by a fresh
`congress.new` over the same fake league is exactly the reload. What
they cannot check is whether a real reload resumes where the last poll
left off, so the seam's real width wants one replayed save.

## Let a counterspy leave a trace

### The problem

A spy posted to one of its owner's own cities runs counter-intelligence,
and `examples/india-diplo.jsonl` in the analyst repo contains **not one
record of one**. India garrisoned Delhi for the whole game and the log
says nothing about it.

That garrison is not a guess. `CvEspionageClasses.cpp:538-582` (under
`ESPIONAGE_SYSTEM_REWORK`, defined at `_Defines.h:1441`) resolves every
completed mission on a rank difference, and the two branches differ in
what they can produce:

```
with a counterspy:      >2 DETECTED   2|1 IDENTIFIED   0 SPOTTED   <0 KILLED
without a counterspy:   >3 UNDETECTED   3 DETECTED     2 IDENTIFIED
```

There is no `KILLED` branch without a counterspy. **Nine spies died in
Delhi** — England lost four there, Tibet three, the Netherlands and the
Iroquois one each — so a counterspy was sitting in Delhi. It is even
nameable: India created six spies, five of them appear in some city, and
the sixth is

```
{"civ":"India","event":"spy_created","spy":"TXT_KEY_SPY_NAME_INDIA_7","turn":94}
{"civ":"India","event":"spy_promoted","rank":"agent","spy":"...INDIA_7","turn":108}
{"civ":"India","event":"spy_promoted","rank":"special_agent","spy":"...INDIA_7","turn":109}
```

Three records in 90 turns, no city, ever. The promotions date it: the
DLL sets `bCounterSpyUpgrade` on `SPOTTED` and `KILLED` — the defender
is what levels up — and the first kill in the game is on turn 109.

From the UI there is nothing special about this posting: sending a spy
home is the same gesture as sending it to a rival or a city-state. The
data is there too — `CvLuaPlayer.cpp:11552` returns `CityX`/`CityY`
unconditionally for every spy in `m_aSpyList` and maps
`SPY_STATE_COUNTER_INTEL` like any other state. The loss is entirely in
`src/spies.lua`, and it is three separate defects that happen to
compound.

**1. Counter-intelligence can only ever produce one event, and it is the
one most often missed.** `GetPercentOfStateComplete` returns `-1` for
`SPY_STATE_COUNTER_INTEL` (`CvEspionageClasses.cpp:2503`), so `progress`
is nil for the whole posting, and `completed()` requires
`known.progress ~= nil and spy.progress ~= nil`. A counterspy therefore
never emits `spy_mission_completed` — correctly, it completes nothing —
which leaves `spy_moved` as the *only* record it can produce for the
rest of the game. Every other state has a second chance; this one does
not.

**2. `spy_moved` is missed often, and that is the defect that hurts.**
Of the 24 spies that ever appear in a city, **11 are first located by a
`spy_mission_completed`, not by a `spy_moved`** — their posting was
never written. It is not only initial postings, either:

```
{"event":"spy_created",           "spy":"...ENGLAND_6","turn":148}
{"event":"spy_mission_completed", "spy":"...ENGLAND_6","city":"Amsterdam","turn":152}
{"event":"spy_mission_completed", "spy":"...ENGLAND_6","city":"Osininka", "turn":168}
```

Amsterdam to Osininka with no `spy_moved` between them, so a
**re-posting** is lost too. The log carries ten `logger_error` records
and every one is `PlayerDoTurn (congress)` — the spy poller never
raised, so this is not a crash swallowing turns.

Two candidate causes worth instrumenting before choosing a fix, because
they want different fixes:

- `moved()` short-circuits on `spy.x ~= nil`. `MoveSpyTo` calls
  `ExtractSpyFromCity` before assigning the destination, so a poll can
  land on a spy with `CityX == -1`. That poll writes no event *and*
  overwrites `known` with a positionless record.
- `diffSpy` returns immediately when `known.state == "dead"`, emitting
  only `spy_revived`. A spy that revives and is posted before the next
  poll loses the posting outright. England revived three spies and
  Tibet three.

The instrumentation that settles it is small: log `row.CityX`,
`row.CityY` and `row.State` per poll for one spy across one
reassignment.

**3. `spy_killed` throws away a location it is holding.** `diffSpy`
writes `at(spy)` — the *dead* record — and the DLL calls
`ExtractSpyFromCity` before setting `SPY_STATE_DEAD`, so `CityX` is
already `-1`. **0 of 9 kills carry a city.** The previous poll's `known`
still holds it; `at(known)` is a one-word change that hands the analyst
the death site directly instead of making it infer one from the last
tenure, 4 to 13 turns stale.

The same one-word class of fix applies to `spy_created`, which carries
no location either (0 of 18). A spy first seen already posted loses that
posting permanently, whatever happens to defect 2.

**4. `spy_mission_completed` fires on missions that never happened, and
they outnumber the real ones.** `completed()` reads a fall in
`PercentComplete` as a finished mission. But progress also resets at a
**state transition**: `GetPercentOfStateComplete` computes
`amount * 100 / goal` for `TRAVELLING`, `SURVEILLANCE` and
`GATHERING_INTEL` alike (`CvEspionageClasses.cpp:2474-2487`), and each
new state starts that counter at zero. So surveillance completing and
intel-gathering beginning reads as a completed mission.

The arithmetic dates it exactly. `iSpyTurnsToTravel = 1` (`:23`) and
`GetInfluenceSurveillanceTime` returns **3**, or **1** when the spy's
owner is at `INFLUENCE_LEVEL_FAMILIAR` or better over the target
(`CvCultureClasses.cpp:2919`). So the false completion lands **4 turns
after the posting**, or 2 with a tourism lead — and in india-diplo the
first "completed mission" after a posting lands at **+3 or +4 in 14 of
18 postings**, while genuine repeats in the same city run 9 to 37 turns
apart for a tech steal and exactly 10 for a rigged election.

Anchoring every completion against the nearest preceding `spy_created`
or `spy_moved`:

| | count |
|---|---|
| state-transition artifacts | **23** |
| genuine completions | 21 |
| unclassifiable — no anchor survived defect 2 | 9 |

**23 of 53.** The damage is uneven and worst where volume is lowest:
India's 23 rigged elections survive as 18 real ones, because elections
land on a fixed ten-turn cycle that corroborates them, while England's
ten tech thefts reduce to two that can be confirmed, and the Netherlands,
Tibet and the Iroquois to none. The analyst's headline finding for this
feature is the per-civ mission split, and that split is currently mostly
artifact.

Rigging is damaged less for a readable reason: for `SPY_STATE_RIG_ELECTION`
progress comes from the global election clock
(`GetTurnsBetweenMinorCivElections`), not from the city's counter, so the
transition does not always produce a fall. The defect's footprint follows
the progress formula exactly, which is the strongest evidence that this
reading is right.

### Approach

Defects 1 and 3 are cheap and independent of the hard one:

- `spy_created` and `spy_killed` both take `at()` — `at(spies[key])` for
  the creation, `at(known)` for the death. This alone makes a garrison
  visible whenever the spy is first polled in place, and gives every
  kill a city.
- A counterspy still needs its posting written. If defect 2 proves hard
  to close, the fallback is to emit a `spy_moved` whenever `known.state`
  and `spy.state` differ and a city is present, not only on a coordinate
  change — a state transition into `counter_intel` is a posting even
  when the coordinates were already right.

Defect 4 is the one worth fixing first, because it corrupts a number the
analyst publishes. A fall in progress is only a completion when the
**state is unchanged**; `completed()` should require
`known.state == spy.state` alongside the fall. That is one clause, and it
turns the false positives into nothing rather than into a new event.

**And the transition it currently mislabels is worth logging on purpose.**
`spyRecord` already extracts `surveillance = row.EstablishedSurveillance`
(`src/adapter.lua:927`) from `HasEstablishedSurveillance`, and **no event
carries it** — neither `posting()` nor `completion()` mentions it. The
turn a spy's surveillance goes false → true is the turn its owner can
first see the city, which is exactly what the analyst is otherwise forced
to reconstruct from the DLL's constants. One event per posting, about 39
for a whole game. It is the cheapest record in this document and it
answers a question nothing else can.

Defect 2 wants the instrumentation above first. If the extraction poll
is the cause, `moved()` should compare against the last *positioned*
record rather than the immediately previous one; if the revival
early-return is the cause, `diffSpy` should fall through to the move
check after emitting `spy_revived`.

Worth doing in the same pass, since it is the other espionage event that
does not exist: **a coup has no record at all.**
`CvEspionageClasses.cpp:2110` — a spy in a city-state that already has an
ally can seize the alliance outright, swapping influence with the
previous ally on success, and on failure taking the owner's influence to
`-10` and dying. Neither outcome is a move or a completed mission, so
the poller writes nothing. A failure is already inside reach: it is a
spy going to `dead` while posted to a minor, which fix 3 makes
identifiable on its own. A success needs its own read, and
`CanStageCoup` plus a city-state ally check is the whole of it.

### Verification

The fakes cover the cheap half: a poll sequence over a spy that is
already in a city when first seen must produce a located `spy_created`,
and one that dies in place must produce a located `spy_killed`. A
counterspy fake — a spy in its owner's own city, `PercentComplete` at
`-1` for the whole posting — pins that it emits its posting and then
stays quiet, which is correct behaviour rather than silence.

Defect 4 has a fake that is barely more than a table: a spy whose state
walks `travelling → surveillance → gathering_intel` with progress
restarting at each step must produce **one** surveillance event and **no**
completion, and the same walk with the state held still and progress
falling must produce a completion. The regression to guard is the count,
not the shape — 53 logged completions in india-diplo should become about
30.

What the fakes cannot settle is defect 2, which needs one replayed save
with a spy reassigned between two cities and the per-poll `CityX`
written out beside the events.

### Status

Landed in `src/spies.lua`:

- **Defect 4.** `completed()` now requires `known.state == spy.state`
  alongside the fall in progress, so a state transition no longer reads
  as a finished mission.
- **The mislabelled transition.** A `spy_surveillance_established` event
  fires the turn `surveillance` goes false → true, carrying the city.
- **Defect 3.** `spy_killed` reads its location from `known`, the last
  live poll, instead of the emptied dead record.
- **`spy_created` location.** The creation now carries `at()`, so a spy
  first polled while already posted keeps that posting.
- **Defect 2, the revival half.** `diffSpy` no longer returns straight
  after `spy_revived`: if the revived spy already sits in a city it emits
  the `spy_moved` posting too, read from the spy alone since the dead
  record it is diffed against carries no position.
- **The counterspy's one event.** `spy_moved` now also fires on the
  transition into `counter_intel` with a city present, not only on a
  coordinate change, so a spy posted home to coordinates that did not
  move is still recorded. Fires once — a counterspy left in place stays
  quiet.

All six are confirmed against a live game in `docs/capture-protocol.md`:
fifteen postings, every surveillance event on posting + 4, zero false
completions, five located counterspy postings and a located kill.

Still owed:

- **Sessions.** The first poll of a session is only a baseline, so a spy
  created or posted inside a reload seam is never announced —
  Jerusalem's `GREECE_4` surfaces with a surveillance event and no prior
  record at all. Persisting `known` between sessions is the general fix
  and is shared with the other stateful pollers, but the spy half comes
  almost free now that the record carries `agent`: a rebaseline can emit
  a located `spy_created` for every spy it sees and let the analyst
  deduplicate on the agent id.
- **Defect 2, the extraction-poll half.** A `spy_moved` lost mid-`MoveSpyTo`
  when a poll lands on `CityX == -1`. Wants the per-poll `CityX`/`CityY`/
  `State` instrumentation above, from one replayed save with a spy
  reassigned between two cities, before a fix is chosen. Run B of the
  capture protocol: the instrumented build exists on branch
  `run-b-instrumentation`, the run has not been played.

Off this list: **a successful coup**. A *failed* one is identified by
the located `spy_killed` in a minor plus the stager's influence stepping
down by 10, both measured at Valletta on turn 181. A success turned out
to need nothing from the logger either — it swaps the stager's influence
with the former ally's and changes the alliance, and both are already
written. The detection is the analyst's, not this repo's.
