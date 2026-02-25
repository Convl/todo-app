#!/bin/sh
# Loads the project-scoped GitHub token from .devcontainer/.env
# and exports it so git-askpass.sh can use it.

ENV_FILE=/workspace/.devcontainer/.env

if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi

. "$ENV_FILE"

# Set git identity (host gitconfig is no longer copied in).
if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    exit 0
fi

# Remove any credential helpers that VS Code copies from the host's
# .gitconfig. Credential helpers take precedence over GIT_ASKPASS,
# so they must be cleared for our repo-scoped token to be used.
git config --global --unset-all credential.helper 2>/dev/null || true

# Make GITHUB_TOKEN available to all shell sessions so git-askpass.sh
# (pointed to by GIT_ASKPASS) can echo it when git needs credentials.
BASHRC=/home/devuser/.bashrc
if ! grep -q 'GITHUB_TOKEN' "$BASHRC" 2>/dev/null; then
    echo "export GITHUB_TOKEN=$GITHUB_TOKEN" >> "$BASHRC"
fi
