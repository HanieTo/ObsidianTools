<#
  Standalone text cleanup via OpenRouter's API - no Obsidian plugin needed.
  Paste text in, get typo-fixed text back. Your API key is stored locally
  (outside this repo) the first time you run it, never shared anywhere.
#>

# ---- Change the model here if you want a different free one ----
$Model = "openai/gpt-oss-20b:free"
# -------------------------------------------------------------------

$configDir  = Join-Path $env:APPDATA "ObsidianTools"
$configPath = Join-Path $configDir "openrouter-key.txt"

if (-not (Test-Path -LiteralPath $configPath)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Write-Host "No API key saved yet." -ForegroundColor Yellow
    $key = Read-Host "Paste your OpenRouter API key (stored locally in $configPath, never sent anywhere except OpenRouter)"
    Set-Content -LiteralPath $configPath -Value $key.Trim() -NoNewline
}
$apiKey = (Get-Content -LiteralPath $configPath -Raw).Trim()

Write-Host ""
Write-Host "Paste the text you want cleaned up, then press Ctrl+Z and Enter when done:" -ForegroundColor Cyan
$lines = New-Object System.Collections.Generic.List[string]
while ($true) {
    $line = Read-Host
    if ($null -eq $line) { break }
    $lines.Add($line)
}
$text = $lines -join "`n"

if ($text.Trim() -eq "") {
    Write-Host "No text entered - nothing to do." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit
}

$prompt = "Fix only obvious spelling/typo errors in the following text. Do not change its meaning, do not translate it, do not add commentary or notes. Return only the corrected text, nothing else.`n`nTEXT:`n$text"

$body = @{
    model    = $Model
    messages = @(
        @{ role = "user"; content = $prompt }
    )
} | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Sending to OpenRouter ($Model)..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" `
        -Method Post `
        -Headers @{ Authorization = "Bearer $apiKey" } `
        -ContentType "application/json" `
        -Body $body `
        -TimeoutSec 60

    $result = $response.choices[0].message.content.Trim()

    Write-Host ""
    Write-Host "=== Fixed text ===" -ForegroundColor Green
    Write-Host $result
    Write-Host ""

    Set-Clipboard -Value $result
    Write-Host "(Copied to clipboard.)" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If this mentions 401/403, your API key may be wrong or revoked - delete $configPath and run this again to re-enter it." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to close"
