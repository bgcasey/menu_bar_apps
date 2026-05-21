#!/usr/bin/env zsh

# SwiftBar Obsidian Daily Note
# Filename: obsidian_daily.30s.zsh
#
# Clicking the menu bar icon opens an editable dialog pre-filled with the
# current H2 section of today's Obsidian daily note. Save writes it back.
#
# Setup:
#   1. Install SwiftBar: brew install --cask swiftbar
#   2. Symlink or copy this script into your SwiftBar plugin directory
#   3. Make executable: chmod +x obsidian_daily.30s.zsh
#
# Configuration (env vars or edit defaults below):
#   OBS_VAULT_PATH      — absolute path to your Obsidian vault root
#   OBS_DAILY_SUBDIR    — daily notes folder relative to vault (default: 0_periodic/daily)
#   OBS_DATE_FORMAT     — strftime format for note filename (default: %Y-%m-%d)
#   OBS_SECTIONS        — comma-separated H2 sections to edit (default: Work log,Tasks,Scratch)
#   OBS_TEMPLATE_FILE   — optional template file used when creating today's note

# --- Configuration -----------------------------------------------------------
VAULT_PATH=${OBS_VAULT_PATH:-/Users/brendan/Dropbox/0_obsidian}
DAILY_SUBDIR=${OBS_DAILY_SUBDIR:-0_periodic/daily}
DATE_FORMAT=${OBS_DATE_FORMAT:-%Y-%m-%d}
SECTIONS=${OBS_SECTIONS:-Work log,Tasks,Scratch}
TEMPLATE_FILE=${OBS_TEMPLATE_FILE:-}

SELF="$0"
SELF_DIR="${SELF:A:h}"
ICON_PATH="$SELF_DIR/obsidian_wireframe.png"
TODAY=$(date +"$DATE_FORMAT")
NOTE_DIR="$VAULT_PATH/$DAILY_SUBDIR"
NOTE_PATH="$NOTE_DIR/$TODAY.md"

# --- Helpers ----------------------------------------------------------------

