# write_stats.ps1
# Samples this PC's CPU + memory and writes a one-line stats file NEXT TO ITSELF,
# for the macOS SwiftBar "Remote PC Stats" widget (remote_stats.30s.zsh) to read.
# Because this script lives in the Dropbox-synced repo folder, the .dat it writes
# syncs straight to the mac. No admin rights and no inbound network connection
# required — the data is pushed out via Dropbox.
#
# Output file: <this script's folder>\<COMPUTERNAME>.dat
# Output line: cpuPct;memPct;usedGB;totalGB;epochSeconds;hostname
#
# --- One-time setup on this Windows PC ---------------------------------------
# 1. Make sure Dropbox is installed and signed in to the SAME account as the mac,
#    so this repo's `remote_stats` folder is synced here. Note the script's full
#    path, e.g.  %USERPROFILE%\Dropbox\3_resources\menu_bar_apps\remote_stats\write_stats.ps1
#    (adjust to wherever your Dropbox keeps this repo).
# 2. Register a per-user scheduled task that runs it every minute (NO admin needed).
#    Launch it through run_hidden.vbs (in this folder) via wscript so no console
#    window flashes each minute. Point at the .vbs in step 1's folder:
#
#      schtasks /create /tn "Dropbox PC Stats" /sc minute /mo 1 /f /ru "%USERNAME%" /it ^
#        /tr "wscript \"%USERPROFILE%\Dropbox\3_resources\menu_bar_apps\remote_stats\run_hidden.vbs\""
#
#    /ru "%USERNAME%" runs it as your account (use DOMAIN\user for a specific
#    account); /it uses an interactive token so it runs while that user is logged
#    on without a stored password. Run it in a normal (non-admin) Command Prompt.
#    To sample less often, change "/mo 1" to "/mo 2" (every 2 minutes), etc.
#
# 3. Check it: run the task once and confirm the .dat appears beside this script —
#      schtasks /run /tn "Dropbox PC Stats"
#
#    Remove later with:  schtasks /delete /tn "Dropbox PC Stats" /f
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'SilentlyContinue'

# Write the .dat next to this script (which is inside the Dropbox-synced repo).
$dir = $PSScriptRoot
if (-not $dir) { $dir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$out = Join-Path $dir ("{0}.dat" -f $env:COMPUTERNAME)

$os  = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
if (-not $cpu) { $cpu = 0 }

$totalKB = [double]$os.TotalVisibleMemorySize
$freeKB  = [double]$os.FreePhysicalMemory
$usedKB  = $totalKB - $freeKB
$pct     = [math]::Round($usedKB / $totalKB * 100)
$usedGB  = [math]::Round($usedKB / 1MB, 1)
$totalGB = [math]::Round($totalKB / 1MB, 1)
# True UTC epoch. (Get-Date -UFormat %s on Windows PowerShell uses LOCAL time,
# which makes readings look hours stale to the mac — use UtcNow instead.)
$epoch   = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$line = "{0};{1};{2};{3};{4};{5}" -f [math]::Round($cpu), $pct, $usedGB, $totalGB, $epoch, $env:COMPUTERNAME

# Write atomically-ish: temp file then move, so the mac never reads a half line.
$tmp = "$out.tmp"
Set-Content -Path $tmp -Value $line -Encoding ASCII
Move-Item -Path $tmp -Destination $out -Force
