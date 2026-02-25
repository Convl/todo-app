 0. Set up ENABLE_FIREWALL in devcontainer.json
 
 1. System packages (apt) / runtimes / CLI tools → Dockerfile

  Add apt-get install lines (or curl-based installers like nvm, pyenv, etc.) to the Dockerfile. This is the right place for things like Python, Node.js, Go, ripgrep, etc.

  RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip nodejs npm \
      && rm -rf /var/lib/apt/lists/*

  2. VS Code extensions → customizations.vscode.extensions in devcontainer.json

  Already shown in your config. Add extension IDs (from the marketplace) here:

  "extensions": [
    "anthropic.claude-code",
    "ms-python.python",
    "dbaeumer.vscode-eslint"
  ]

  3. Project-level dependencies (npm, pip, etc.) → postStartCommand or a dedicated setup script

  You can chain commands in postStartCommand, or better, add a postCreateCommand to run once after the container is built:

  "postCreateCommand": "npm install"
  // or: "pip install -r requirements.txt"

  ---
  Key distinction:

  ┌──────────────────────────────────┬─────────────────────────────────┬─────────────────────────────────────────────┐
  │              Where               │          When it runs           │                   Use for                   │
  ├──────────────────────────────────┼─────────────────────────────────┼─────────────────────────────────────────────┤
  │ Dockerfile                       │ Image build (once, cached)      │ OS packages, language runtimes, global CLIs │
  ├──────────────────────────────────┼─────────────────────────────────┼─────────────────────────────────────────────┤
  │ postCreateCommand                │ After container creation (once) │ Project deps (npm install, pip install)     │
  ├──────────────────────────────────┼─────────────────────────────────┼─────────────────────────────────────────────┤
  │ postStartCommand                 │ Every container start           │ Init scripts (firewall, env setup)          │
  ├──────────────────────────────────┼─────────────────────────────────┼─────────────────────────────────────────────┤
  │ customizations.vscode.extensions │ Container creation              │ VS Code extensions                          │
  └──────────────────────────────────┴─────────────────────────────────┴─────────────────────────────────────────────┘

  After editing the Dockerfile or devcontainer.json, you need to Rebuild Container (VS Code command palette: Dev Containers: Rebuild Container) for changes to take effect.