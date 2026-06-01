#!/usr/bin/env zsh

# SwiftBar Pomodoro Timer
# Filename: pomodoro.1s.zsh (refreshes every 1 second)
#
# Setup:
#   1. Install SwiftBar: brew install --cask swiftbar
#   2. Launch SwiftBar and set your plugin directory
#   3. Symlink or copy this script into that directory
#   4. Make executable: chmod +x pomodoro.1s.zsh
#
# Configuration (env vars or edit defaults below):
#   POM_WORK_MIN          — focus duration in minutes  (default: 25)
#   POM_BREAK_MIN         — break duration in minutes  (default: 5)
#   POM_CYCLES            — number of cycles            (default: 4)
#   POM_BANK_BREAK_TIME   — bank skipped break time      (default: 1; use 0 to disable)
#   POM_DESK_MODE         — standing-desk alternation    (default: 0; use 1 to enable)
#   POM_STAND_ROUNDS      — consecutive standing rounds  (default: 2)
#   POM_SIT_ROUNDS        — consecutive sitting rounds   (default: 2)
#   POM_START_POSTURE     — first round posture           (default: stand; or sit)
#
# Standing-desk mode: when enabled, each pomodoro cycle (round) is tagged as a
# standing or sitting round. Rounds run in blocks — e.g. 2 standing then 2
# sitting then repeat — and you're notified to change posture at each switch.

# --- Configuration -----------------------------------------------------------
STATE_FILE="/tmp/pomodoro_swiftbar.state"
CONFIG_FILE="$HOME/.config/pomodoro_swiftbar.conf"
SELF="$0"

# Load saved config, then allow env var overrides
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

WORK_MIN=${POM_WORK_MIN:-${WORK_MIN:-25}}
BREAK_MIN=${POM_BREAK_MIN:-${BREAK_MIN:-5}}
TOTAL_CYCLES=${POM_CYCLES:-${TOTAL_CYCLES:-4}}
BANK_BREAK_TIME=${POM_BANK_BREAK_TIME:-${BANK_BREAK_TIME:-1}}
DESK_MODE=${POM_DESK_MODE:-${DESK_MODE:-0}}
STAND_ROUNDS=${POM_STAND_ROUNDS:-${STAND_ROUNDS:-2}}
SIT_ROUNDS=${POM_SIT_ROUNDS:-${SIT_ROUNDS:-2}}
START_POSTURE=${POM_START_POSTURE:-${START_POSTURE:-stand}}

# --- State helpers ------------------------------------------------------------
read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
  else
    pom_status="idle"
  fi

  # Backward-compatible defaults for older state files
  pom_start=${pom_start:-0}
  pom_duration=${pom_duration:-0}
  pom_cycle=${pom_cycle:-1}
  pom_total_cycles=${pom_total_cycles:-$TOTAL_CYCLES}
  pom_work_min=${pom_work_min:-$WORK_MIN}
  pom_break_min=${pom_break_min:-$BREAK_MIN}
  pom_pause_remaining=${pom_pause_remaining:-0}
  pom_paused_phase=${pom_paused_phase:-""}
  pom_break_bank=${pom_break_bank:-0}
  pom_desk_mode=${pom_desk_mode:-$DESK_MODE}
  pom_stand_rounds=${pom_stand_rounds:-$STAND_ROUNDS}
  pom_sit_rounds=${pom_sit_rounds:-$SIT_ROUNDS}
  pom_start_posture=${pom_start_posture:-$START_POSTURE}
}

write_state() {
  cat > "$STATE_FILE" <<EOF
pom_status="$pom_status"
pom_start=$pom_start
pom_duration=$pom_duration
pom_cycle=$pom_cycle
pom_total_cycles=$pom_total_cycles
pom_work_min=$pom_work_min
pom_break_min=$pom_break_min
pom_pause_remaining=$pom_pause_remaining
pom_paused_phase="$pom_paused_phase"
pom_break_bank=$pom_break_bank
pom_desk_mode=$pom_desk_mode
pom_stand_rounds=$pom_stand_rounds
pom_sit_rounds=$pom_sit_rounds
pom_start_posture="$pom_start_posture"
EOF
}

clear_state() {
  rm -f "$STATE_FILE"
}

