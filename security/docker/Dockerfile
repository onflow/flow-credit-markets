# Security scanning toolchain — all tools pinned, solc pre-cached for offline use.
#
# Built once (`make security-build`) and reused by every scan. The static tier
# runs this image with `--network none`; the AI tier runs it with egress
# restricted to the Anthropic API only (see security/docker/init-firewall.sh).
#
# Tools are pinned to exact versions so a rebuild is reproducible and a poisoned
# upstream release can't silently change what runs.

FROM node:20-bookworm-slim

# Pinned tool versions ------------------------------------------------------
ARG SLITHER_VERSION=0.11.5
ARG SOLHINT_VERSION=6.2.1
ARG ADERYN_VERSION=0.6.8
ARG CLAUDE_VERSION=2.1.146
ARG SOLC_VERSION=0.8.35
ARG FOUNDRY_VERSION=stable

ENV DEBIAN_FRONTEND=noninteractive \
    FOUNDRY_DIR=/root/.foundry \
    PATH=/root/.foundry/bin:/opt/slither/bin:/usr/local/bin:$PATH

# Base packages: python (slither), git, curl, jq, and the firewall tooling
# (iptables/ipset/dnsutils) used only by the AI tier's egress allowlist.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq xz-utils \
        python3 python3-venv python3-pip \
        iptables ipset dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Slither (isolated venv) ---------------------------------------------------
RUN python3 -m venv /opt/slither \
    && /opt/slither/bin/pip install --no-cache-dir "slither-analyzer==${SLITHER_VERSION}"

# Solhint + Claude Code CLI (pinned) ---------------------------------------
RUN npm install -g "solhint@${SOLHINT_VERSION}" "@anthropic-ai/claude-code@${CLAUDE_VERSION}"

# Aderyn (pinned release binary, arm64 linux) ------------------------------
RUN curl -fsSL "https://github.com/Cyfrin/aderyn/releases/download/aderyn-v${ADERYN_VERSION}/aderyn-aarch64-unknown-linux-gnu.tar.xz" \
        -o /tmp/aderyn.tar.xz \
    && mkdir -p /tmp/aderyn-extract \
    && tar -xJf /tmp/aderyn.tar.xz -C /tmp/aderyn-extract \
    && install -m 0755 "$(find /tmp/aderyn-extract -type f -name aderyn | head -1)" /usr/local/bin/aderyn \
    && rm -rf /tmp/aderyn.tar.xz /tmp/aderyn-extract \
    && aderyn --version

# Foundry (forge) -----------------------------------------------------------
RUN curl -L https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup --install "${FOUNDRY_VERSION}" \
    && forge --version

# Pre-cache solc so the static tier can compile with no network. Warming a
# throwaway project forces foundry-compilers to download solc into ~/.svm,
# which Slither (via crytic-compile/forge) and Aderyn both reuse offline.
RUN mkdir -p /tmp/warm/src \
    && printf '[profile.default]\nsolc_version = "%s"\n' "${SOLC_VERSION}" > /tmp/warm/foundry.toml \
    && printf 'pragma solidity %s; contract Warm {}' "${SOLC_VERSION}" > /tmp/warm/src/Warm.sol \
    && (cd /tmp/warm && forge build) \
    && rm -rf /tmp/warm

# Make forge/slither resolvable regardless of shell/PATH handling.
RUN ln -sf /root/.foundry/bin/forge /usr/local/bin/forge \
    && ln -sf /root/.foundry/bin/cast /usr/local/bin/cast \
    && ln -sf /opt/slither/bin/slither /usr/local/bin/slither

# Entrypoints + egress firewall (copied last to keep heavy layers cached).
COPY entry-static.sh entry-ai.sh init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entry-static.sh /usr/local/bin/entry-ai.sh /usr/local/bin/init-firewall.sh

WORKDIR /work
