# Planned changes

Changes the logger still owes the downstream analyst
(`civ-strategy-analyst`). Implemented ones move to
`implemented-changes.md`.

## Stop announcing a Congress founding on every reload

### The problem

`congress.new` builds its state fresh — `{ turn = nil, snapshot = nil }`
(`src/congress.lua:103`) — and the first poll of a session therefore
takes the `not state.snapshot` branch (`:116`), announcing a founding
and skipping the diff. Nothing carries the previous session's snapshot
across the seam, because nothing persists between sessions at all: the
census keeps its `known` table the same way (`src/census.lua:17`).

`examples/babylon-domination.jsonl` in the analyst repo shows the cost
plainly. That league was founded once, on turn 100, and the log claims

```
{"event":"congress_founded","host":"Babylon","turn":100}
{"event":"congress_founded","host":"Babylon","turn":141}
{"event":"congress_founded","host":"Babylon","turn":146}
{"event":"congress_founded","host":"Babylon","turn":190}
```

one per `session_started`. Three of the four are false. This is not the
one-shot defect and predates it — it costs every event type `diff`
produces, not just outcomes: a host change, a repeal, a UN formation or
a resolution decided across that seam is never written, and a vote that
concluded there stays "pending" in the analyst forever, which is the
same false claim `resolution_undetermined` was added to avoid.

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

The founding is the easier half. `congress_founded` tells the analyst
nothing it does not learn from the first `congress_snapshot` — the
analyst names the type as known and reads it nowhere else — so the
honest fix is to drop the event and let the first snapshot mark the
league's arrival. Emitting it only when the league is genuinely new
would need a way to tell "new league" from "new session", and no league
API offers one.

The lost diff is the harder half and needs the log to describe itself:
`congress_snapshot` would have to carry the proposals, active
resolutions and project states that `diff` compares, so a resuming
session can rebuild its baseline from the last snapshot it wrote rather
than starting blind. That is a bigger record and a new read path — worth
doing only if the seam is shown to swallow something real, which is what
the `WORLD_RELIGION` question above should settle first.

### Verification

The fakes can drive both halves: a poll sequence interrupted by a fresh
`congress.new` over the same fake league is exactly the reload. What
they cannot check is whether a real reload resumes where the last poll
left off, so the seam's real width wants one replayed save.