notify() {
  osascript -e "display notification \"$1\" with title \"Pomodoro\" sound name \"Glass\""
}

format_time() {
  local total_seconds=$1
  (( total_seconds < 0 )) && total_seconds=0
  local m=$(( total_seconds / 60 ))
  local s=$(( total_seconds % 60 ))
  printf "%02d:%02d" "$m" "$s"
}

current_remaining() {
  if [[ "$pom_status" == "paused" ]]; then
    echo "$pom_pause_remaining"
  else
    local now=$(date +%s)
    local elapsed=$(( now - pom_start ))
    echo $(( pom_duration - elapsed ))
  fi
}

start_break() {
  pom_status="break"
  pom_start=$(date +%s)

  # Add any banked break time to this break, then clear the bank
  pom_duration=$(( pom_break_min * 60 + pom_break_bank ))
  pom_break_bank=0

  pom_pause_remaining=0
  pom_paused_phase=""
  write_state
}

start_work() {
  pom_status="work"
  pom_start=$(date +%s)
  pom_duration=$(( pom_work_min * 60 ))
  pom_pause_remaining=0
  pom_paused_phase=""
  write_state
}

bank_remaining_break_time() {
  local remaining=$1

  if [[ "$BANK_BREAK_TIME" == "1" ]]; then
    (( remaining < 0 )) && remaining=0
    pom_break_bank=$(( pom_break_bank + remaining ))
  fi
}

# --- Standing-desk helpers ----------------------------------------------------
# Posture for a given cycle (1-indexed): rounds run in repeating blocks. The
# block leads with whichever posture pom_start_posture selects, then switches.
posture_for_cycle() {
  local cycle=$1
  local block=$(( pom_stand_rounds + pom_sit_rounds ))
  (( block <= 0 )) && { echo "$pom_start_posture"; return; }
  local pos=$(( (cycle - 1) % block ))

  local first second first_count
  if [[ "$pom_start_posture" == "sit" ]]; then
    first="sit"; second="stand"; first_count=$pom_sit_rounds
  else
    first="stand"; second="sit"; first_count=$pom_stand_rounds
  fi

  if (( pos < first_count )); then
    echo "$first"
  else
    echo "$second"
  fi
}

posture_label() {
  [[ "$1" == "stand" ]] && echo "Standing" || echo "Sitting"
}

posture_icon() {
  [[ "$1" == "stand" ]] && echo "figure.stand" || echo "figure.seated.side"
}

# Notify at the start of a focus round, calling out a posture switch when the
# new round flips standing <-> sitting.
notify_focus() {
  local cycle=$1 total=$2

  if [[ "$pom_desk_mode" != "1" ]]; then
    notify "Cycle $cycle/$total — Focus"
    return
  fi

  local posture prev
  posture=$(posture_for_cycle "$cycle")
  prev=""
  (( cycle > 1 )) && prev=$(posture_for_cycle $(( cycle - 1 )))

  if [[ "$cycle" == "1" || "$posture" != "$prev" ]]; then
    if [[ "$posture" == "stand" ]]; then
      notify "Cycle $cycle/$total — Stand up & focus 🧍"
    else
      notify "Cycle $cycle/$total — Sit down & focus 🪑"
    fi
  else
    notify "Cycle $cycle/$total — Focus ($(posture_label "$posture"))"
  fi
}

# --- Settings actions ---------------------------------------------------------
save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"

  cat > "$CONFIG_FILE" <<EOF
WORK_MIN=$WORK_MIN
BREAK_MIN=$BREAK_MIN
TOTAL_CYCLES=$TOTAL_CYCLES
BANK_BREAK_TIME=$BANK_BREAK_TIME
DESK_MODE=$DESK_MODE
STAND_ROUNDS=$STAND_ROUNDS
SIT_ROUNDS=$SIT_ROUNDS
START_POSTURE=$START_POSTURE
EOF
}

if [[ "${1:-}" == "set_work" ]]; then
  WORK_MIN="$2"
  save_config
  exit 0
fi

if [[ "${1:-}" == "set_break" ]]; then
  BREAK_MIN="$2"
  save_config
  exit 0
fi

if [[ "${1:-}" == "set_cycles" ]]; then
  TOTAL_CYCLES="$2"
  save_config
  exit 0
