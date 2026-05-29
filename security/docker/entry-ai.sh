#!/usr/bin/env bash
#
# Entrypoint for the AI tier. Brings up the egress allowlist (api.anthropic.com
# only), then copies the read-only source into a writable workdir and runs the
# requested command. The only secret in the container is ANTHROPIC_API_KEY, and
# the only reachable network destination is the Anthropic API.

set -euo pipefail

# Set NO_FIREWALL=1 only for local debugging — never in normal use.
if [ "${SECURITY_NO_FIREWALL:-0}" != "1" ]; then
  /usr/local/bin/init-firewall.sh
fi

cp -a /repo/. /work/
cd /work
exec "$@"
