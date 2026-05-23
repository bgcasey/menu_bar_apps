#!/usr/bin/env zsh

# SwiftBar Obsidian Work Hours
# Filename: obsidian_work_hours.30s.zsh
#
# Menu bar widget that shows how many hours you've worked today vs how many
# you planned to work, sourced from your Obsidian daily and weekly notes.
#
# Worked hours: sum of "HH:MM-HH:MM" entries in today's daily note "## Work log"
# section that include an "#abmi/" tag (excluding #abmi/sick_day and
# #abmi/vacation_day) — matches the calculation used in the weekly note's
# "Planned Hours" dataviewjs block.
#
# Planned hours: parsed from "rows[N].hours = X.X;" in this week's weekly note,
# where N is today's day-of-week index (0=Sun .. 6=Sat).
#
# Setup:
#   1. Install SwiftBar: brew install --cask swiftbar
#   2. Symlink or copy this script into your SwiftBar plugin directory
#   3. Make executable: chmod +x obsidian_work_hours.30s.zsh
#
# Configuration (env vars or edit defaults below):
#   OBS_VAULT_PATH       — absolute path to your Obsidian vault root
#   OBS_DAILY_SUBDIR     — daily notes folder relative to vault
#   OBS_WEEKLY_SUBDIR    — weekly notes folder relative to vault
#   OBS_VAULT_NAME       — vault name used in obsidian:// URLs (defaults to dir basename)

# --- Configuration -----------------------------------------------------------
VAULT_PATH=${OBS_VAULT_PATH:-/Users/brendan/Dropbox/0_obsidian}
DAILY_SUBDIR=${OBS_DAILY_SUBDIR:-0_periodic/daily}
WEEKLY_SUBDIR=${OBS_WEEKLY_SUBDIR:-0_periodic/weekly}
VAULT_NAME=${OBS_VAULT_NAME:-${VAULT_PATH:t}}

SELF="$0"
SELF_DIR="${SELF:A:h}"
ICON_PATH="$SELF_DIR/obsidian_wireframe.png"

TODAY=$(date +%Y-%m-%d)
DOW=$(date +%w)  # 0=Sun .. 6=Sat
WEEK_START=$(date -v-${DOW}d +%Y-%m-%d)
WEEK_END=$(date -v-${DOW}d -v+6d +%Y-%m-%d)

DAILY_DIR="$VAULT_PATH/$DAILY_SUBDIR"
WEEKLY_NOTE="$VAULT_PATH/$WEEKLY_SUBDIR/${WEEK_START}_to_${WEEK_END}.md"

