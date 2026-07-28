# Obsidianify Inbox

An Obsidian plugin that watches an **Inbox** folder inside your vault for `.txt` files and converts each one into a formatted note, with category filing. Works on desktop and mobile, since it only uses Obsidian's own vault API (no filesystem access, no external dependencies at runtime).

This is the plugin version of the Windows-only `ObsidianifyNote.ps1` script in this repo - same formatting logic (commands/IPs/paths wrapped in code, `Label:` lines become headings), but runs inside Obsidian itself so it works on every device Obsidian runs on.

## What it does

1. Watches a folder (default: `Inbox`) inside your vault.
2. When a `.txt` file appears there (dragged in on desktop, or shared in via Android/iOS's share sheet), it pops up a small dialog asking you to pick or type a **category**.
3. Creates a formatted `.md` note in `<category>/`, with frontmatter (`title`, `created`, `aliases`, `tags`, `source`, `summary`).
4. Moves the original `.txt` into `Inbox/Processed/` (nothing is ever deleted).

You can also run it manually anytime via the command palette (`Process Inbox folder`) or the ribbon icon, which processes every `.txt` currently sitting in the Inbox folder.

## Installing

**Manual install (any platform):** copy `manifest.json` and `main.js` from this folder into `<your vault>/.obsidian/plugins/obsidianify-inbox/` inside your vault, then in Obsidian go to Settings → Community plugins → enable "Obsidianify Inbox". If your vault syncs (via `vault-IT`/git, or any other sync), that folder will show up on your other devices too - just enable the plugin there as well.

**Mobile:** use a file manager app to place the two files into `.obsidian/plugins/obsidianify-inbox/` inside the vault folder, or push them there via git sync from desktop first (they're tracked in this repo) and let your existing vault sync bring them to your phone.

## Building from source

Requires Node.js.

```
npm install
npm run build
```

This produces `main.js`. `npm run dev` runs an incremental watch build while developing.

## Syncing your vault (git)

This plugin only handles the txt-to-note conversion. For pushing/pulling your vault to GitHub, use the [Obsidian Git](https://github.com/denolehov/obsidian-git) community plugin instead - it's mature, cross-platform (including mobile), and already solves that well rather than reinventing it here.
