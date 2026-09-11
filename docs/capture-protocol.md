# Capture protocol

What has to happen in a live game, with the current
`dist/CivNarrativeLogger.lua` installed, to move the open items in
`planned-changes.md`. Three runs, each answering a different question.
Run A validates what already landed and unblocks the analyst; runs B and
C settle the fixes that are still owed. **All three have now been
played** — what each one settled is at the end of this file.

The bundle to install is the one at `b51a639` — Defect 3, Defect 4,
`spy_created` location, `spy_surveillance_established`, the revival
fall-through and the counterspy `spy_moved` are all in it. Run B needs a
code change on top; see its step 0.

---

## Run A — full validation playthrough

One normal game, played to a war or a late peace, with espionage used
deliberately. Every landed fix has a path here that no existing log
exercises: `india-diplo.jsonl` predates all of them.

### What has to happen in the game

Play these into one game in roughly this order. Turn numbers are
relative to each posting.

1. **First spy.** Reach the tech that grants it, or build the wonder.
   Note the turn — this is the first `spy_created`. If the spy is
   granted while you already hold a city it could sit in, so much the
   better: it may be first polled already posted.

2. **Post spy 1 to a rival capital.** The turn you issue the order,
   then end it. Expect, across the next four polls:
   - `spy_moved` with the posting on the arrival turn,
   - `spy_surveillance_established` carrying that city 1–3 turns later
     (1 turn if you have Familiar+ influence over the target, else 3),
   - **no `spy_mission_completed`** in that window. The spy walks
     `travelling → surveillance → gathering_intel` and the progress
     counter restarts at each step; the Defect 4 fix has to hold here,
     in the wild — one surveillance event, zero false completions.

3. **Let spy 1 finish a real mission.** Steal a tech or gather intel to
   completion. Expect one `spy_mission_completed` with the city, at a
   point where the state did not change and progress genuinely fell.

4. **Post spy 2 to a city-state and rig its elections.** Same
   surveillance event on arrival. Then leave it there through **two**
   election cycles (~10 turns each) to get two genuine repeat
   `spy_mission_completed` records in one city — the pattern that has to
   stay distinguishable from a state-transition artifact.

5. **Make a counterspy.** Post spy 3 to one of *your own* cities.
   Expect **exactly one** `spy_moved` — the `counter_intel` transition
   with the city present — and then **silence for the rest of the
   game**: no surveillance event, no completion. Leave it in place 15+
   turns to prove "fires once".

6. **Get one of your spies killed while posted.** The controllable
   route: stage a coup in a city-state that already has an ally, with
   enough influence to have the option, and lose the roll. Save first
   and retry until it fails. Expect `spy_killed` **carrying the
   city-state name** — read from the last live poll, since the dead
   record is emptied.

7. **Revive and re-post that spy.** Wait out the revival cooldown —
   expect `spy_revived`. Then post the revived spy to a city on the
   same or the next turn. Expect `spy_revived` followed by the
   `spy_moved` posting, read from the spy alone. If the spy is shown
   back in your capital the moment it revives, the fall-through should
   already emit that posting without a move order.

8. **Promotions** need no action — note that `spy_promoted` records
   appear for spies that survive missions.

### Save / reload point

This run doubles as the session-seam test. Pick a turn where **spy 4 is
mid-travel to a new posting** — order issued turn S, arrival S+1:

1. On turn S, issue the move order. Do **not** end the turn.
2. Quit to the main menu. Reload the save.
3. End turn S. Advance to S+3.

After the reload, check:

- Does `spy_moved` for spy 4's posting appear at all, or does the spy
  just turn up with surveillance already established, the posting having
  fallen in the seam (the first poll of a session only sets a baseline)?
- Every spy already posted at reload should produce a **located**
  `spy_created` on the first post-reload poll. Confirm the city is
  populated — that is the `spy_created` location fix, and it is also the
  shape the seam produces for a posting made just before it.

### After the run

- Import the log into the analyst. The event-reading paths in the
  `Espionage` projection (once built) finally have real input:
  `spy_surveillance_established`, located `spy_created` / `spy_killed`,
  `spy_moved` after a revival, `spy_moved` on `counter_intel`.
- Sanity-check the completion count against the old ratio: india-diplo
  logged 53 completions where ~30 were real. A comparable game should
  now log close to the real number.
- Whatever the reload seam swallowed becomes the concrete case for the
  "Sessions" item in `planned-changes.md`.

---

## Run B — instrumented spy reassignment (played)

