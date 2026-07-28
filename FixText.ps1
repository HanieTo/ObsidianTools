<#
  Standalone document cleanup via OpenRouter's API - no Obsidian plugin needed.
  Drag a .txt file onto FixText.bat (or run it and type a path), pick a saved
  prompt (or add a new one), and get a "-fixed" copy written next to it.
  The original file is never modified. API key and prompts are stored locally
  (outside this repo) and never shared anywhere except with OpenRouter.
#>

param(
    [Parameter(Position = 0)]
    [string]$FilePath
)

# Windows PowerShell 5.1's console defaults to a non-Unicode codepage, which
# mangles non-ASCII input/output (e.g. Persian) unless overridden like this.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# ---- Change the model here if you want a different free one ----
$Model = "openai/gpt-oss-20b:free"
# -------------------------------------------------------------------

$configDir     = Join-Path $env:APPDATA "ObsidianTools"
$keyPath       = Join-Path $configDir "openrouter-key.txt"
$promptsPath   = Join-Path $configDir "fixtext-prompts.json"

if (-not (Test-Path -LiteralPath $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# ---- API key ----
if (-not (Test-Path -LiteralPath $keyPath)) {
    Write-Host "No API key saved yet." -ForegroundColor Yellow
    $key = Read-Host "Paste your OpenRouter API key (stored locally in $keyPath, never sent anywhere except OpenRouter)"
    Set-Content -LiteralPath $keyPath -Value $key.Trim() -NoNewline
}
$apiKey = (Get-Content -LiteralPath $keyPath -Raw).Trim()

# ---- Prompt library ----
# Stored as {"prompts": [...]} rather than a bare top-level JSON array.
# ConvertFrom-Json's array-vs-single-object return type for a bare array is
# genuinely inconsistent across element counts and re-wrapping attempts (
# verified directly - not just theory). A named property holding the array
# doesn't have that ambiguity: it's a property value, not pipeline output,
# so it isn't subject to the same auto-unwrap/enumerate behavior.
function Load-Prompts {
    if (Test-Path -LiteralPath $promptsPath) {
        try {
            $data = Get-Content -LiteralPath $promptsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $data.prompts) { return ,@() }
            return ,@($data.prompts)
        } catch { return ,@() }
    }
    return ,@()
}

function Save-Prompts([array]$Prompts) {
    @{ prompts = $Prompts } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $promptsPath -Encoding UTF8
}

function Read-NewPrompt {
    $name = Read-Host "Name for this prompt (e.g. 'Fix typos', 'Translate to English')"
    $text = Read-Host "The instruction itself (e.g. 'Fix only obvious spelling/typo errors, do not change meaning')"
    return [PSCustomObject]@{ name = $name; text = $text }
}

$prompts = Load-Prompts

Write-Host ""
if ($prompts.Count -eq 0) {
    Write-Host "No saved prompts yet - let's add your first one." -ForegroundColor Cyan
    $chosen = Read-NewPrompt
    $prompts = @($chosen)
    Save-Prompts -Prompts $prompts
}
else {
    Write-Host "Saved prompts:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $prompts.Count; $i++) {
        Write-Host "  $($i + 1)) $($prompts[$i].name)"
    }
    Write-Host "  N) New prompt..."
    $choice = Read-Host "Pick a number, or N for a new prompt"

    if ($choice -match '^[Nn]$') {
        $chosen = Read-NewPrompt
        $prompts += $chosen
        Save-Prompts -Prompts $prompts
    }
    else {
        $index = [int]$choice - 1
        if ($index -lt 0 -or $index -ge $prompts.Count) {
            Write-Host "Invalid choice." -ForegroundColor Red
            Read-Host "Press Enter to close"
            exit
        }
        $chosen = $prompts[$index]
    }
}

# ---- File to process ----
if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $FilePath = Read-Host "Path to the .txt file to fix"
}
$FilePath = $FilePath.Trim('"')

if (-not (Test-Path -LiteralPath $FilePath)) {
    Write-Host "File not found: $FilePath" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit
}

$content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8

$instruction = "$($chosen.text)`n`nPreserve any lines that look like shell commands, file paths, IP addresses, or URLs exactly as-is, character for character - do not rewrite or `"fix`" those. Keep every part of the document in its original language - do not translate anything, even if some lines are in a different language than others (mixed-language documents must stay mixed-language). Return only the resulting document text, nothing else (no commentary, no preamble).`n`nDOCUMENT:`n$content"

$body = @{
    model    = $Model
    messages = @(
        @{ role = "user"; content = $instruction }
    )
} | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Sending to OpenRouter ($Model) using prompt '$($chosen.name)'..." -ForegroundColor Cyan

try {
    # Invoke-RestMethod on Windows PowerShell 5.1 mis-detects the response
    # encoding as Latin-1 for APIs that don't send an explicit response
    # charset, corrupting any non-ASCII text (e.g. Persian) it returns. Using
    # Invoke-WebRequest and decoding the raw bytes as UTF8 ourselves avoids
    # that entirely. The request body is UTF8-encoded explicitly for the
    # same reason, on the way out.
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $webResponse = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" `
        -Method Post `
        -Headers @{ Authorization = "Bearer $apiKey" } `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes `
        -TimeoutSec 120 `
        -UseBasicParsing

    $jsonText = [System.Text.Encoding]::UTF8.GetString($webResponse.RawContentStream.ToArray())
    $response = $jsonText | ConvertFrom-Json

    $result = $response.choices[0].message.content.Trim()

    $dir  = Split-Path -Path $FilePath -Parent
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $ext  = [System.IO.Path]::GetExtension($FilePath)
    $outPath = Join-Path $dir "$name-fixed$ext"
    $i = 2
    while (Test-Path -LiteralPath $outPath) {
        $outPath = Join-Path $dir "$name-fixed ($i)$ext"
        $i++
    }
    Set-Content -LiteralPath $outPath -Value $result -Encoding UTF8

    Write-Host ""
    Write-Host "=== Result ===" -ForegroundColor Green
    Write-Host $result
    Write-Host ""
    Write-Host "Written to: $outPath" -ForegroundColor Green
    Write-Host "(Original file left untouched.)" -ForegroundColor Green

    Set-Clipboard -Value $result
    Write-Host "(Also copied to clipboard.)" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If this mentions 401/403, your API key may be wrong or revoked - delete $keyPath and run this again to re-enter it." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to close"
