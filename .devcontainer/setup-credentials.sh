#!/bin/sh
# Configures git and gh CLI to use the project-scoped GitHub token
# from .devcontainer/.env. Overrides VS Code's credential forwarding
# for github.com to enforce single-repo access.

ENV_FILE=/workspace/.devcontainer/.env

if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi

. "$ENV_FILE"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    exit 0
fi

# Host-specific credential config takes precedence over VS Code's
# generic credential.helper forwarding.
git config --global --unset-all credential.https://github.com.helper 2>/dev/null || true
git config --global credential.https://github.com.helper \
    "!f() { test \"\$1\" = get && echo username=x-access-token && echo password=$GITHUB_TOKEN; }; f"
