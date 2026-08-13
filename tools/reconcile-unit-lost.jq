# Annotates unit_lost records with a best-effort cause, since UnitPrekill
# (which produces unit_lost) fires on every unit removal regardless of why -
# combat death, a great person's power spent, a settler founding a city, a
# city falling to conquest, or a caravan/cargo ship/workboat/missionary
# completing its one-shot job. Everything else passes through unchanged.
#
# cause is one of: killed | expended | founded_city | city_captured |
# used_up | unknown. confidence is confirmed | inferred | none.
#
# The "Barbarians" inference is evidence-based, not a guess: in the hook
# data, killed_by on unit_lost is only ever populated for civilian capture
# (worker/settler/missionary), and unit_killed's killer is never
# "Barbarians" - the DLL simply doesn't log barbarian-caused combat kills
# any other way. So a combat-type unit_lost that matches none of the other
# rules is, by elimination, almost certainly a barbarian kill.
#
# Usage: jq -s -f tools/reconcile-unit-lost.jq events.jsonl

def great_person_types:
  ["UNIT_PROPHET", "UNIT_SCIENTIST", "UNIT_ENGINEER", "UNIT_WRITER",
   "UNIT_ARTIST", "UNIT_MUSICIAN", "UNIT_MERCHANT",
   "UNIT_GREAT_ADMIRAL", "UNIT_GREAT_GENERAL"];

def founding_types: ["UNIT_SETTLER", "UNIT_SPANISH_CONQUISTADOR"];

def consumed_types:
  ["UNIT_CARAVAN", "UNIT_CARGO_SHIP", "UNIT_WORKBOAT", "UNIT_MISSIONARY"];

. as $all
| ($all | map(select(.event == "great_person_expended"))) as $gpe
| ($all | map(select(.event == "city_founded"))) as $cf
| ($all | map(select(.event == "city_captured"))) as $cc

| reduce $all[] as $e (
    {out: [], remaining_uk: ($all | map(select(.event == "unit_killed")))};

    if $e.event != "unit_lost" then
      .out += [$e]

    elif ($e | has("killed_by")) then
      .out += [$e + {cause: "killed", killer: $e.killed_by, confidence: "confirmed"}]

    elif (great_person_types | index($e.unit))
      and ($gpe | any(.civ == $e.civ and .turn == $e.turn and .great_person == $e.unit)) then
      .out += [$e + {cause: "expended", confidence: "confirmed"}]

    elif (founding_types | index($e.unit))
      and ($cf | any(.civ == $e.civ and .turn == $e.turn and .x == $e.x and .y == $e.y)) then
      .out += [$e + {cause: "founded_city", confidence: "confirmed"}]

    elif ($cc | any(.turn == $e.turn and .x == $e.x and .y == $e.y and .old_owner == $e.civ)) then
      ( $cc | map(select(.turn == $e.turn and .x == $e.x and .y == $e.y and .old_owner == $e.civ)) | first) as $cap
      | .out += [$e + {cause: "city_captured", captured_by: $cap.new_owner, confidence: "confirmed"}]

    elif (.remaining_uk | any(.turn == $e.turn and .unit == $e.unit and .victim == $e.civ)) then
      (.remaining_uk | map(select(.turn == $e.turn and .unit == $e.unit and .victim == $e.civ)) | first) as $match
      | (.remaining_uk | to_entries | map(select(.value == $match)) | first.key) as $idx
      | .out += [$e + {cause: "killed", killer: $match.killer, confidence: "confirmed"}]
      | .remaining_uk |= del(.[$idx])

    elif (consumed_types | index($e.unit)) then
      .out += [$e + {cause: "used_up", confidence: "confirmed"}]

    elif ($e.civ != "Barbarians") then
      .out += [$e + {cause: "killed", killer: "Barbarians", confidence: "inferred"}]

    else
      .out += [$e + {cause: "unknown", confidence: "none"}]

    end
  )
| .out[]
