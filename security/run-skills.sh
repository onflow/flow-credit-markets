#!/usr/bin/env bash
#
# Local skills-based AI audit. Vendors community audit skills (gitignored) and
# runs the chosen one against the codebase. ALL output stays local — written to
# security/reports/ (gitignored) and your terminal. Nothing is posted to GitHub.
#
# Usage: security/run-skills.sh [skill-name]
#   skill-name defaults to solidity-auditor.
#   Options: solidity-auditor | x-ray | audit-prep | scv-scan | <auditmos skill>

set -euo pipefail

skill="${1:-solidity-auditor}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found. Install Claude Code: https://docs.claude.com/claude-code" >&2
  exit 1
fi

"$root/security/vendor-skills.sh"

reports_dir="$root/security/reports"
mkdir -p "$reports_dir"
out="$reports_dir/skills-${skill}-$(date +%Y%m%d-%H%M%S).md"

prompt="Use the \`${skill}\` skill (from .claude/skills/) to audit this project. You MUST actually invoke the skill — do not improvise your own review instead.

$(cat "$root/security/prompts/skills-audit.md")"

echo
echo ">> Skills audit with: $skill"
echo ">> Output (local, gitignored): $out"
echo

( cd "$root" && claude -p "$prompt" \
    --setting-sources project \
    --allowedTools "Skill,Task,Read,Grep,Glob,Bash(git diff:*),Bash(git status:*),Bash(forge build:*)" \
) | tee "$out"

echo
echo ">> Saved local report: $out"
echo ">> Reminder: do NOT commit or share this file; it may describe live vulnerabilities."
