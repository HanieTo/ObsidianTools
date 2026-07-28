<#
  Send-to handler: converts one or more .txt files into Markdown notes in your Obsidian vault,
  then moves each original .txt into a "Processed" subfolder next to it.
  Runs entirely under your own user account - no admin rights required.
#>

param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$FilePaths
)

# ---- EDIT THIS before first use ----
# Path to your Obsidian vault (or a specific folder inside it, e.g. an "Inbox" folder).
$VaultPath = "D:\vault\IT"
# -------------------------------------

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

function Show-Message([string]$Text, [string]$Title, [System.Windows.Forms.MessageBoxIcon]$Icon) {
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

function Get-SafeFileName([string]$Name) {
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('-') } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Trim()
}

function Get-UniquePath([string]$Directory, [string]$BaseName, [string]$Extension) {
    $candidate = Join-Path $Directory "$BaseName$Extension"
    $i = 2
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $Directory "$BaseName ($i)$Extension"
        $i++
    }
    return $candidate
}

function Show-CategoryPicker([string]$VaultPath, [string]$PromptText) {
    $existingCategories = @()
    if (Test-Path -LiteralPath $VaultPath) {
        $existingCategories = Get-ChildItem -LiteralPath $VaultPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "Processed" -and -not $_.Name.StartsWith(".") } |
            Select-Object -ExpandProperty Name | Sort-Object
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Choose a category"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(380, 130)
    $form.Topmost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $PromptText
    $label.AutoSize = $true
    $label.MaximumSize = New-Object System.Drawing.Size(356, 0)
    $label.Location = New-Object System.Drawing.Point(12, 15)
    $form.Controls.Add($label)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(12, 55)
    $combo.Width = 350
    $combo.DropDownStyle = "DropDown"
    foreach ($c in $existingCategories) { [void]$combo.Items.Add($c) }
    $form.Controls.Add($combo)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(206, 90)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Skip this file"
    $cancelButton.Location = New-Object System.Drawing.Point(287, 90)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $combo.Text.Trim()
    }
    return $null
}

# Heuristic reformatting: wraps commands/IPs/paths in code, turns "Label:" lines
# into "## Label" sub-headings. Best-effort only - always check the result.
function Format-NoteBody([string]$Content) {
    $ipRegex      = '^(\d{1,3}\.){3}\d{1,3}$'
    $domainRegex  = '^[A-Za-z0-9][A-Za-z0-9.\-]*\.[A-Za-z]{2,}$'
    $pathRegex    = '^(/[^\s]+|[A-Za-z]:\\[^\s]+)$'
    $promptRegex  = '^[\w.\-]+@[\w.\-]+:\S*[#$]'
    $commandWords = 'zmprov|grep|ssh|mount|ls|touch|dmesg|bash|openssl|curl|git|npm|docker|sudo|cd|cat|chmod|chown|systemctl|journalctl|ping|traceroute|nslookup|dig|yum|apt-get|apt|netstat|ss|ip|ifconfig|tail|head|vim|nano|ps|kill|df|du|tar|scp|rsync|wget|python3?|pip3?|vssadmin|powershell|reg|sc|tasklist|taskkill|iptables|firewall-cmd'
    $commandRegex = "^($commandWords)\b"
    $labelRegex   = '^(.{1,60}):$'

    $blocks = [regex]::Split($Content.Trim(), '(?:\r?\n){2,}')
    $renderedBlocks = New-Object System.Collections.Generic.List[string]

    foreach ($block in $blocks) {
        $lines = $block -split '\r?\n'
        $outLines = New-Object System.Collections.Generic.List[string]
        $codeBuffer = New-Object System.Collections.Generic.List[string]

        foreach ($line in $lines) {
            $trimmed = $line.Trim()

            if ($trimmed -eq '') {
                if ($codeBuffer.Count -gt 0) {
                    $outLines.Add('```'); $outLines.AddRange($codeBuffer); $outLines.Add('```')
                    $codeBuffer.Clear()
                }
                $outLines.Add('')
                continue
            }

            if ($trimmed -match $labelRegex -and $trimmed -notmatch $commandRegex) {
                if ($codeBuffer.Count -gt 0) {
                    $outLines.Add('```'); $outLines.AddRange($codeBuffer); $outLines.Add('```')
                    $codeBuffer.Clear()
                }
                $outLines.Add("## $($Matches[1].Trim())")
                continue
            }

            if ($trimmed -match $commandRegex -or $trimmed -match $promptRegex) {
                $codeBuffer.Add($trimmed)
                continue
            }

            if ($codeBuffer.Count -gt 0) {
                $outLines.Add('```'); $outLines.AddRange($codeBuffer); $outLines.Add('```')
                $codeBuffer.Clear()
            }

            if ($trimmed -match $ipRegex -or $trimmed -match $domainRegex -or $trimmed -match $pathRegex) {
                $outLines.Add('`' + $trimmed + '`')
            } else {
                $outLines.Add($trimmed)
            }
        }

        if ($codeBuffer.Count -gt 0) {
            $outLines.Add('```'); $outLines.AddRange($codeBuffer); $outLines.Add('```')
        }

        $renderedBlocks.Add(($outLines -join "`n"))
    }

    return ($renderedBlocks -join "`n`n")
}

