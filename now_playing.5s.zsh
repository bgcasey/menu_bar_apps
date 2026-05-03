#!/usr/bin/env zsh

# SwiftBar Now Playing
# Filename: now_playing.5s.zsh (refreshes every 5 seconds)
#
# Shows the currently playing track in the menu bar.
# Supports: any app via nowplaying-cli, or Spotify / Apple Music via AppleScript.
#
# Setup:
#   1. Install SwiftBar: brew install --cask swiftbar
#   2. Symlink into your SwiftBar plugin directory
#   3. Optional: brew install nowplaying-cli (for system-wide support)

SELF="$0"
MAX_TITLE_LEN=0

# --- Helpers ------------------------------------------------------------------
truncate_str() {
  local str="$1" max="$2"
  if (( ${#str} > max )); then
    echo "${str:0:$((max - 1))}…"
  else
    echo "$str"
  fi
}

is_running() {
  osascript -l JavaScript -e "Application('System Events').processes.whose({name: '$1'}).length > 0" 2>/dev/null
}

# --- Fetch now-playing info ---------------------------------------------------
title="" artist="" album="" state="" source="" duration="" position=""

if command -v nowplaying-cli &>/dev/null; then
  # System-wide: catches browsers, Podcasts, any media app
  title=$(nowplaying-cli get title 2>/dev/null)
  artist=$(nowplaying-cli get artist 2>/dev/null)
  album=$(nowplaying-cli get album 2>/dev/null)
  duration=$(nowplaying-cli get duration 2>/dev/null)
  position=$(nowplaying-cli get elapsedTime 2>/dev/null)
  rate=$(nowplaying-cli get playbackRate 2>/dev/null)
  bundle=$(nowplaying-cli get bundleIdentifier 2>/dev/null)

  if [[ -n "$title" && "$title" != "null" ]]; then
    if [[ "${rate:-0}" == "0" || "${rate:-0}" == "0.0" ]]; then
      state="paused"
    else
      state="playing"
    fi
    case "$bundle" in
      com.spotify.client)        source="Spotify" ;;
      com.apple.Music)           source="Apple Music" ;;
      com.apple.podcasts)        source="Podcasts" ;;
      com.google.Chrome*)        source="Chrome" ;;
      com.apple.Safari*)         source="Safari" ;;
      org.mozilla.firefox*)      source="Firefox" ;;
      null|"")
        # Check if a music app is actively playing this track
        source="Unknown"
        if [[ "$(is_running Spotify)" == "true" ]]; then
          sp_state=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null)
          if [[ "$sp_state" == "playing" || "$sp_state" == "paused" ]]; then
            sp_track=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null)
            [[ "$sp_track" == "$title" ]] && source="Spotify"
          fi
        fi
        if [[ "$source" == "Unknown" && "$(is_running Music)" == "true" ]]; then
          mu_state=$(osascript -e 'tell application "Music" to player state as string' 2>/dev/null)
          if [[ "$mu_state" == "playing" || "$mu_state" == "paused" ]]; then
            mu_track=$(osascript -e 'tell application "Music" to name of current track' 2>/dev/null)
            [[ "$mu_track" == "$title" ]] && source="Apple Music"
          fi
        fi
        # If neither music app owns the track, check browsers
        if [[ "$source" == "Unknown" ]]; then
          if [[ "$(is_running Safari)" == "true" ]]; then
            source="Safari"
          elif [[ "$(is_running "Google Chrome")" == "true" ]]; then
            source="Chrome"
          elif [[ "$(is_running Firefox)" == "true" ]]; then
            source="Firefox"
          elif [[ "$(is_running Arc)" == "true" ]]; then
            source="Arc"
          fi
        fi
        ;;
      *)                         source="$bundle" ;;
    esac
  fi
fi

