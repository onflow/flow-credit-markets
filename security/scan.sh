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

require_key() {
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "error: the AI tier needs an API key. Set ANTHROPIC_API_KEY and re-run." >&2
    echo "       (The static tier — slither/aderyn/solhint — needs no key.)" >&2
    exit 1
  fi
}

# NET_ADMIN is required to install the egress firewall. The scan agent's tool
# allowlist excludes arbitrary Bash, so a poisoned skill cannot use it to alter
# the firewall.
ai_run() {
  ensure_image
  require_key
  docker run --rm \
    --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges \
    -e ANTHROPIC_API_KEY \
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
