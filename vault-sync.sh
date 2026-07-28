#!/usr/bin/env bash
# Syncs an Obsidian vault folder with a GitHub repo - either direction.
# Built for Termux on Android. Run with: bash vault-sync.sh
# Remembers the repo URL and vault path after the first run.

set -e

CONFIG_DIR="$HOME/.config/obsidian-vault-sync"
CONFIG_FILE="$CONFIG_DIR/config"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
REPO_URL="$REPO_URL"
VAULT_PATH="$VAULT_PATH"
EOF
}

ask_yes_no() {
    local prompt="$1"
    read -r -p "$prompt [Y/n] " answer
    case "$answer" in
        [Nn]*) return 1 ;;
        *) return 0 ;;
    esac
}

echo "=== Obsidian Vault Sync ==="
echo ""

# Termux has no OS-level credential manager like Windows' Git Credential Manager,
# so use git's own store (plaintext in ~/.git-credentials, private to Termux's app
# storage) so you only have to enter your GitHub username + Personal Access Token once.
if [ "$(git config --global credential.helper)" != "store" ]; then
    git config --global credential.helper store
    echo "First-time setup: git will remember your GitHub username + Personal Access Token"
    echo "in ~/.git-credentials after you enter them once on the next push/pull that needs it."
    echo "(Use a PAT, not your GitHub password - GitHub no longer accepts passwords over HTTPS.)"
    echo ""
fi
echo "What do you need?"
echo "  1) Pull - download the vault from GitHub onto this phone"
echo "  2) Push - upload the vault on this phone to GitHub"
echo ""
read -r -p "Enter 1 or 2: " CHOICE
while [ "$CHOICE" != "1" ] && [ "$CHOICE" != "2" ]; do
    read -r -p "Please enter 1 (pull) or 2 (push): " CHOICE
done

load_config

if [ -n "$REPO_URL" ]; then
    echo ""
    echo "Saved GitHub repo: $REPO_URL"
    if ! ask_yes_no "Use this repo?"; then
        read -r -p "Enter the GitHub repo URL (e.g. https://github.com/user/repo.git): " REPO_URL
    fi
else
    read -r -p "Enter the GitHub repo URL (e.g. https://github.com/user/repo.git): " REPO_URL
fi

if [ -n "$VAULT_PATH" ]; then
    echo ""
    echo "Saved vault path: $VAULT_PATH"
    if ! ask_yes_no "Use this path?"; then
        read -r -p "Enter the local vault folder path: " VAULT_PATH
    fi
else
    read -r -p "Enter the local vault folder path: " VAULT_PATH
fi

save_config

REAL_VAULT_PATH=$(realpath "$VAULT_PATH" 2>/dev/null || echo "$VAULT_PATH")
echo ""
echo "Real vault path: $REAL_VAULT_PATH"
echo "(Compare this to what Obsidian shows for this vault: tap the vault-switcher"
echo "icon top-left in Obsidian, or Settings > About > vault path. They must match"
echo "for files pulled here to actually show up in Obsidian.)"
echo ""

if [ "$CHOICE" = "1" ]; then
    # ---- PULL ----
    if [ -d "$VAULT_PATH/.git" ]; then
        echo "Pulling latest changes into $VAULT_PATH ..."
        (cd "$VAULT_PATH" && git pull)
    else
        # Folder may already contain other files - adopt it in place rather than
        # requiring an empty folder. Files with the same name as ones in the repo
        # are left alone by git (it refuses to overwrite untracked files); everything
        # else in the folder is simply left untouched alongside the pulled repo.
        mkdir -p "$VAULT_PATH"
        echo "Setting up git in $VAULT_PATH and pulling from $REPO_URL ..."
        (
            cd "$VAULT_PATH"
            git init
            git remote add origin "$REPO_URL"
            if git fetch origin; then
                REMOTE_BRANCH=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/ {sub("refs/heads/","",$2); print $2}')
                [ -z "$REMOTE_BRANCH" ] && REMOTE_BRANCH="main"
                if ! git checkout -t "origin/$REMOTE_BRANCH"; then
                    echo ""
                    echo "Some existing local files share a name with files in the repo (listed above) - git won't overwrite them automatically."
                    echo "Move/rename just those files, then run Pull again to bring in the rest."
                fi
            else
                echo "Could not reach '$REPO_URL' - check the URL and your connection."
            fi
        )
    fi
else
    # ---- PUSH ----
    (
        cd "$VAULT_PATH"
        if [ ! -d ".git" ]; then
            echo "Initializing git repo in $VAULT_PATH ..."
            git init
            git checkout -B main
            git remote add origin "$REPO_URL"
        fi

        git add -A
        if [ -n "$(git status --porcelain)" ]; then
            git commit -m "Vault sync $(date '+%Y-%m-%d %H:%M')"
        else
            echo "Nothing to commit - vault already up to date locally."
        fi

        BRANCH=$(git branch --show-current)
        [ -z "$BRANCH" ] && BRANCH="main"

        if ! git push -u origin "$BRANCH"; then
            echo ""
            echo "Push was rejected - the remote has changes you don't have locally."
            echo "Run this script again and choose Pull first, then Push."
        fi
    )
fi

echo ""
echo "Done."
