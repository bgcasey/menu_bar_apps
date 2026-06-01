' run_hidden.vbs
' Launches write_stats.ps1 with NO visible window, so the per-minute scheduled
' task doesn't flash a console. Have Task Scheduler run this via wscript.exe
' instead of calling powershell.exe directly — wscript allocates no console, and
' it starts PowerShell already hidden (the "0" below), so nothing flashes.
'
' Finds write_stats.ps1 in its own folder, so it stays portable inside Dropbox.

Dim shell, fso, scriptDir, ps1
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\write_stats.ps1"

Set shell = CreateObject("WScript.Shell")
' 0 = hidden window, False = don't wait for it to finish
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """", 0, False
