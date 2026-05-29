#!/usr/bin/env bash
#
# Containerized security-scan dispatcher. Every scanner runs inside the
# fcm-security image (see security/docker/Dockerfile) so untrusted analysis —
# especially community AI skills — executes with no access to the host
# filesystem or secrets.
#
#   Static tier (slither/aderyn/solhint): --network none, --cap-drop ALL,
#     source mounted read-only. Fully airtight.
#   AI tier (review/audit/skills/summarize): egress restricted to the Anthropic
#     API only (security/docker/init-firewall.sh), ANTHROPIC_API_KEY is the only
#     secret, source mounted read-only.
#
# All reports stay local in security/reports/ (gitignored).
#
# Usage: security/scan.sh <build|slither|aderyn|solhint|ai-review|ai-audit|ai-skills [skill]|summarize>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="fcm-security:local"
REPORTS="$ROOT/security/reports"
mkdir -p "$REPORTS"

stamp() { date +%Y%m%d-%H%M%S; }

build() {
  echo ">> Building $IMAGE"
  docker build -f "$ROOT/security/docker/Dockerfile" -t "$IMAGE" "$ROOT/security/docker"
}

ensure_image() {
  docker image inspect "$IMAGE" >/dev/null 2>&1 || build
}

# Common docker flags. Source is mounted read-only; reports dir is the only
# writable host mount.
static_run() {
  ensure_image
  docker run --rm --network none \
    --cap-drop ALL --security-opt no-new-privileges \
    -v "$ROOT:/repo:ro" -v "$REPORTS:/out" \
    --entrypoint /usr/local/bin/entry-static.sh "$IMAGE" "$@"
}

# 1Password reference for the Claude Code OAuth token. This is a path, not a
# secret, so it's safe to commit. Point it at your team's shared-vault item, or
# override per-shell with FCM_OP_TOKEN_REF.
DEFAULT_OP_REF="op://Shared/Claude Code OAuth Token/credential"

# Resolve a credential for the AI tier WITHOUT requiring a permanent env var.
# Precedence: an already-set env var wins (power users / CI); otherwise fetch the
# OAuth token from 1Password at run time. Sets CRED_ENV to the variable name to
# hand to docker — the value is passed by reference (-e NAME), never on the
# command line, so it can't leak via `ps`.
resolve_cred() {
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then CRED_ENV=CLAUDE_CODE_OAUTH_TOKEN; return; fi
  if [ -n "${ANTHROPIC_API_KEY:-}" ];     then CRED_ENV=ANTHROPIC_API_KEY;     return; fi

  local ref="${FCM_OP_TOKEN_REF:-$DEFAULT_OP_REF}"
  if ! command -v op >/dev/null 2>&1; then
    echo "error: 1Password CLI 'op' not found." >&2
    echo "       Install it, or set CLAUDE_CODE_OAUTH_TOKEN in your shell for this run." >&2
    exit 1
  fi
  if ! CLAUDE_CODE_OAUTH_TOKEN="$(op read "$ref" 2>/dev/null)" || [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "error: could not read the Claude Code OAuth token from 1Password:" >&2
    echo "         $ref" >&2
    echo "       One-time setup:" >&2
    echo "         1. Run 'claude setup-token' to mint a token." >&2
    echo "         2. Store it in 1Password at the path above (or set FCM_OP_TOKEN_REF)." >&2
    echo "         3. Make sure 'op' is signed in (the desktop app integration is easiest)." >&2
    exit 1
  fi
  export CLAUDE_CODE_OAUTH_TOKEN
  CRED_ENV=CLAUDE_CODE_OAUTH_TOKEN
}

# NET_ADMIN is required to install the egress firewall. The scan agent's tool
# allowlist excludes arbitrary Bash, so a poisoned skill cannot use it to alter
# the firewall.
ai_run() {
  ensure_image
  resolve_cred
  docker run --rm \
    --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges \
    -e "$CRED_ENV" \
    -v "$ROOT:/repo:ro" -v "$REPORTS:/out" \
    --entrypoint /usr/local/bin/entry-ai.sh "$IMAGE" "$@"
}

AI_REVIEW_TOOLS="Read,Grep,Glob,Bash(git diff:*),Bash(git status:*),Bash(git log:*),Bash(git merge-base:*),Bash(forge build:*)"
AI_SKILLS_TOOLS="Skill,Task,Read,Grep,Glob,Bash(git diff:*),Bash(git status:*),Bash(forge build:*)"

case "${1:-}" in
  build)
    build
    ;;

  slither)
    out="$REPORTS/slither-report-$(stamp).txt"
    static_run bash -c 'cd solidity && slither . --config-file slither.config.json' 2>&1 | tee "$out"
    echo ">> Saved: $out"
    ;;

  aderyn)
    name="aderyn-report-$(stamp).md"
    static_run bash -c "aderyn solidity -o /out/$name"
    echo ">> Saved: security/reports/$name"
    ;;

  solhint)
    out="$REPORTS/solhint-report-$(stamp).txt"
    static_run bash -c 'cd solidity && solhint "src/**/*.sol"' 2>&1 | tee "$out"
    echo ">> Saved: $out"
    ;;

  ai-review)
    out="$REPORTS/ai-review-$(stamp).md"
    ai_run claude -p "$(cat "$ROOT/security/prompts/review-changes.md")" \
      --allowedTools "$AI_REVIEW_TOOLS" | tee "$out"
    echo ">> Saved: $out"
    ;;

  ai-audit)
    out="$REPORTS/ai-audit-$(stamp).md"
    ai_run claude -p "$(cat "$ROOT/security/prompts/full-audit.md")" \
      --allowedTools "$AI_REVIEW_TOOLS" | tee "$out"
    echo ">> Saved: $out"
    ;;

  ai-skills)
    skill="${2:-solidity-auditor}"
    # Vendor skills on the HOST (network + SHA-pin), then mount read-only into
    # the sealed container — so the container needs no GitHub egress.
    "$ROOT/security/vendor-skills.sh"
    out="$REPORTS/skills-${skill}-$(stamp).md"
    prompt="Use the \`${skill}\` skill (from .claude/skills/) to audit this project. You MUST actually invoke the skill — do not improvise your own review instead.

$(cat "$ROOT/security/prompts/skills-audit.md")"
    ai_run claude -p "$prompt" --setting-sources project \
      --allowedTools "$AI_SKILLS_TOOLS" | tee "$out"
    echo ">> Saved: $out"
    ;;

  summarize)
    # Reads the reports (copied into the container with the source) and prints a
    # ranked index to stdout only — no file written.
    ai_run claude -p "$(cat "$ROOT/security/prompts/summarize.md")" \
      --allowedTools "Read,Grep,Glob"
    ;;

  *)
    echo "usage: security/scan.sh <build|slither|aderyn|solhint|ai-review|ai-audit|ai-skills [skill]|summarize>" >&2
    exit 2
    ;;
esac
