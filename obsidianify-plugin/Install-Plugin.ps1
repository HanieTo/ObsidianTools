<#
  Installs (or updates) the Obsidianify Inbox plugin into your vault's
  .obsidian/plugins folder, and creates the Inbox folder if missing.
  Runs entirely under your own user account - no admin rights required.
#>

# ---- EDIT THIS if your vault is elsewhere ----
$VaultPath = "D:\vault\IT"
# -----------------------------------------------

$PluginId = "obsidianify-inbox"
$scriptDir = $PSScriptRoot

if (-not (Test-Path -LiteralPath $VaultPath)) {
    Write-Host "Vault path not found: $VaultPath" -ForegroundColor Red
    Write-Host "Edit `$VaultPath at the top of Install-Plugin.ps1 to point at your vault." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit
}

$manifestPath = Join-Path $scriptDir "manifest.json"
$mainJsPath = Join-Path $scriptDir "main.js"

if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $mainJsPath)) {
    Write-Host "manifest.json / main.js not found next to this script." -ForegroundColor Red
    Write-Host "Run 'npm run build' first, or make sure this script is still in the obsidianify-plugin folder." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit
}

$pluginDir = Join-Path $VaultPath ".obsidian\plugins\$PluginId"
if (-not (Test-Path -LiteralPath $pluginDir)) {
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
}

Copy-Item -LiteralPath $manifestPath -Destination $pluginDir -Force
Copy-Item -LiteralPath $mainJsPath -Destination $pluginDir -Force
Write-Host "Copied manifest.json and main.js into:"
Write-Host "  $pluginDir"

$inboxPath = Join-Path $VaultPath "Inbox"
if (-not (Test-Path -LiteralPath $inboxPath)) {
    New-Item -ItemType Directory -Path $inboxPath | Out-Null
    Write-Host "Created Inbox folder: $inboxPath"
} else {
    Write-Host "Inbox folder already exists: $inboxPath"
}

Write-Host ""
Write-Host "Done. Next steps in Obsidian:" -ForegroundColor Green
Write-Host "  1. Settings -> Community plugins -> make sure Restricted mode is off"
Write-Host "  2. Find 'Obsidianify Inbox' in the list and enable it"
Write-Host "  3. Drop a .txt file into the Inbox folder to try it"
Write-Host ""
Read-Host "Press Enter to close"
