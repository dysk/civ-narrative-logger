# Planned changes

Changes the logger still owes the downstream analyst
(`civ-strategy-analyst`). Implemented ones move to
`implemented-changes.md`.

## Explain a repeal that never got an outcome

`babylon-domination.jsonl` has Babylon proposing a repeal of
`RESOLUTION_WORLD_RELIGION` on turn 189 and no outcome for it anywhere,
though the log runs to turn 203 and the league is polled through 200.

The reload seam does not account for it. The proposal was already in
flight when the session before it last polled on 189, and Run C
established that a proposal in flight is rebuilt live from the league
across any seam - `congress.new` reads the proposals list from
`civ.congressSnapshot()`, not from the log. Two seams in
`espionage-test.jsonl` are crossed by votes that do get their outcomes.

This could not be settled at the time because `congress_snapshot` carried
only the host, the delegates and the vote threshold, so the log cannot
say what the proposals list held after turn 189. The snapshot now carries
the proposals, the active resolutions and the project states
(`implemented-changes.md`), which is exactly what the reading needs. So
the next game that repeals anything either reproduces this or retires it,
and there is no code change to make until one does.