# Converts a single .txt file into a vault note under $Category (or vault root if blank).
# Returns the created note path. Throws on failure.
function Convert-TxtFile([string]$FilePath, [string]$VaultPath, [string]$Category) {
    $destDir = $VaultPath
    $tagsLine = "tags: []"
    if ($Category -ne "") {
        $safeCategory = Get-SafeFileName $Category
        $destDir = Join-Path $VaultPath $safeCategory
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir | Out-Null
        }
        $tagsLine = "tags: [$safeCategory]"
    }

    $sourceItem = Get-Item -LiteralPath $FilePath
    $rawTitle   = [System.IO.Path]::GetFileNameWithoutExtension($sourceItem.Name)
    $safeTitle  = Get-SafeFileName $rawTitle
    # Explicit UTF8 read - without this, PowerShell 5.1 guesses the encoding
    # from the system codepage and mangles non-ASCII text (e.g. Persian).
    $content    = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
    $created    = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $body       = Format-NoteBody -Content $content

    $frontmatter = @"
---
title: "$rawTitle"
created: $created
aliases: []
$tagsLine
source: "$($sourceItem.Name)"
summary: ""
---

# $rawTitle

---

"@

    $destPath = Get-UniquePath -Directory $destDir -BaseName $safeTitle -Extension ".md"
    Set-Content -LiteralPath $destPath -Value ($frontmatter + $body) -Encoding UTF8

    # Move the original .txt into a "Processed" subfolder next to it
    $processedDir = Join-Path $sourceItem.DirectoryName "Processed"
    if (-not (Test-Path -LiteralPath $processedDir)) {
        New-Item -ItemType Directory -Path $processedDir | Out-Null
    }
    $processedDest = Get-UniquePath -Directory $processedDir -BaseName $safeTitle -Extension ".txt"
    Move-Item -LiteralPath $FilePath -Destination $processedDest

    return $destPath
}

# ---- Main ----

if ($VaultPath -eq "C:\PUT-YOUR-VAULT-PATH-HERE" -or -not (Test-Path -LiteralPath $VaultPath)) {
    Show-Message "Obsidian vault path is not set up yet. Open ObsidianifyNote.ps1 and set `$VaultPath` to your vault folder." "Obsidianify: Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

$total = $FilePaths.Count
$created = @()
$skipped = @()
$failed  = @()

for ($i = 0; $i -lt $total; $i++) {
    $filePath = $FilePaths[$i]
    $displayName = Split-Path -Path $filePath -Leaf

    if (-not (Test-Path -LiteralPath $filePath)) {
        $failed += "$displayName (file not found)"
        continue
    }

    $promptText = "File $($i + 1) of $total`: $displayName`n`nSelect an existing category or type a new one:"
    $category = Show-CategoryPicker -VaultPath $VaultPath -PromptText $promptText
    if ($null -eq $category) {
        $skipped += $displayName
        continue
    }

    try {
        $destPath = Convert-TxtFile -FilePath $filePath -VaultPath $VaultPath -Category $category
        $created += $destPath
    }
    catch {
        $failed += "$displayName ($($_.Exception.Message))"
    }
}

$summaryLines = @()
if ($created.Count -gt 0) { $summaryLines += "Created ($($created.Count)):"; $summaryLines += ($created | ForEach-Object { "  $_" }) }
if ($skipped.Count -gt 0) { $summaryLines += ""; $summaryLines += "Skipped ($($skipped.Count)):"; $summaryLines += ($skipped | ForEach-Object { "  $_" }) }
if ($failed.Count -gt 0)  { $summaryLines += ""; $summaryLines += "Failed ($($failed.Count)):"; $summaryLines += ($failed | ForEach-Object { "  $_" }) }

$icon = if ($failed.Count -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
Show-Message ($summaryLines -join "`n") "Obsidianify: Done" $icon