Settles Defect 2's extraction-poll half: a `spy_moved` lost mid
`MoveSpyTo` when a poll lands on a spy with `CityX == -1`. The fakes
cannot reach this; it needs per-poll DLL values from a real move.

### Step 0 — the instrumented build (done)

**Branch `run-b-instrumentation`, commit `9768f63`.** Install with
`tools/install.sh <LEKMOD folder>` from that branch, and switch back to
`main` and reinstall afterwards — the branch is throwaway and is not for
merging.

It writes one `logger_debug` line per spy per poll, through an opt-in
sink `main.lua` supplies, so the suite still asserts the real record
sequences and stays green (309 tests, 0 failures). The branch sits on
top of the three fixes that landed after the first capture run — the
spy `agent` id, the guarded proposer and the dropped
`congress_founded` — so this run exercises them in the wild as well.

It needs less than this section originally asked for. `spyRecord` fills
`x`/`y` only when `row.CityX >= 0` (`src/adapter.lua:928`), so **a line
with no `x` is the DLL answering `CityX == -1`** and no raw read is
needed; the whole change lives in `src/spies.lua`. The line also carries
the `playerIndex:AgentID` key as `agent`, which is stable across a death
and is the only place in any log where it appears until *"A stable spy
identity"* lands.

**The game truncates `Lua.log` on every launch, and this run reloads.**
Start `tools/watch.sh` before the game and leave it running, or copy
`Lua.log` out before the reload — otherwise the first half is lost.

### The game

1. Play to a single spy. Post it to city X. Let surveillance establish
   and the spy settle into `gathering_intel`.
2. **Save** — call it save-R.
3. Issue a move order to city Y. End the turn. Advance 3–4 turns, one
   poll each.
4. Reload save-R. Issue the **same** order. Advance again. Two identical
   runs rule out a one-off.

### What to read out

Filter `logger_debug` for the spy, keyed on `agent` rather than the
name, and find the poll(s) with **no `x`** — the spy extracted from X
but not yet assigned to Y. Then check:

- Does that poll emit **no** `spy_moved` (expected — `moved()`
  short-circuits on `spy.x ~= nil`)?
- Does the **arrival at Y** also emit no `spy_moved`, because `known`
  was overwritten with the positionless record and `moved()` now
  compares Y against nil?

If both hold, the fix is to have `moved()` compare against the last
*positioned* `known`, not the immediately previous one. If the arrival
at Y *does* emit `spy_moved`, the extraction poll is harmless and the
lost postings in india-diplo were all the revival early-return, which is
already fixed — in which case this item closes with no further change.

---

## Run C — congress reload seam

Settles the `WORLD_RELIGION` question in `planned-changes.md`: does a
resolution that concludes across a session boundary lose its outcome, or
only its founding announcement?

Can be folded into Run A's game if a League is active there; otherwise a
short dedicated game with the World Congress founded.

### The game

1. With a Congress active, get a resolution **proposed on turn P** —
   propose it yourself, or note an AI proposal once it shows in
   `congress_snapshot`.
2. Play so the session's **last poll is on turn P** (or later, but
   before the vote resolves). **Save.**
3. Quit to the menu. Reload on turn **P + k**, where k is far enough
   that the vote has already been decided.
4. Advance a few turns.

### What to check

- Is the resolution's outcome event present in the log, or did it vanish
  — the diff for turns P+1..P+k never ran because the first poll of the
  new session only rebaselined?
- Count `congress_founded` records: one per `session_started`? Every one
  after the first is false.

### After

- If the outcome vanished: the hard half of the congress fix is real —
  `congress_snapshot` has to carry proposals and resolution states so a
  resuming session rebuilds its baseline. That is a bigger record and a
  new read path.
- If only the founding repeated: drop the `congress_founded` event and
  let the first `congress_snapshot` mark the league's arrival. The
  analyst reads `congress_founded` nowhere else.

---

# What the runs settled

Run A and run C were played into one game — `examples/espionage-test.jsonl`
in the analyst repo, Arabia, quick speed, turns 82–189, five sessions.
Run B was played separately from the instrumented build —
`examples/run-b-test.jsonl`, Polynesia, turns 122–140, two sessions.

## Run A — every landed fix holds

**Surveillance is exact, and the constant is 4.** Fifteen postings in the
log reach `spy_surveillance_established`, and every one of them lands on
**posting + 4** — `iSpyTurnsToTravel` 1 plus `GetInfluenceSurveillanceTime`
3, with no exceptions and no spread. Nobody held Familiar+ influence over
a target, so the 1-turn branch stays unexercised; the 3-turn branch is now
measured rather than derived.

