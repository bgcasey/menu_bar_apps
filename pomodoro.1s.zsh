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

# --- Settings actions ---------------------------------------------------------
save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"

  cat > "$CONFIG_FILE" <<EOF
WORK_MIN=$WORK_MIN
BREAK_MIN=$BREAK_MIN
TOTAL_CYCLES=$TOTAL_CYCLES
BANK_BREAK_TIME=$BANK_BREAK_TIME
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

  write_state
  notify "Cycle 1/$TOTAL_CYCLES — Focus"
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
      notify "Cycle $pom_cycle/$pom_total_cycles — Focus"
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
        notify "Cycle $pom_cycle/$pom_total_cycles — Focus"
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

  write_state
  notify "Restarted Pomodoro — Cycle 1/$TOTAL_CYCLES"
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
      notify "Cycle $pom_cycle/$pom_total_cycles — Focus"
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
  echo ":brain.head.profile: $time_str | font=Menlo sfsize=14"
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

bank_check=""
[[ "$BANK_BREAK_TIME" == "1" ]] && bank_check=" :checkmark:"
echo "--Bank skipped break time${bank_check} | bash=\"$SELF\" param1=toggle_bank_break_time terminal=false refresh=true"
