#!/usr/bin/env bash
#
# Entrypoint for the AI tier. Brings up the egress allowlist (api.anthropic.com
# only), then copies the read-only source into a writable workdir and runs the
# requested command. The only secret in the container is the Claude credential
# (CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY), and the only reachable network
# destination is the Anthropic API.

set -euo pipefail

# Set NO_FIREWALL=1 only for local debugging — never in normal use.
if [ "${SECURITY_NO_FIREWALL:-0}" != "1" ]; then
  /usr/local/bin/init-firewall.sh
fi

# Keep Claude's traffic to the Anthropic API only. Without this, it would attempt
# telemetry / auto-update / error-reporting calls that the egress allowlist
# blocks, stalling the run on connection timeouts.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_AUTOUPDATER=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_BUG_COMMAND=1

cp -a --no-preserve=ownership /repo/. /work/
cd /work

# Heads-up on stderr (not stdout, so it stays out of the saved report). Claude in
# headless mode prints nothing until it finishes.
echo ">> Scan running in a sealed container. Claude produces no output until it" >&2
echo "   finishes — this is normal and may take a couple of minutes. Please wait." >&2

exec "$@"