fi

if [[ "${1:-}" == "toggle_bank_break_time" ]]; then
  if [[ "$BANK_BREAK_TIME" == "1" ]]; then
    BANK_BREAK_TIME=0
  else
    BANK_BREAK_TIME=1
  fi

  save_config
  exit 0
fi

if [[ "${1:-}" == "toggle_desk_mode" ]]; then
  if [[ "$DESK_MODE" == "1" ]]; then
    DESK_MODE=0
  else
    DESK_MODE=1
  fi

  save_config
  exit 0
fi

if [[ "${1:-}" == "set_stand_rounds" ]]; then
  STAND_ROUNDS="$2"
  save_config
  exit 0
fi

if [[ "${1:-}" == "set_sit_rounds" ]]; then
  SIT_ROUNDS="$2"
  save_config
  exit 0
fi

if [[ "${1:-}" == "toggle_start_posture" ]]; then
  if [[ "$START_POSTURE" == "sit" ]]; then
    START_POSTURE="stand"
  else
    START_POSTURE="sit"
  fi

  save_config
  exit 0
fi

# --- Action handling ----------------------------------------------------------
# SwiftBar calls this script with $1 set to the action name
if [[ "${1:-}" == "start" ]]; then
  pom_status="work"
  pom_start=$(date +%s)
  pom_duration=$(( WORK_MIN * 60 ))
  pom_cycle=1
  pom_total_cycles=$TOTAL_CYCLES
  pom_work_min=$WORK_MIN
  pom_break_min=$BREAK_MIN
  pom_pause_remaining=0
  pom_paused_phase=""
  pom_break_bank=0
  pom_desk_mode=$DESK_MODE
  pom_stand_rounds=$STAND_ROUNDS
  pom_sit_rounds=$SIT_ROUNDS
  pom_start_posture=$START_POSTURE

  write_state
  notify_focus 1 "$TOTAL_CYCLES"
  exit 0
fi

if [[ "${1:-}" == "pause_resume" ]]; then
  read_state

  if [[ "$pom_status" == "paused" ]]; then
    pom_start=$(date +%s)
    pom_duration=$pom_pause_remaining
    pom_pause_remaining=0
    pom_status="${pom_paused_phase:-work}"
    pom_paused_phase=""
    write_state

  elif [[ "$pom_status" == "work" || "$pom_status" == "break" ]]; then
    now=$(date +%s)
    elapsed=$(( now - pom_start ))
    pom_pause_remaining=$(( pom_duration - elapsed ))
    (( pom_pause_remaining < 0 )) && pom_pause_remaining=0

    pom_paused_phase="$pom_status"
    pom_status="paused"
    write_state
  fi

  exit 0
fi

if [[ "${1:-}" == "skip" ]]; then
  read_state

  if [[ "$pom_status" == "work" ]]; then
    # Skip work — always go to break (even on the final cycle)
    start_break
    notify "Skipped — Break time"

  elif [[ "$pom_status" == "break" ]]; then
    # Skip break and optionally bank the unused break time
    remaining=$(current_remaining)
    bank_remaining_break_time "$remaining"

    if (( pom_cycle >= pom_total_cycles )); then
      notify "All cycles complete!"
      clear_state
    else
      pom_cycle=$(( pom_cycle + 1 ))
      start_work
      notify_focus "$pom_cycle" "$pom_total_cycles"
    fi

  elif [[ "$pom_status" == "paused" ]]; then
    if [[ "$pom_paused_phase" == "break" ]]; then
      # Skip a paused break and optionally bank the paused remaining time
      bank_remaining_break_time "$pom_pause_remaining"

      if (( pom_cycle >= pom_total_cycles )); then
        notify "All cycles complete!"
        clear_state
      else
        pom_cycle=$(( pom_cycle + 1 ))
        start_work
        notify_focus "$pom_cycle" "$pom_total_cycles"
      fi

    else
      # Skip paused work — always go to break (even on the final cycle)
      start_break
      notify "Skipped — Break time"
    fi
  fi

  exit 0
fi

if [[ "${1:-}" == "stop" ]]; then
  clear_state
  notify "Pomodoro stopped"
  exit 0
fi

