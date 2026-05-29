#!/usr/bin/env bash
#
# Local AI security review runner.
#
# Runs Claude Code headlessly against a prompt file and keeps ALL output LOCAL:
# the report is written only to security/reports/ (gitignored) and printed to
# your terminal. Nothing is posted to GitHub. This is deliberate — the repo is
# public and the contracts hold real value.
#
# Usage: security/run-ai.sh <prompt-file> <report-name>

set -euo pipefail

prompt_file="${1:?usage: run-ai.sh <prompt-file> <report-name>}"
report_name="${2:?usage: run-ai.sh <prompt-file> <report-name>}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
reports_dir="$root/security/reports"
mkdir -p "$reports_dir"
out="$reports_dir/${report_name}-$(date +%Y%m%d-%H%M%S).md"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found. Install Claude Code: https://docs.claude.com/claude-code" >&2
  echo "       Or run the prompt manually from: $prompt_file" >&2
  exit 1
fi

echo ">> AI security review: $report_name"
echo ">> Working dir: $root   (read-only tools; nothing is pushed or posted)"
echo ">> Output (local, gitignored): $out"
echo

# Read-only allowlist: no gh, no git write, no file writes, no network posts.
( cd "$root" && claude -p "$(cat "$prompt_file")" \
    --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git status:*),Bash(git log:*),Bash(git merge-base:*),Bash(forge build:*),Bash(forge inspect:*)" \
) | tee "$out"

echo
echo ">> Saved local report: $out"
echo ">> Reminder: do NOT commit or share this file; it may describe live vulnerabilities."