create_today() {
  mkdir -p "$NOTE_DIR"
  if [[ -n "$TEMPLATE_FILE" && -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$NOTE_PATH"
  else
    cat > "$NOTE_PATH" <<EOF
---
date: "$TODAY"
type: daily
---

EOF
  fi
}

extract_sections() {
  NOTE_PATH="$NOTE_PATH" SECTIONS="$SECTIONS" /usr/bin/python3 <<'PY'
import os, sys
path = os.environ["NOTE_PATH"]
sections = [s.strip() for s in os.environ["SECTIONS"].split(",") if s.strip()]

try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

def extract(section):
    target = f"## {section}\n"
    try:
        start = lines.index(target)
    except ValueError:
        return ""
    end = start + 1
    while end < len(lines):
        stripped = lines[end].rstrip("\n")
        if stripped.startswith("## ") or stripped.startswith("# ") or stripped in ("---", "***"):
            break
        end += 1
    return "".join(lines[start + 1:end]).strip("\n")

parts = []
for s in sections:
    body = extract(s)
    parts.append(f"## {s}\n{body}\n" if body else f"## {s}\n")
sys.stdout.write("\n\n\n\n".join(parts))
PY
}

replace_sections() {
  local new_content="$1"
  NOTE_PATH="$NOTE_PATH" SECTIONS="$SECTIONS" NEW_CONTENT="$new_content" /usr/bin/python3 <<'PY'
import os, sys, re
path = os.environ["NOTE_PATH"]
sections = [s.strip() for s in os.environ["SECTIONS"].split(",") if s.strip()]
edited = os.environ["NEW_CONTENT"]

section_set = set(sections)
parsed = {}
current = None
buffer = []
for line in edited.split("\n"):
    m = re.match(r"^## (.+)$", line)
    if m and m.group(1).strip() in section_set:
        if current is not None:
            parsed[current] = "\n".join(buffer)
        current = m.group(1).strip()
        buffer = []
    elif current is not None:
        buffer.append(line)
if current is not None:
    parsed[current] = "\n".join(buffer)

try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

def write_section(lines, section, new):
    new = new.strip("\n")
    block = (new + "\n\n") if new else "\n"
    target = f"## {section}\n"
    try:
        start = lines.index(target)
    except ValueError:
        if lines and not lines[-1].endswith("\n"):
            lines.append("\n")
        return lines + (["\n"] if lines else []) + [target, block]
    end = start + 1
    while end < len(lines):
        stripped = lines[end].rstrip("\n")
        if stripped.startswith("## ") or stripped.startswith("# ") or stripped in ("---", "***"):
            break
        end += 1
    return lines[:start + 1] + [block] + lines[end:]

for s in sections:
    if s in parsed:
        lines = write_section(lines, s, parsed[s])

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PY
}

edit_section() {
  [[ ! -f "$NOTE_PATH" ]] && create_today

  local initfile result new_content
  initfile=$(mktemp /tmp/obsidian_edit.XXXXXX)
  extract_sections > "$initfile"

  result=$(INITFILE="$initfile" TODAY="$TODAY" ICON_PATH="$ICON_PATH" /usr/bin/osascript <<'APPLESCRIPT'
use framework "AppKit"
use framework "Foundation"
use scripting additions

set initFile to system attribute "INITFILE"
set todayStr to system attribute "TODAY"
set iconPath to system attribute "ICON_PATH"

set initialText to ""
try
    set initialText to (do shell script "cat -- " & quoted form of initFile)
end try

current application's NSApplication's sharedApplication()
current application's NSApp's setActivationPolicy:1 -- Accessory (allows key events)
current application's NSApp's activateIgnoringOtherApps:true

set alert to current application's NSAlert's alloc()'s init()
alert's setMessageText:"Daily Note"
alert's setInformativeText:todayStr
set customIcon to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
if customIcon is not missing value then
    alert's setIcon:customIcon
end if
alert's addButtonWithTitle:"Save"
alert's addButtonWithTitle:"Cancel"

set alertWindow to alert's |window|()
alertWindow's setAppearance:(current application's NSAppearance's appearanceNamed:"NSAppearanceNameDarkAqua")
alertWindow's setTitle:("Obsidian · " & todayStr)
alertWindow's setCollectionBehavior:257 -- CanJoinAllSpaces(1) | FullScreenAuxiliary(256)

set scrollW to 680
set scrollH to 440
set scrollRect to current application's NSMakeRect(0, 0, scrollW, scrollH)
set scrollView to (current application's NSScrollView's alloc()'s initWithFrame:scrollRect)
scrollView's setHasVerticalScroller:true
scrollView's setBorderType:0 -- NSNoBorder
scrollView's setDrawsBackground:false
scrollView's setAutohidesScrollers:true

set textRect to current application's NSMakeRect(0, 0, scrollW, scrollH)
set textView to (current application's NSTextView's alloc()'s initWithFrame:textRect)
textView's setString:initialText

set textBg to current application's NSColor's colorWithCalibratedRed:0.118 green:0.118 blue:0.129 alpha:1.0
textView's setBackgroundColor:textBg
set textColor to current application's NSColor's colorWithCalibratedRed:0.863 green:0.866 blue:0.871 alpha:1.0
textView's setTextColor:textColor
textView's setInsertionPointColor:textColor

set monoFont to (current application's NSFont's fontWithName:"SF Mono" |size|:14)
if monoFont is missing value then
    set monoFont to (current application's NSFont's fontWithName:"JetBrains Mono" |size|:14)
end if
if monoFont is missing value then
    set monoFont to (current application's NSFont's fontWithName:"Menlo" |size|:14)
end if
if monoFont is missing value then
    set monoFont to (current application's NSFont's userFixedPitchFontOfSize:14)
end if
textView's setFont:monoFont

textView's setTextContainerInset:(current application's NSMakeSize(14, 14))
textView's setAutomaticQuoteSubstitutionEnabled:false
textView's setAutomaticDashSubstitutionEnabled:false
textView's setAutomaticTextReplacementEnabled:false
textView's setAutomaticSpellingCorrectionEnabled:false
textView's setAutomaticLinkDetectionEnabled:false
textView's setSmartInsertDeleteEnabled:false
textView's setRichText:false
textView's setAllowsUndo:true
textView's setUsesFindBar:true
textView's setHorizontallyResizable:false
textView's setVerticallyResizable:true
textView's setAutoresizingMask:2 -- Width
(textView's textContainer())'s setWidthTracksTextView:true

scrollView's setDocumentView:textView
alert's setAccessoryView:scrollView

set btns to alert's buttons()
set saveBtn to item 1 of btns
saveBtn's setKeyEquivalent:"s"
saveBtn's setKeyEquivalentModifierMask:1048576 -- NSEventModifierFlagCommand
set cancelBtn to item 2 of btns
cancelBtn's setKeyEquivalent:(ASCII character 27)

alertWindow's setInitialFirstResponder:textView

set response to (alert's runModal()) as integer
set finalText to (textView's |string|()) as string

if response = 1000 then -- NSAlertFirstButtonReturn
    return "__SAVED__" & finalText
else
    return "__CANCELLED__"
end if
APPLESCRIPT
)

  rm -f "$initfile"

  result=${result//$'\r'/$'\n'}
  if [[ "$result" == __SAVED__* ]]; then
    new_content=${result#__SAVED__}
    replace_sections "$new_content"
  fi
}

# --- CLI dispatch -----------------------------------------------------------
case "${1:-}" in
  edit)   edit_section; exit 0 ;;
  create) create_today; exit 0 ;;
esac

# --- Menu bar output --------------------------------------------------------
echo " | bash=\"$SELF\" param1=edit terminal=false refresh=true dropdown=false sfimage=square.and.pencil"