if [[ "${1:-}" == "reset" ]]; then
  pom_status="work"
  pom_start=$(date +%s)
  pom_duration=$(( WORK_MIN * 60 ))
  pom_cycle=1
  pom_total_cycles=$TOTAL_CYCLES
  pom_work_min=$WORK_MIN
  pom_break_min=$BREAK_MIN
  pom_pause_remaining=0
  pom_paused_phase=""
  pom_break_bank=0
  pom_desk_mode=$DESK_MODE
  pom_stand_rounds=$STAND_ROUNDS
  pom_sit_rounds=$SIT_ROUNDS
  pom_start_posture=$START_POSTURE

  write_state
  notify "Restarted Pomodoro"
  notify_focus 1 "$TOTAL_CYCLES"
  exit 0
fi

# --- Phase transition logic ---------------------------------------------------
advance_phase() {
  if [[ "$pom_status" == "work" ]]; then
    # Work always transitions to a break — even the final cycle
    start_break
    notify "Break time (cycle $pom_cycle/$pom_total_cycles)"

  elif [[ "$pom_status" == "break" ]]; then
    if (( pom_cycle >= pom_total_cycles )); then
      notify "All $pom_total_cycles cycles complete!"
      clear_state
      pom_status="idle"
    else
      pom_cycle=$(( pom_cycle + 1 ))
      start_work
      notify_focus "$pom_cycle" "$pom_total_cycles"
    fi
  fi
}

# --- Render menu bar ----------------------------------------------------------
read_state

if [[ "$pom_status" == "idle" || -z "${pom_status:-}" ]]; then
  # Idle state — timer icon, ready to start
  echo " |sfimage=timer"
  echo "---"
  echo "Start Pomodoro | bash=\"$SELF\" param1=start terminal=false refresh=true"
  echo "---"
  echo "Settings | sfimage=gear"

  for m in 15 20 25 30 45 50 60; do
    check=""
    [[ "$m" == "$WORK_MIN" ]] && check=" :checkmark:"
    echo "--Work: ${m}m${check} | bash=\"$SELF\" param1=set_work param2=$m terminal=false refresh=true"
  done

  echo "-----"

  for m in 3 5 10 15; do
    check=""
    [[ "$m" == "$BREAK_MIN" ]] && check=" :checkmark:"
    echo "--Break: ${m}m${check} | bash=\"$SELF\" param1=set_break param2=$m terminal=false refresh=true"
  done

  echo "-----"

  for c in 1 2 3 4 5 6; do
    check=""
    [[ "$c" == "$TOTAL_CYCLES" ]] && check=" :checkmark:"
    echo "--Cycles: ${c}${check} | bash=\"$SELF\" param1=set_cycles param2=$c terminal=false refresh=true"
  done

  echo "-----"

  bank_check=""
  [[ "$BANK_BREAK_TIME" == "1" ]] && bank_check=" :checkmark:"
  echo "--Bank skipped break time${bank_check} | bash=\"$SELF\" param1=toggle_bank_break_time terminal=false refresh=true"

  exit 0
fi

# Calculate remaining time
remaining=$(current_remaining)

# Check for phase completion
if (( remaining <= 0 )) && [[ "$pom_status" != "paused" ]]; then
  advance_phase

  # Re-read after transition
  read_state

  if [[ "$pom_status" == "idle" || -z "${pom_status:-}" ]]; then
    echo "|sfimage=timer"
    echo "---"
    echo "Start Pomodoro | bash=\"$SELF\" param1=start terminal=false refresh=true"
    exit 0
  fi

  remaining=$(current_remaining)
fi

(( remaining < 0 )) && remaining=0
time_str=$(format_time "$remaining")

# Menu bar display
if [[ "$pom_status" == "work" ]]; then
  if [[ "$pom_desk_mode" == "1" ]]; then
    work_icon=$(posture_icon "$(posture_for_cycle "$pom_cycle")")
    echo ":brain.head.profile::$work_icon: $time_str | font=Menlo sfsize=14"
  else
    echo ":brain.head.profile: $time_str | font=Menlo sfsize=14"
  fi
elif [[ "$pom_status" == "break" ]]; then
  echo ":cup.and.saucer.fill: $time_str | font=Menlo sfsize=14"
