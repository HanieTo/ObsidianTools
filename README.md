# ObsidianTools

Scripts and a plugin for turning `.txt` files into Obsidian notes and keeping a vault synced with GitHub, on both Windows and Android. None of it needs administrator rights.

## What's here

| File | Platform | What it does |
|---|---|---|
| [`ObsidianifyNote.ps1`](ObsidianifyNote.ps1) + [`Install-SendTo.ps1`](Install-SendTo.ps1) | Windows | Right-click any `.txt` file → Send to → converts it into a formatted note in your vault |
| [`VaultSync.ps1`](VaultSync.ps1) / [`VaultSync.bat`](VaultSync.bat) | Windows | Push/pull your vault to/from GitHub |
| [`vault-sync.sh`](vault-sync.sh) | Android (Termux) | Same push/pull, for your phone |
| [`obsidianify-plugin/`](obsidianify-plugin/) | Everywhere (inside Obsidian) | The same txt→note conversion as a real Obsidian plugin, so it also works on mobile via a watched Inbox folder |

---

## On your PC (Windows)

### 1. Convert a `.txt` file into a note

One-time setup:
```
powershell -ExecutionPolicy Bypass -File Install-SendTo.ps1
```
This adds "Obsidianify Note" to your right-click **Send to** menu. Before first use, open [`ObsidianifyNote.ps1`](ObsidianifyNote.ps1) and set `$VaultPath` near the top to your vault folder.

To use: right-click one or more `.txt` files → **Send to** → **Obsidianify Note**. For each file you'll be asked to pick/type a category; it creates a formatted `.md` note and moves the original `.txt` into a `Processed` subfolder.

### 2. Sync your vault with GitHub

Double-click [`VaultSync.bat`](VaultSync.bat). It asks Pull or Push, then for a repo URL and vault path — both remembered after the first run. Pull safely adopts a non-empty folder in place (won't overwrite existing files with different names).

### 3. Install the Obsidian plugin (optional, see below)

Double-click [`obsidianify-plugin/Install-Plugin.bat`](obsidianify-plugin/Install-Plugin.bat) to copy the plugin into your vault automatically.

---

## On your phone (Android)

### 1. Sync your vault with GitHub

In Termux:
```
pkg update && pkg install git -y
git clone https://github.com/HanieTo/ObsidianTools
bash ObsidianTools/vault-sync.sh
```
(That last line runs [`vault-sync.sh`](vault-sync.sh).) Same Pull/Push prompt as Windows, with its own remembered repo URL and vault path (stored at `~/.config/obsidian-vault-sync/config`).

First push/pull will ask for a GitHub username + a **Personal Access Token** (not your password — GitHub Settings → Developer settings → Personal access tokens, `repo` scope). It's remembered after that via `credential.helper store`.

After confirming the vault path, the script prints the *real* resolved path (`realpath`) — compare that to what Obsidian's vault switcher shows on your phone to make sure they're the same folder. If they don't match, files pulled here won't show up in Obsidian.

### 2. Convert a `.txt` file into a note

This is what the **Obsidianify Inbox** plugin is for (see below) — Windows' Send-To trick doesn't exist on Android, so conversion happens inside Obsidian itself instead.

---

## The Obsidian plugin (works on every device)

[`obsidianify-plugin/`](obsidianify-plugin/) is a real Obsidian plugin — same conversion logic as [`ObsidianifyNote.ps1`](ObsidianifyNote.ps1), but runs inside Obsidian directly, so it works identically on Windows, Mac, Linux, Android, and iOS.

- Watches an `Inbox` folder in your vault.
- Drop a `.txt` there (drag-and-drop on desktop, or share-sheet on mobile) → a category picker pops up → creates the note, moves the original into `Inbox/Processed`.
- Or run **"Process Inbox folder"** from the command palette to process everything waiting in Inbox at once.

**Install on Windows:** double-click [`obsidianify-plugin/Install-Plugin.bat`](obsidianify-plugin/Install-Plugin.bat) (edit `$VaultPath` in [`Install-Plugin.ps1`](obsidianify-plugin/Install-Plugin.ps1) first if needed).

**Install on phone:** since the plugin's files live inside `.obsidian/plugins/` in the vault itself, once they're pulled down via [`vault-sync.sh`](vault-sync.sh) they're already in place — just enable the plugin in Obsidian (Settings → Community plugins → turn off Restricted mode → enable "Obsidianify Inbox"). One-time step per device.

Full details: [`obsidianify-plugin/README.md`](obsidianify-plugin/README.md).

---

## Notes

- Everything here is designed to avoid admin rights: Windows scripts run with `-ExecutionPolicy Bypass` for that one invocation only (no system policy changes), and the plugin installs entirely inside your vault folder.
- Your actual vault content (`vault-IT` on GitHub) is a **separate, private** repo from this one — this repo only holds tooling, not your notes.
- AI-assisted cleanup was tried and deliberately left out (see commit history) — a small local model wasn't reliable enough to trust with unsupervised edits to technical notes.
