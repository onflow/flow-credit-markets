#!/usr/bin/env bash
#
# Entrypoint for the static tier. The host source is mounted read-only at /repo;
# copy it into a writable workdir so Foundry/Slither/Aderyn can compile without
# touching the host, then run the requested command. No network is available.

set -euo pipefail

cp -a --no-preserve=ownership /repo/. /work/
cd /work
forge build
exec "$@"
