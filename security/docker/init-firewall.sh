#!/usr/bin/env bash
#
# Egress allowlist for the AI tier: permit ONLY DNS + HTTPS to the Anthropic API,
# default-drop everything else. Requires NET_ADMIN. Run once at container start.
#
# The scan agent cannot run arbitrary shell (its tool allowlist excludes Bash
# beyond git/forge), so a poisoned skill cannot undo these rules from inside the
# agent. This caps exfiltration: even if a skill tries to phone home, there is no
# route off-box except to api.anthropic.com.

set -euo pipefail

iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Loopback
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Established/related return traffic
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS (needed to resolve the API host)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow HTTPS only to the resolved Anthropic API IPs
allow_host() {
  local host="$1" ip
  for ip in $(getent ahostsv4 "$host" | awk '{print $1}' | sort -u); do
    iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
    echo "  allow $host -> $ip:443"
  done
}

echo ">> egress firewall: allowing api.anthropic.com only"
allow_host api.anthropic.com

# Reject (not silently drop) any other egress so a blocked connection fails fast
# instead of hanging on a timeout. The policy DROP above remains a backstop.
iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

echo ">> egress firewall active (api.anthropic.com only; others rejected)"