# --- Compute hours ----------------------------------------------------------
# Python emits:
#   line 1: "<today_worked_h> <today_planned_h>"  (for the menu bar title)
#   line 2: marker "---DROPDOWN---"
#   remaining lines: SwiftBar dropdown body (per-day breakdown, totals, projects)
COMPUTED=$(
  DAILY_DIR="$DAILY_DIR" \
  WEEKLY_NOTE="$WEEKLY_NOTE" \
  TODAY="$TODAY" \
  WEEK_START="$WEEK_START" \
  DOW="$DOW" \
  TAGS_PATH="$VAULT_PATH/5_system/tags.md" \
  /usr/bin/python3 <<'PY'
import os, re
from datetime import date, timedelta

daily_dir = os.environ["DAILY_DIR"]
weekly = os.environ["WEEKLY_NOTE"]
today_str = os.environ["TODAY"]
week_start_str = os.environ["WEEK_START"]
dow_today = int(os.environ["DOW"])
tags_path = os.environ["TAGS_PATH"]

DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

def read(p):
    try:
        with open(p, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None

def minutes_between(a, b):
    sh, sm = map(int, a.split(":"))
    eh, em = map(int, b.split(":"))
    return (eh * 60 + em) - (sh * 60 + sm)

# Load Work Codes lookup (code -> human name)
lookup = {}
tags_md = read(tags_path)
if tags_md:
    in_section = False
    for line in tags_md.splitlines():
        if line.strip() == "## Work Codes":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section and line.startswith("|") and "---" not in line:
            m = re.match(r"^\|([^|]+)\|([^|]+)\|", line)
            if m:
                code = m.group(1).strip()
                name = m.group(2).strip()
                if code and name and code.lower() != "tag":
                    lookup[code.upper()] = name

def scan_work_log(md):
    """Return (total_minutes, {project_name: minutes})."""
    total = 0
    projects = {}
    if not md:
        return total, projects
    in_log = False
    for line in md.splitlines():
        if re.match(r"^##\s+Work log\s*$", line):
            in_log = True
            continue
        if in_log and line.startswith("## "):
            break
        if not in_log:
            continue
        m = re.match(r"^\s*-\s*(\d{2}:\d{2})-(\d{2}:\d{2})\s", line)
        if not m:
            continue
        if "#abmi" not in line:
            continue
        if "#abmi/sick_day" in line or "#abmi/vacation_day" in line:
            continue
        mins = minutes_between(m.group(1), m.group(2))
        if mins <= 0:
            continue
        total += mins
        for tag in re.findall(r"#abmi/[^\s#,)]+", line, flags=re.I):
            code = tag.split("/", 1)[1].split("/")[0].rstrip(".,;:!?").strip().upper()
            name = lookup.get(code, code)
            projects[name] = projects.get(name, 0) + mins
    return total, projects

# Walk the 7 days of this week (Sun..Sat from WEEK_START)
ws = date.fromisoformat(week_start_str)
per_day = []          # list of (date_str, dow_name, minutes)
today_projects = {}
for i in range(7):
    d = ws + timedelta(days=i)
    ds = d.isoformat()
    md = read(os.path.join(daily_dir, f"{ds}.md"))
    total, projects = scan_work_log(md)
    per_day.append((ds, DAY_NAMES[i], total))
    if ds == today_str:
        today_projects = projects

today_worked = next((m for d, _, m in per_day if d == today_str), 0)
week_worked = sum(m for _, _, m in per_day)

# Planned hours from the weekly note: rows[N].hours for today, plus week sum
weekly_md = read(weekly)
planned_today = None
planned_week_total = 0.0
planned_known = False
if weekly_md:
    for i in range(7):
        m = re.search(rf"rows\[\s*{i}\s*\]\.hours\s*=\s*([0-9]*\.?[0-9]+)", weekly_md)
        if m:
            planned_known = True
            v = float(m.group(1))
            planned_week_total += v
            if i == dow_today:
                planned_today = v

def hfmt(mins):
    return f"{mins/60:.1f}"

today_w = hfmt(today_worked)
today_p = f"{planned_today:.1f}" if planned_today is not None else "?"
week_w = hfmt(week_worked)
week_p = f"{planned_week_total:.1f}" if planned_known else "?"

print(f"{today_w} {today_p}")
print("---DROPDOWN---")
print(f"Today · {today_str} | size=11 color=gray")
print(f"Worked: {today_w}h    Planned: {today_p}h")
print("---")
print("This week | size=11 color=gray")
cum = 0
for ds, name, mins in per_day:
    cum += mins
    marker = " ←" if ds == today_str else ""
    print(f"  {name} {ds[-5:]}  {hfmt(mins)}h   (cum {hfmt(cum)}h){marker}")
print(f"Total: {week_w}h / {week_p}h")
if today_projects:
    print("---")
    print("Today by project | size=11 color=gray")
    for name, mins in sorted(today_projects.items(), key=lambda kv: -kv[1]):
        print(f"  {name}: {hfmt(mins)}h")
PY
)

TITLE_LINE=${COMPUTED%%$'\n'*}
DROPDOWN=${COMPUTED#*---DROPDOWN---$'\n'}
read -r WORKED_H PLANNED_H <<<"$TITLE_LINE"

# --- Helpers ----------------------------------------------------------------
open_daily() {
  /usr/bin/open "obsidian://open?vault=$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$VAULT_NAME")&file=$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$DAILY_SUBDIR/$TODAY")"
}

open_weekly() {
  /usr/bin/open "obsidian://open?vault=$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$VAULT_NAME")&file=$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$WEEKLY_SUBDIR/${WEEK_START}_to_${WEEK_END}")"
}

# --- CLI dispatch -----------------------------------------------------------
case "${1:-}" in
  open_daily)  open_daily;  exit 0 ;;
  open_weekly) open_weekly; exit 0 ;;
esac

# --- Menu bar output --------------------------------------------------------
echo "${WORKED_H}/${PLANNED_H}h | sfimage=calendar.day.timeline.left"
echo "---"
print -r -- "$DROPDOWN"
echo "---"
echo "Open today's note | bash=\"$SELF\" param1=open_daily terminal=false refresh=false"
echo "Open this week's note | bash=\"$SELF\" param1=open_weekly terminal=false refresh=false"
echo "Refresh | refresh=true"
