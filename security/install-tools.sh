#!/usr/bin/env bash
#
# Install the tools needed to run the local security scans:
#   - foundry (forge)  — required by Slither & Aderyn to compile the project
#   - slither          — static analysis
#   - aderyn           — static analysis
#   - solhint          — linter
#   - claude           — Claude Code CLI, for the AI targets
#
# Idempotent: anything already on PATH is skipped. Failures for one tool do not
# stop the others, so re-run after fixing prerequisites (Python, Node, curl).

set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
log()  { printf '\n>> %s\n' "$*"; }
warn() { printf '\n!! %s\n' "$*" >&2; }

# --- Foundry (forge) -------------------------------------------------------
if have forge; then
  log "foundry: present — $(forge --version 2>/dev/null | head -1)"
else
  log "foundry: installing via foundryup"
  if curl -L https://foundry.paradigm.xyz | bash; then
    export PATH="$HOME/.foundry/bin:$PATH"
    "$HOME/.foundry/bin/foundryup" || foundryup || warn "foundry: run 'foundryup' after adding ~/.foundry/bin to PATH"
  else
    warn "foundry: install failed — see https://book.getfoundry.sh/getting-started/installation"
  fi
fi

# --- Slither ---------------------------------------------------------------
if have slither; then
  log "slither: present — $(slither --version 2>/dev/null | head -1)"
elif have pipx; then
  log "slither: installing via pipx"
  pipx install slither-analyzer || warn "slither: pipx install failed"
elif have pip3; then
  log "slither: installing via pip3 --user"
  pip3 install --user slither-analyzer || warn "slither: pip3 install failed"
else
  warn "slither: needs Python (install pipx or pip3), then re-run. https://github.com/crytic/slither"
fi

# --- Aderyn ----------------------------------------------------------------
if have aderyn; then
  log "aderyn: present — $(aderyn --version 2>/dev/null | head -1)"
else
  log "aderyn: installing via official installer"
  if curl --proto '=https' --tlsv1.2 -LsSf \
       https://github.com/cyfrin/aderyn/releases/latest/download/aderyn-installer.sh | bash; then
    :
  else
    warn "aderyn: install failed — see https://github.com/Cyfrin/aderyn"
  fi
fi

# --- Solhint ---------------------------------------------------------------
if have solhint; then
  log "solhint: present — $(solhint --version 2>/dev/null | head -1)"
elif have npm; then
  log "solhint: installing via npm -g"
  npm install -g solhint || warn "solhint: npm install failed (it can still run via npx)"
else
  warn "solhint: needs Node/npm — or it runs via 'npx solhint' at scan time."
fi

# --- Claude Code -----------------------------------------------------------
if have claude; then
  log "claude: present — $(claude --version 2>/dev/null | head -1)"
elif have npm; then
  log "claude: installing Claude Code via npm -g"
  npm install -g @anthropic-ai/claude-code || warn "claude: npm install failed — see https://docs.claude.com/claude-code"
else
  warn "claude: install Claude Code manually — https://docs.claude.com/claude-code"
fi

cat <<'NOTE'

>> Done. If any tool isn't found after this, add its bin dir to your PATH:
     foundry  -> $HOME/.foundry/bin
     aderyn   -> $HOME/.cyfrin/bin
     pipx     -> ensure `pipx ensurepath` has been run
   Then restart your shell and re-run: make install-tools
NOTE
