# macOS Menu Bar Apps

![Maintenance](https://img.shields.io/badge/Status-Maintenance-green)
![Languages](https://img.shields.io/badge/Languages-zsh%20%7C%20JXA-blue)

A small collection of [SwiftBar](https://github.com/swiftbar/SwiftBar) plugins for the macOS menu bar.

## Prerequisites

```sh
# Install SwiftBar
brew install --cask swiftbar

# Launch SwiftBar, then set a plugin directory when prompted (e.g. ~/swiftbar_plugins)
```

---

## SwiftBar Pomodoro Menu Bar Timer

Script: [pomodoro.1s.zsh](pomodoro.1s.zsh)

A Pomodoro timer that lives in the menu bar. Shows the current phase icon (focus / break / paused) with `MM:SS` countdown, fires a system notification at each phase transition, and exposes start / pause / skip / restart / stop controls plus duration + cycle settings from the dropdown. State persists in `/tmp/pomodoro_swiftbar.state`; settings persist in `~/.config/pomodoro_swiftbar.conf`.

```sh
# Symlink the plugin into your SwiftBar plugin directory
ln -s "$(pwd)/pomodoro.1s.zsh" ~/swiftbar_plugins/
chmod +x pomodoro.1s.zsh

# Override defaults with environment variables (optional)
export POM_WORK_MIN=25   # focus duration in minutes
export POM_BREAK_MIN=5   # break duration in minutes
export POM_CYCLES=4      # number of cycles

# CLI control (also available from the menu bar dropdown)
./pomodoro.1s.zsh start         # start a pomodoro session
./pomodoro.1s.zsh pause_resume  # toggle pause/resume
./pomodoro.1s.zsh skip          # skip to next phase
./pomodoro.1s.zsh reset         # restart from cycle 1
./pomodoro.1s.zsh stop          # stop and reset
```

---

## SwiftBar Now Playing Menu Bar Widget

Script: [now_playing.5s.zsh](now_playing.5s.zsh)

Displays the currently playing track in the menu bar with playback controls (play/pause, next, previous) and a dropdown showing title, artist, album, and a progress bar. Supports Spotify and Apple Music via AppleScript out of the box, and any audio source (browsers, Podcasts, etc.) when `nowplaying-cli` is installed.

```sh
# Symlink the plugin into your SwiftBar plugin directory
ln -s "$(pwd)/now_playing.5s.zsh" ~/swiftbar_plugins/
chmod +x now_playing.5s.zsh

# Optional: install nowplaying-cli for system-wide support (browsers, Podcasts, etc.)
brew install nowplaying-cli

# Required for the AppleScript fallback to parse track info
brew install jq

# CLI control (also available from the menu bar dropdown)
./now_playing.5s.zsh playpause   # toggle play/pause
./now_playing.5s.zsh next        # next track
./now_playing.5s.zsh prev        # previous track
./now_playing.5s.zsh open        # open the source app
```
