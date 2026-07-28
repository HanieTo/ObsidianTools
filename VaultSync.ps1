<#
  Syncs an Obsidian vault folder with a GitHub repo - either direction.
  Run by right-clicking this file -> "Run with PowerShell", or from a terminal.
  Remembers the repo URL and vault path after the first run.
#>

$configDir  = Join-Path $env:APPDATA "ObsidianTools"
$configPath = Join-Path $configDir "vault-sync-config.json"

function Load-Config {
    if (Test-Path -LiteralPath $configPath) {
        try { return Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config([string]$RepoUrl, [string]$VaultPath) {
    if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }
    @{ RepoUrl = $RepoUrl; VaultPath = $VaultPath } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Read-YesNo([string]$Prompt) {
    $answer = Read-Host "$Prompt [Y/n]"
    return ($answer -eq "" -or $answer -match '^[Yy]')
}

Write-Host "=== Obsidian Vault Sync ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "What do you need?"
Write-Host "  1) Pull - download the vault from GitHub into your Windows vault folder"
Write-Host "  2) Push - upload your local vault to GitHub"
Write-Host ""
$choice = Read-Host "Enter 1 or 2"
while ($choice -ne "1" -and $choice -ne "2") {
    $choice = Read-Host "Please enter 1 (pull) or 2 (push)"
}

$config = Load-Config

if ($config -and $config.RepoUrl) {
    Write-Host ""
    Write-Host "Saved GitHub repo: $($config.RepoUrl)"
    if (Read-YesNo "Use this repo?") {
        $repoUrl = $config.RepoUrl
    } else {
        $repoUrl = Read-Host "Enter the GitHub repo URL (e.g. https://github.com/user/repo.git)"
    }
} else {
    $repoUrl = Read-Host "Enter the GitHub repo URL (e.g. https://github.com/user/repo.git)"
}

if ($config -and $config.VaultPath) {
    Write-Host ""
    Write-Host "Saved vault path: $($config.VaultPath)"
    if (Read-YesNo "Use this path?") {
        $vaultPath = $config.VaultPath
    } else {
        $vaultPath = Read-Host "Enter the local vault folder path"
    }
} else {
    $vaultPath = Read-Host "Enter the local vault folder path"
}

Save-Config -RepoUrl $repoUrl -VaultPath $vaultPath
Write-Host ""

if ($choice -eq "1") {
    # ---- PULL ----
    $gitDir = Join-Path $vaultPath ".git"
    if (Test-Path -LiteralPath $gitDir) {
        Write-Host "Pulling latest changes into $vaultPath ..."
        Push-Location $vaultPath
        git pull
        Pop-Location
    }
    else {
        # Folder may already contain other files - adopt it in place rather than
        # requiring an empty folder. Files with the same name as ones in the repo
        # are left alone by git (it refuses to overwrite untracked files); everything
        # else in the folder is simply left untouched alongside the pulled repo.
        if (-not (Test-Path -LiteralPath $vaultPath)) { New-Item -ItemType Directory -Path $vaultPath | Out-Null }

        Write-Host "Setting up git in $vaultPath and pulling from $repoUrl ..."
        Push-Location $vaultPath
        git init
        git remote add origin $repoUrl | Out-Null
        git fetch origin

        if ($LASTEXITCODE -eq 0) {
            $branchInfo = git ls-remote --symref origin HEAD 2>$null | Select-String 'refs/heads/(\S+)'
            $remoteBranch = if ($branchInfo) { $branchInfo.Matches[0].Groups[1].Value } else { "main" }

            git checkout -t "origin/$remoteBranch"
            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                Write-Host "Some existing local files share a name with files in the repo (listed above) - git won't overwrite them automatically." -ForegroundColor Yellow
                Write-Host "Move/rename just those files, then run Pull again to bring in the rest." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Could not reach '$repoUrl' - check the URL and your connection." -ForegroundColor Yellow
        }

        Pop-Location
    }
}
else {
    # ---- PUSH ----
    Push-Location $vaultPath
    if (-not (Test-Path -LiteralPath ".git")) {
        Write-Host "Initializing git repo in $vaultPath ..."
        git init
        git checkout -B main
        git remote add origin $repoUrl
    }

    git add -A
    $status = git status --porcelain
    if ($status) {
        $msg = "Vault sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        git commit -m $msg
    } else {
        Write-Host "Nothing to commit - vault already up to date locally."
    }

    $branch = git branch --show-current
    if (-not $branch) { $branch = "main" }

    git push -u origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Push was rejected - the remote has changes you don't have locally." -ForegroundColor Yellow
        Write-Host "Run this script again and choose Pull first, then Push." -ForegroundColor Yellow
    }

    Pop-Location
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Read-Host "Press Enter to close"