# Fallback to app-specific AppleScript if nowplaying-cli unavailable or silent
if [[ -z "$title" || "$title" == "null" ]]; then
  # Try Spotify first
  if [[ "$(is_running Spotify)" == "true" ]]; then
    info=$(osascript -l JavaScript -e '
      var app = Application("Spotify");
      var s = app.playerState();
      if (s === "stopped") { JSON.stringify({state:"stopped"}); }
      else {
        var t = app.currentTrack();
        JSON.stringify({
          state: s,
          name: t.name(),
          artist: t.artist(),
          album: t.album(),
          duration: t.duration() / 1000,
          position: app.playerPosition()
        });
      }' 2>/dev/null)

    if [[ -n "$info" ]]; then
      s=$(echo "$info" | jq -r '.state // empty')
      if [[ "$s" != "stopped" && -n "$s" ]]; then
        title=$(echo "$info" | jq -r '.name // empty')
        artist=$(echo "$info" | jq -r '.artist // empty')
        album=$(echo "$info" | jq -r '.album // empty')
        duration=$(echo "$info" | jq -r '.duration // empty')
        position=$(echo "$info" | jq -r '.position // empty')
        state="$s"
        source="Spotify"
      fi
    fi
  fi
fi

if [[ -z "$title" || "$title" == "null" ]]; then
  # Try Apple Music
  if [[ "$(is_running Music)" == "true" ]]; then
    info=$(osascript -l JavaScript -e '
      var app = Application("Music");
      var s = app.playerState();
      if (s === "stopped") { JSON.stringify({state:"stopped"}); }
      else {
        var t = app.currentTrack();
        JSON.stringify({
          state: s,
          name: t.name(),
          artist: t.artist(),
          album: t.album(),
          duration: t.duration(),
          position: app.playerPosition()
        });
      }' 2>/dev/null)

    if [[ -n "$info" ]]; then
      s=$(echo "$info" | jq -r '.state // empty')
      if [[ "$s" != "stopped" && -n "$s" ]]; then
        title=$(echo "$info" | jq -r '.name // empty')
        artist=$(echo "$info" | jq -r '.artist // empty')
        album=$(echo "$info" | jq -r '.album // empty')
        duration=$(echo "$info" | jq -r '.duration // empty')
        position=$(echo "$info" | jq -r '.position // empty')
        state="$s"
        source="Apple Music"
      fi
    fi
  fi
fi

# --- Action handling ----------------------------------------------------------
if [[ "${1:-}" == "playpause" ]]; then
  if command -v nowplaying-cli &>/dev/null; then
    nowplaying-cli togglePlayPause
  elif [[ "$source" == "Spotify" ]]; then
    osascript -e 'tell application "Spotify" to playpause'
  elif [[ "$source" == "Apple Music" ]]; then
    osascript -e 'tell application "Music" to playpause'
  fi
  exit 0
fi

if [[ "${1:-}" == "next" ]]; then
  if command -v nowplaying-cli &>/dev/null; then
    nowplaying-cli nextTrack
  elif [[ "$source" == "Spotify" ]]; then
    osascript -e 'tell application "Spotify" to next track'
  elif [[ "$source" == "Apple Music" ]]; then
    osascript -e 'tell application "Music" to next track'
  fi
  exit 0
fi

if [[ "${1:-}" == "prev" ]]; then
  if command -v nowplaying-cli &>/dev/null; then
    nowplaying-cli previousTrack
  elif [[ "$source" == "Spotify" ]]; then
    osascript -e 'tell application "Spotify" to previous track'
  elif [[ "$source" == "Apple Music" ]]; then
    osascript -e 'tell application "Music" to back track'
  fi
  exit 0
fi

if [[ "${1:-}" == "open" ]]; then
  case "$source" in
    Spotify)       open -a Spotify ;;
    "Apple Music") open -a Music ;;
    Safari)        open -a Safari ;;
    Chrome)        open -a "Google Chrome" ;;
    Firefox)       open -a Firefox ;;
    Arc)           open -a Arc ;;
    *)
      if [[ "$(is_running Spotify)" == "true" ]]; then
        open -a Spotify
      else
        open -a Music
      fi
      ;;
  esac
  exit 0
fi

# --- Render menu bar ----------------------------------------------------------

# Nothing playing
if [[ -z "$title" || "$title" == "null" ]]; then
  echo ":music.note: | sfsize=14"
  echo "---"
  echo "Nothing playing | color=#888888"
  exit 0
fi

# Menu bar title
if [[ -n "$artist" && "$artist" != "null" ]]; then
  display_title=$(truncate_str "$artist - $title" $MAX_TITLE_LEN)
else
  display_title=$(truncate_str "$title" $MAX_TITLE_LEN)
fi
if [[ "$state" == "paused" ]]; then
  echo ":pause.fill: $display_title | font=Menlo sfsize=14"
else
  echo ":music.note: $display_title | font=Menlo sfsize=14"
fi

# --- Dropdown -----------------------------------------------------------------
echo "---"

# Track info
echo "$title | size=14"
[[ -n "$artist" && "$artist" != "null" ]] && echo "$artist | size=12 color=#888888"
[[ -n "$album" && "$album" != "null" ]] && echo "$album | size=11 color=#666666"

# Progress bar
if [[ -n "$duration" && -n "$position" && "$duration" != "null" && "$position" != "null" ]]; then
  dur_int=${duration%.*}
  pos_int=${position%.*}
  if (( dur_int > 0 )); then
    pos_min=$(( pos_int / 60 ))
    pos_sec=$(( pos_int % 60 ))
    dur_min=$(( dur_int / 60 ))
    dur_sec=$(( dur_int % 60 ))
    progress=$(( pos_int * 20 / dur_int ))
    bar=""
    for (( i = 0; i < 20; i++ )); do
      if (( i < progress )); then
        bar+="▓"
      else
        bar+="░"
      fi
    done
    printf -v time_line "%d:%02d / %d:%02d  %s" "$pos_min" "$pos_sec" "$dur_min" "$dur_sec" "$bar"
    echo "$time_line | font=Menlo size=11 color=#888888"
  fi
fi

echo "---"

# Playback controls
if [[ "$state" == "paused" ]]; then
  echo "Play | bash=\"$SELF\" param1=playpause terminal=false refresh=true sfimage=play.fill"
else
  echo "Pause | bash=\"$SELF\" param1=playpause terminal=false refresh=true sfimage=pause.fill"
fi
echo "Previous | bash=\"$SELF\" param1=prev terminal=false refresh=true sfimage=backward.fill"
echo "Next | bash=\"$SELF\" param1=next terminal=false refresh=true sfimage=forward.fill"

echo "---"
echo "Open $source | bash=\"$SELF\" param1=open terminal=false sfimage=arrow.up.forward.app"
echo "---"
echo "via $source | color=#888888 size=11"
