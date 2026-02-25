FROM ubuntu:24.04

ARG TZ=UTC
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=${TZ}

# Runtime dependencies:
#   curl, ca-certificates  – for Claude Code install script and HTTPS
#   sudo                   – devuser needs to run the firewall script as root
#   iproute2               – firewall (init-firewall.sh)
#   dnsutils               – dig, used by init-firewall.sh to resolve allowed domains
#   aggregate              – collapses overlapping CIDR blocks (used for GitHub IP ranges)
#   jq                     – JSON parsing in init-firewall.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        sudo \
        iptables \
        ipset \
        iproute2 \
        dnsutils \
        aggregate \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash devuser \
    && printf '%s\n' \
        "devuser ALL=(root) NOPASSWD: SETENV: /usr/local/bin/init-firewall.sh" \
        "devuser ALL=(root) NOPASSWD: /usr/local/bin/fix-workspace.sh" \
        > /etc/sudoers.d/devuser \
    && chmod 0440 /etc/sudoers.d/devuser \
    && mkdir -p /commandhistory \
    && chown devuser /commandhistory

# Persist bash history in the /commandhistory volume (mounted via devcontainer.json).
# PROMPT_COMMAND flushes each command immediately so history survives crashes.
RUN echo 'export HISTFILE=/commandhistory/.bash_history' >> /home/devuser/.bashrc \
    && echo 'export PROMPT_COMMAND="history -a"' >> /home/devuser/.bashrc \
    && echo 'parse_git_branch() { local b; b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && echo " ($b)"; }' >> /home/devuser/.bashrc \
    && echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\]\$ "' >> /home/devuser/.bashrc

# Install scripts as root so devuser cannot modify them.
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY setup-credentials.sh /usr/local/bin/setup-credentials.sh
COPY git-askpass.sh /usr/local/bin/git-askpass.sh
RUN printf '#!/bin/sh\nchown -R devuser:devuser /workspace\ngit config --system --unset-all credential.helper 2>/dev/null || true\n' \
        > /usr/local/bin/fix-workspace.sh \
    && chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/fix-workspace.sh \
                /usr/local/bin/setup-credentials.sh /usr/local/bin/git-askpass.sh


# Everything below runs as devuser.
USER devuser

# The Claude Code install script drops the binary into ~/.local/bin.
ENV PATH="/home/devuser/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /workspace