elif [[ "$pom_status" == "paused" ]]; then
  echo ":pause.circle.fill: $time_str | font=Menlo sfsize=14"
fi

# Dropdown menu
echo "---"

# Status line
if [[ "$pom_status" == "work" ]]; then
  echo "Focus — Cycle $pom_cycle/$pom_total_cycles | size=14"
elif [[ "$pom_status" == "break" ]]; then
  echo "Break — Cycle $pom_cycle/$pom_total_cycles | size=14"
elif [[ "$pom_status" == "paused" ]]; then
  echo "Paused — Cycle $pom_cycle/$pom_total_cycles | size=14"
fi

echo "$time_str remaining | size=24 font=SFMono-Regular"

if [[ "$pom_desk_mode" == "1" ]]; then
  cur_posture=$(posture_for_cycle "$pom_cycle")
  echo "Posture: $(posture_label "$cur_posture") | size=12 sfimage=$(posture_icon "$cur_posture")"
fi

if [[ "$BANK_BREAK_TIME" == "1" && "$pom_break_bank" -gt 0 ]]; then
  banked_time_str=$(format_time "$pom_break_bank")
  echo "Banked break time: $banked_time_str | size=12"
fi

echo "---"

# Controls
if [[ "$pom_status" == "paused" ]]; then
  echo "Resume | bash=\"$SELF\" param1=pause_resume terminal=false refresh=true sfimage=play.fill"
else
  echo "Pause | bash=\"$SELF\" param1=pause_resume terminal=false refresh=true sfimage=pause.fill"
fi

echo "Skip | bash=\"$SELF\" param1=skip terminal=false refresh=true sfimage=forward.fill"
echo "Restart | bash=\"$SELF\" param1=reset terminal=false refresh=true sfimage=arrow.counterclockwise"
echo "Stop | bash=\"$SELF\" param1=stop terminal=false refresh=true sfimage=stop.fill"

echo "---"
echo "Settings | sfimage=gear"

for m in 15 20 25 30 45 50 60; do
  check=""
  [[ "$m" == "$WORK_MIN" ]] && check=" :checkmark:"
  echo "--Work: ${m}m${check} | bash=\"$SELF\" param1=set_work param2=$m terminal=false refresh=true"
done

echo "-----"

for m in 3 5 10 15; do
  check=""
  [[ "$m" == "$BREAK_MIN" ]] && check=" :checkmark:"
  echo "--Break: ${m}m${check} | bash=\"$SELF\" param1=set_break param2=$m terminal=false refresh=true"
done

echo "-----"

for c in 1 2 3 4 5 6; do
  check=""
  [[ "$c" == "$TOTAL_CYCLES" ]] && check=" :checkmark:"
  echo "--Cycles: ${c}${check} | bash=\"$SELF\" param1=set_cycles param2=$c terminal=false refresh=true"
done

echo "-----"

desk_check=""
[[ "$DESK_MODE" == "1" ]] && desk_check=" :checkmark:"
echo "--Standing desk mode${desk_check} | bash=\"$SELF\" param1=toggle_desk_mode terminal=false refresh=true"

if [[ "$START_POSTURE" == "sit" ]]; then
  start_posture_label="Start with: Sitting"
else
  start_posture_label="Start with: Standing"
fi
echo "--${start_posture_label} | bash=\"$SELF\" param1=toggle_start_posture terminal=false refresh=true"

for r in 1 2 3 4; do
  check=""
  [[ "$r" == "$STAND_ROUNDS" ]] && check=" :checkmark:"
  echo "--Stand rounds: ${r}${check} | bash=\"$SELF\" param1=set_stand_rounds param2=$r terminal=false refresh=true"
done

echo "-----"

for r in 1 2 3 4; do
  check=""
  [[ "$r" == "$SIT_ROUNDS" ]] && check=" :checkmark:"
  echo "--Sit rounds: ${r}${check} | bash=\"$SELF\" param1=set_sit_rounds param2=$r terminal=false refresh=true"
done

echo "-----"

bank_check=""
[[ "$BANK_BREAK_TIME" == "1" ]] && bank_check=" :checkmark:"
echo "--Bank skipped break time${bank_check} | bash=\"$SELF\" param1=toggle_bank_break_time terminal=false refresh=true"
