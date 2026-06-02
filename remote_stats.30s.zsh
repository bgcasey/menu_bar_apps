#!/usr/bin/env zsh

# SwiftBar Remote PC Stats
# Filename: remote_stats.30s.zsh (refreshes every 30 seconds)
#
# Shows CPU and memory usage of a remote Windows PC in the menu bar. The PC
# pushes its stats into a Dropbox-synced folder (see write_stats.ps1); this
# widget just reads the local synced file — no SSH, no network, no firewall
# changes. Very light: each refresh reads one tiny file.
#
# Pairs with write_stats.ps1 running on the Windows PC as a per-minute task.
# Data file: <Dropbox>/remote_stats/<HOST>.dat
# Data line: cpuPct;memPct;usedGB;totalGB;epochSeconds;hostname
#
# Setup:
#   1. Install SwiftBar: brew install --cask swiftbar
#   2. Symlink or copy this script into your SwiftBar plugin directory
#   3. Make executable: chmod +x remote_stats.30s.zsh
#   4. On the Windows PC, set up remote_stats/write_stats.ps1 (instructions in that file)
#
# Configuration (env vars or ~/.config/remote_stats_swiftbar.conf):
#   STATS_DIR     — folder holding the .dat files (default: the repo's
#                   remote_stats/ folder, next to this script — where
#                   write_stats.ps1 lives and writes)
#   STATS_FILE    — explicit .dat file to read (default: newest in STATS_DIR)
#   REMOTE_LABEL  — short label shown in the menu bar (default: the hostname)
#   STALE_SECS    — flag data as stale after this many seconds (default: 180)
#   WARN_PCT      — colour the reading orange at/above this %   (default: 75)
#   CRIT_PCT      — colour the reading red at/above this %       (default: 90)

# --- Configuration -----------------------------------------------------------
CONFIG_FILE="$HOME/.config/remote_stats_swiftbar.conf"
SELF="$0"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

# Resolve this script's real directory (SwiftBar runs it via a symlink); the
# .dat files written by write_stats.ps1 land in remote_stats/ beside it.
SCRIPT_DIR="${0:A:h}"
STATS_DIR=${STATS_DIR:-$SCRIPT_DIR/remote_stats}
STATS_FILE=${STATS_FILE:-}
REMOTE_LABEL=${REMOTE_LABEL:-}
STALE_SECS=${STALE_SECS:-180}
WARN_PCT=${WARN_PCT:-75}
CRIT_PCT=${CRIT_PCT:-90}

# --- Actions ------------------------------------------------------------------
# Reveal the data folder in Finder
if [[ "${1:-}" == "reveal" ]]; then
  open "$STATS_DIR" 2>/dev/null
  exit 0
fi

# --- Locate the data file -----------------------------------------------------
# Newest *.dat in STATS_DIR; (N) = no error if none, (om) = newest first.
if [[ -z "$STATS_FILE" ]]; then
  dat_files=("$STATS_DIR"/*.dat(Nom))
  STATS_FILE="${dat_files[1]}"
fi

# --- Helpers ------------------------------------------------------------------
color_for() {
  local pct=$1
  if (( pct >= CRIT_PCT )); then
    echo "red"
  elif (( pct >= WARN_PCT )); then
    echo "orange"
  else
    echo ""
  fi
}

format_age() {
  local s=$1
  if (( s < 60 )); then
    echo "${s}s ago"
  elif (( s < 3600 )); then
    echo "$(( s / 60 ))m ago"
  else
    echo "$(( s / 3600 ))h $(( (s % 3600) / 60 ))m ago"
  fi
}

# --- No data yet --------------------------------------------------------------
if [[ -z "$STATS_FILE" || ! -f "$STATS_FILE" ]]; then
  echo ":questionmark.circle: no data | color=gray sfsize=13"
  echo "---"
  echo "No stats file found | size=12"
  echo "Looked in: $STATS_DIR | size=11 color=gray"
  echo "Is write_stats.ps1 running on the PC, and has | size=11 color=gray"
  echo "Dropbox finished syncing on both machines? | size=11 color=gray"
  echo "---"
  echo "Reveal folder in Finder | bash=\"$SELF\" param1=reveal terminal=false sfimage=folder"
  echo "Refresh | bash=\"$SELF\" terminal=false refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# --- Parse --------------------------------------------------------------------
raw=$(head -1 "$STATS_FILE" 2>/dev/null)
cpu=$(echo "$raw"     | cut -d';' -f1 | tr -dc '0-9')
mempct=$(echo "$raw"  | cut -d';' -f2 | tr -dc '0-9')
used_gb=$(echo "$raw" | cut -d';' -f3)
total_gb=$(echo "$raw" | cut -d';' -f4)
epoch=$(echo "$raw"   | cut -d';' -f5 | tr -dc '0-9')
host=$(echo "$raw"    | cut -d';' -f6)

cpu=${cpu:-0}
mempct=${mempct:-0}
epoch=${epoch:-0}
[[ -z "$host" ]] && host=$(basename "$STATS_FILE" .dat)

label=${REMOTE_LABEL:-$host}

now=$(date +%s)
age=$(( now - epoch ))
(( age < 0 )) && age=0

# --- Stale data ---------------------------------------------------------------
if (( epoch == 0 || age > STALE_SECS )); then
  echo "${prefix}IDLE | sfimage=server.rack sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiTW9ub2Nocm9tZSJ9 font=Menlo sfsize=13 color=gray"
  echo "---"
  echo "$host | size=13 sfimage=desktopcomputer"
  if (( epoch > 0 )); then
    echo "Last seen: $(format_age "$age") | size=12 color=gray"
  else
    echo "No data received yet | size=12 color=gray"
  fi
  echo "PC may be off, asleep, or Dropbox isn't syncing. | size=11 color=gray"
  echo "---"
  echo "Reveal folder in Finder | bash=\"$SELF\" param1=reveal terminal=false sfimage=folder"
  echo "Refresh | bash=\"$SELF\" terminal=false refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# --- Live -------------------------------------------------------------------
cpu_color=$(color_for "$cpu")
mem_color=$(color_for "$mempct")

# Menu bar: colour the line on the higher of the two readings so a spike pops.
if (( cpu >= mempct )); then
  line_color="$cpu_color"
else
  line_color="$mem_color"
fi

prefix=""
[[ -n "$REMOTE_LABEL" ]] && prefix="$REMOTE_LABEL "

# sfconfig is base64 of {"renderingMode":"Monochrome"}
bar="${cpu}% / ${mempct}% | sfimage=server.rack sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiTW9ub2Nocm9tZSJ9 font=Menlo sfsize=13"
[[ -n "$line_color" ]] && bar="$bar color=$line_color"
echo "$prefix$bar"

# Dropdown
echo "---"
echo "$host | size=13 sfimage=desktopcomputer"
echo "---"

cpu_line="CPU: ${cpu}% | size=13 sfimage=cpu"
[[ -n "$cpu_color" ]] && cpu_line="$cpu_line color=$cpu_color"
echo "$cpu_line"

mem_line="Memory: ${mempct}%  (${used_gb} / ${total_gb} GB) | size=13 sfimage=memorychip"
[[ -n "$mem_color" ]] && mem_line="$mem_line color=$mem_color"
echo "$mem_line"

echo "Updated $(format_age "$age") | size=11 color=gray"

echo "---"
echo "Refresh | bash=\"$SELF\" terminal=false refresh=true sfimage=arrow.clockwise"
echo "Reveal folder in Finder | bash=\"$SELF\" param1=reveal terminal=false sfimage=folder"
