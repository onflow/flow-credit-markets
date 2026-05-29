#!/usr/bin/env bash
#
# Summarize all local scanner findings: reads every report in security/reports/,
# de-dupes across tools, ranks by severity, and prints a one-line-per-finding
# index to STDOUT. Writes nothing — output is terminal-only by design.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
reports_dir="$root/security/reports"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found. Install Claude Code: https://docs.claude.com/claude-code" >&2
  exit 1
fi

if [ -z "$(ls -A "$reports_dir" 2>/dev/null)" ]; then
  echo "No reports in security/reports/. Run a scan first, e.g. 'make security' or 'make security-ai-audit'." >&2
  exit 1
fi

# Read-only: no writes, no gh, no git.
( cd "$root" && claude -p "$(cat "$root/security/prompts/summarize.md")" \
    --allowedTools "Read,Grep,Glob" )
