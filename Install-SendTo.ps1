<#
  One-time setup: adds "Obsidianify Note" to the right-click "Send to" menu.
  Only touches your own user profile (Send To is per-user) - no admin rights needed.
#>

$scriptPath = Join-Path $PSScriptRoot "ObsidianifyNote.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Could not find ObsidianifyNote.ps1 next to this installer."
}

$sendToDir = Join-Path $env:APPDATA "Microsoft\Windows\SendTo"
$shortcutPath = Join-Path $sendToDir "Obsidianify Note.lnk"

$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Save()

Write-Host "Installed: right-click any .txt file -> Send to -> 'Obsidianify Note'"
Write-Host "Remember to set `$VaultPath inside ObsidianifyNote.ps1 before using it."
