#!/bin/bash
# Firewall initialisation for the Claude Code sandbox.
#
# Strategy: default-deny everything, then whitelist only the services that
# Claude Code and general development actually need. The container is given
# NET_ADMIN + NET_RAW capabilities (see devcontainer.json) so it can manage
# its own iptables rules without affecting the host.
#
# Allowed outbound traffic:
#   • DNS (UDP 53)           – name resolution
#   • SSH (TCP 22)           – git over SSH
#   • api.anthropic.com      – Claude API
#   • statsig.anthropic.com,
#     statsig.com            – Claude Code feature flags / telemetry
#   • sentry.io              – Claude Code error reporting
#   • github.com (full range)– git, gh CLI
#   • registry.npmjs.org     – npm
#   • Host network           – so VS Code / your terminal can reach the container
#   • VS Code marketplace    – extension install/update (remove if not using VS Code)

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# 0. Remove ::1 from /etc/hosts so that "localhost" resolves to 127.0.0.1 only.
#
#    Claude Code's OAuth callback server calls getaddrinfo("localhost") and
#    binds to whichever address comes back first. In Ubuntu containers,
#    /etc/hosts maps both 127.0.0.1 and ::1 to "localhost", and the IPv6
#    entry is typically first — so the server ends up on [::1]:PORT.
#    VS Code port forwarding connects via IPv4 (127.0.0.1) and never reaches
#    it. Setting NODE_OPTIONS=--dns-result-order=ipv4first has no effect
#    because Claude Code ships a bundled Node.js binary that ignores it.
#    Removing the ::1 entry fixes the problem at the C library level, which
#    all Node.js runtimes (bundled or not) use under the hood.
#    See: https://github.com/anthropics/claude-code/issues/9376
# ---------------------------------------------------------------------------
grep -v '^::1' /etc/hosts > /tmp/hosts.tmp && cat /tmp/hosts.tmp > /etc/hosts && rm /tmp/hosts.tmp

if [ "${ENABLE_FIREWALL:-true}" != "true" ]; then
    echo "Firewall disabled (ENABLE_FIREWALL=${ENABLE_FIREWALL:-unset}). Skipping."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Capture Docker's internal DNS NAT rules before we flush everything.
#    Docker sets up a rule to redirect container DNS to 127.0.0.11; we must
#    restore it or name resolution breaks completely.
# ---------------------------------------------------------------------------
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush all existing rules and ipsets so we start from a clean slate.
# Reset default policies to ACCEPT first — flushing rules does NOT reset policies,
# so if this script previously set DROP and is now re-running, outbound traffic
# (e.g. the curl to fetch GitHub ranges below) would otherwise be blocked.
iptables -P INPUT   ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT  ACCEPT
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Restore Docker's DNS redirect so the container can resolve names.
# ---------------------------------------------------------------------------
if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT     2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

# ---------------------------------------------------------------------------
# 3. Base rules: DNS, SSH, loopback.
# ---------------------------------------------------------------------------
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---------------------------------------------------------------------------
# 4. Build the allowlist ipset.
# ---------------------------------------------------------------------------
ipset create allowed-domains hash:net

# GitHub – fetch their published IP ranges and aggregate overlapping CIDRs.
echo "Fetching GitHub IP ranges..."
gh_meta=$(curl -s https://api.github.com/meta)
[ -z "$gh_meta" ] && { echo "ERROR: could not fetch GitHub meta"; exit 1; }
echo "$gh_meta" | jq -e '.web and .api and .git' >/dev/null \
    || { echo "ERROR: unexpected GitHub meta format"; exit 1; }

while read -r cidr; do
    [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] \
        || { echo "ERROR: invalid CIDR from GitHub meta: $cidr"; exit 1; }
    ipset add -exist allowed-domains "$cidr"
done < <(echo "$gh_meta" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# All other allowed domains – resolve at startup and add their current IPs.
# Note: IP addresses can change; if a domain starts failing after weeks of
# uptime, rebuild the container to refresh the resolved addresses.
ALLOWED_DOMAINS=(
    "api.anthropic.com"          # Claude API
    "claude.ai"                  # Claude Code OAuth authorization server
    "platform.claude.com"        # Claude Code OAuth token exchange
    "statsig.anthropic.com"      # Claude Code feature flags
    "statsig.com"                # Claude Code feature flags (CDN)
    "sentry.io"                  # Claude Code error reporting
    "registry.npmjs.org"         # npm
    # VS Code extension marketplace – remove these three if you don't use VS Code.
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    [ -z "$ips" ] && { echo "ERROR: could not resolve $domain"; exit 1; }
    while read -r ip; do
        [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
            || { echo "ERROR: invalid IP for $domain: $ip"; exit 1; }
        ipset add -exist allowed-domains "$ip"
    done <<< "$ips"
done

# ---------------------------------------------------------------------------
# 5. Allow traffic to/from the Docker host network (VS Code, terminal, etc.).
# ---------------------------------------------------------------------------
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
[ -z "$HOST_IP" ] && { echo "ERROR: could not detect host IP"; exit 1; }
HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
echo "Host network: $HOST_NETWORK"
iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# ---------------------------------------------------------------------------
# 6. Apply default-deny policies and allow established + whitelisted traffic.
# ---------------------------------------------------------------------------
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ---------------------------------------------------------------------------
# 7. Verify: arbitrary internet should be blocked, GitHub API should work.
# ---------------------------------------------------------------------------
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: firewall verification failed – example.com is reachable"
    exit 1
fi
echo "OK: example.com is blocked"

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: firewall verification failed – api.github.com is not reachable"
    exit 1
fi
echo "OK: api.github.com is reachable"

echo "Firewall ready."

# ---------------------------------------------------------------------------
# 8. Stream blocked-connection entries to a readable log file.
#    /dev/kmsg is the kernel message ring; we filter for our prefix and write
#    to a file that devuser (and VS Code) can read without root.
# ---------------------------------------------------------------------------
FIREWALL_LOG=/var/log/firewall-blocked.log
touch "$FIREWALL_LOG"
chmod 644 "$FIREWALL_LOG"
# Run in background, detached from this script's process group so it survives
# after postStartCommand exits.
(grep --line-buffered "FW_BLOCKED:" /dev/kmsg >> "$FIREWALL_LOG") &
disown $!