**Defect 4 is closed in the wild.** Zero completions land on a
surveillance turn, and zero land within four turns of a posting. The
whole class of false positive is gone, not reduced. The count fell as
predicted too: 24 completions over 107 turns of espionage, against
india-diplo's 53 of which ~30 were real.

**The genuine repeat pattern survived the fix.** Arabia's spy rigged
Reykjavik on turns 151, 161, 171 and 181 — four cycles, exactly ten turns
apart, all four written. Jerusalem's spy in Mecca produced eight intel
completions with gaps of 4–9. Neither is confusable with the transition
artifact any more, because the artifact no longer exists.

**A counterspy leaves its trace.** Five `spy_moved` records carry
`counter_intel`, each in one of its owner's own cities, and none of them
is followed by a surveillance event or a completion. The transition lands
**one** turn after the posting, not four — a counterspy needs no
surveillance — which gives the analyst a second, independent way to tell a
garrison from an attack.

The one that fires more than once is honest: the Sioux oscillated a single
spy between Ihankthunwanna and Isanyathi four times in ten turns, and each
leg is a real posting.

**The coup is visible after all, and the influence penalty is −10.**
Arabia posted a spy to Valletta on turn 177 and it died on 181 with no
counterspy anywhere near it. Arabia's influence at Valletta, absent from
the turn-178 snapshot, reads −8 at turn 182 with `per_turn` +1.25 — that
is −10 on the turn of the kill, recovering. No `city_state_ally_changed`.
A failed coup is therefore already identifiable from events that exist:
a located `spy_killed` in a minor, plus a ~−10 step in the stager's
influence. Only a *successful* coup still needs its own read.

**Located `spy_created` and `spy_killed` both work.** Five creations carry
a city; the kill at Valletta carries the city-state read from the last
live poll.

## Run A — two defects the run exposed

### A revived spy comes back under a different name

Arabia's `ARABIA_0` died at Valletta on turn 181. On turn 186 the log
says `spy_revived` for **`ARABIA_8`** — a name that appears nowhere
before. The poller is right: it keys on `playerIndex:AgentID`
(`src/adapter.lua:950`), which is stable, and correctly diffs the same
slot from `dead` to alive. But the record carries `spy = row.Name`
(`:920`), and the DLL draws a fresh name on revival.

This is not a one-off. In india-diplo **all eight** revivals name a spy
that was never created — `ENGLAND_0`, `ENGLAND_1`, `ENGLAND_4`,
`CHINA_0`, `CHINA_5`, `CHINA_9`, `IROQUOIS_6`, `NETHERLANDS_2`. That is
the whole of the analyst's "spies it could never locate": they are
revivals of spies it knew under other names.

Downstream, `(civ, name)` is not an identity. A death orphans a tenure
and the revival invents a spy from nothing, and two live spies of one civ
can in principle collide on a recycled name. The fix is one field: put
`AgentID` in the record and let `spy` stay the display name.

Fixing this also makes the session seam almost free. The first poll of a
session is silent by design, so a spy created or posted inside the seam is
never announced — Jerusalem's `GREECE_4` surfaces at turn 186 with a
surveillance event and no prior record at all. With a stable id in the
payload, the rebaseline can simply emit a located `spy_created` for
every spy it sees and let the analyst deduplicate.

### A proposal with no proposer crashes the congress poll

```
{"event":"logger_error","hook":"PlayerDoTurn (congress)",
 "error":"...CivNarrativeLogger.lua:70: attempt to index field '?' (a nil value)"}
```

Line 70 is `civ.civName`, reached from
`proposer = civ.civName(p.ProposalPlayer)` in `proposalRecord`
(`src/adapter.lua:1044`). `GetHostMember` is already guarded with
`host >= 0` two lines below; `ProposalPlayer` is not, and a proposal with
no player behind it indexes `g.Players[-1]`.

It cost the whole turn-165 poll — the snapshot and any diff — which is
why `congress_snapshot` skips from 164 to 166. Same guard as the host.

## Run C — the seam keeps outcomes, and only the founding is false

**`congress_founded` fires once per session: five sessions, five
foundings.** The league was founded once, on turn 149. Turns 154, 174,
178 and 182 are false. Confirmed exactly as predicted — drop the event
and let the first `congress_snapshot` mark the arrival.

**The outcome does not vanish.** `RESOLUTION_NATURAL_HERITAGE_SITES` was
proposed on turn 150, the session broke at 153, and the resolution passed
on 168 with `resolution_passed` written. `RESOLUTION_WORLD_RELIGION` was
proposed on 169 and survived **three** seams before failing on 181, also
written.

The reason is worth recording, because it makes the hard half of the
congress fix much cheaper than it looked. `congress.new` rebuilds its
baseline from `civ.congressSnapshot()`, which reads the proposals list
**live from the league**, not from the log. A pending proposal is
therefore recovered for free across any seam. The only thing a seam can
still swallow is a vote that both starts and resolves inside it — and
nothing in this game did.

So `congress_snapshot` does not need "a bigger record and a new read
path". The proposals and active resolutions are already in `snapshot`
and are simply not written out. Adding them to the record closes the
remaining hole and lets the analyst compute an outcome itself, with no
new DLL read at all.

The unexplained babylon-domination symptom — a repeal proposed on turn
189 that never gets an outcome, with no seam to blame — is untouched by
this run and stays open.

## Run B — the extraction poll never happens, and could not hurt if it did

Played from branch `run-b-instrumentation` into
`examples/run-b-test.jsonl` in the analyst repo: Polynesia, turns
122–140, two sessions, 23 polls, **138 `logger_debug` lines** — six
spies, one per major, the whole board rather than the one spy the
section asked for.

**No poll ever caught an assigned spy without a position.** `x` is
absent from 13 of the 138 lines, and every one of the 13 is
`state == "unassigned"`: the six spies at the turn-123 baseline before
any of them was posted, and the player's own spy for the seven turns it
sat in hand. Not one line carries a positioned state with no `x`, and
no spy ever goes from a city back to `unassigned` either. So
`ExtractSpyFromCity` and the assignment of the destination are not
separable by a once-per-turn poll — the poll after a move order already
reads the spy as `travelling` to Y.

**Every reassignment was announced.** Twenty-six city changes across the
six spies and both sessions, and every single one emitted `spy_moved` on
the arrival turn, plus the five `counter_intel` transitions Run A
already described. The reassignment the run was built around: the
player's spy posted to Lhasa on 131, surveillance established on 135,
the move order to Sarai Batu issued that same turn, and the turn-136
poll reading `travelling` / Sarai Batu / `x = 22` with `spy_moved`
written.

**The second question answers itself in the code, and the answer is no.**
`moved()` is `spy.x ~= nil and (known.x ~= spy.x or known.y ~= spy.y)`.
A `known` overwritten with a positionless record compares `nil ~= 22`,
which is **true** — so the arrival still fires. The extraction poll's
own silence is correct, because at that poll there is no posting to
announce. The fix this section held in reserve — compare against the
last *positioned* `known` — would change nothing.

**Defect 2 therefore closes with no further change**, and india-diplo's
lost postings are fully accounted for without it. Of the eleven spies
there first located by a `spy_mission_completed`, six carry
`spy_revived` on or one turn before the posting the +4 artifact dates —
the revival early-return, fixed in `b51a639` — and five carry an
unlocated `spy_created` on the posting turn itself, fixed in the same
bundle. The one re-posting, `ENGLAND_6` from Amsterdam to Osininka with
no move between, dates to turn 164, and turn 164 is the first poll of
the session that resumed at 163. It is the seam, not the extraction.

**What this run does move is the seam, which it caught twice.** The
second run is the case outright: save-R reloaded at turn 134, the same
order issued, and the arrival at Sarai Batu landing on the session's
first poll. The turn-135 debug line shows the poller holding the new
posting; nothing was written, because the first poll of a session only
rebaselines. The `spy_surveillance_established` that follows on 139 is
the only trace the reassignment leaves — the same shape as Jerusalem's
`GREECE_4` in Run A. For the same reason two sessions and six spies
produced **zero** `spy_created` records. That is the concrete case the
"Sessions" item in `planned-changes.md` was waiting for, and the last
open espionage item.

**Surveillance is +4 again**, in a second game: all six postings with a
`spy_moved` to date them establish surveillance exactly four turns
later, and the seventh — the one lost in the seam — is dated to turn 135
by its debug lines and lands on 139. Still nobody at Familiar+ influence,
so the 1-turn branch stays unexercised.

Of the three fixes the branch was rebased onto, only the spy `agent` id
is exercised: it is on every spy record in the log. The window holds no
World Congress at all, so the guarded proposer and the dropped
`congress_founded` are still unsighted in a live game — `espionage-test.jsonl`
covers the founding, and nothing yet covers a proposal with no proposer.

With both questions answered, branch `run-b-instrumentation` has done
its job and can be deleted.
