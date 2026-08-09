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

# Keychain item that holds this developer's personal Claude Code OAuth token.
KEYCHAIN_SERVICE="fcm-security-claude-token"

# Resolve a credential for the AI tier WITHOUT requiring a permanent env var.
# The Claude Code OAuth token is PER-DEVELOPER, so it lives in each dev's own
# store, not a shared one. Precedence (highest first):
#   1. CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY env  (power users / CI)
#   2. 1Password, only if FCM_OP_TOKEN_REF points at the dev's own item
#   3. macOS Keychain  (default — set once via `make security-set-token`)
# Sets CRED_ENV to the variable name handed to docker; the value is passed by
# reference (-e NAME), never on the command line, so it can't leak via `ps`.
resolve_cred() {
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo ">> credential: CLAUDE_CODE_OAUTH_TOKEN from environment" >&2
    CRED_ENV=CLAUDE_CODE_OAUTH_TOKEN; return
  fi
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo ">> credential: ANTHROPIC_API_KEY from environment" >&2
    CRED_ENV=ANTHROPIC_API_KEY; return
  fi

  # Opt-in: 1Password, only when a reference is configured.
  if [ -n "${FCM_OP_TOKEN_REF:-}" ]; then
    command -v op >/dev/null 2>&1 || { echo "error: FCM_OP_TOKEN_REF is set but 'op' (1Password CLI) is not installed." >&2; exit 1; }
    if CLAUDE_CODE_OAUTH_TOKEN="$(op read "$FCM_OP_TOKEN_REF" 2>/dev/null)" && [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
      echo ">> credential: Claude token from 1Password ($FCM_OP_TOKEN_REF)" >&2
      export CLAUDE_CODE_OAUTH_TOKEN; CRED_ENV=CLAUDE_CODE_OAUTH_TOKEN; return
    fi
    echo "error: could not read the Claude token from 1Password at: $FCM_OP_TOKEN_REF" >&2
    echo "       Is 'op' signed in, and does the item exist at that path?" >&2
    exit 1
  fi

  # Default: macOS Keychain (per-developer, no shared infra).
  if command -v security >/dev/null 2>&1; then
    if CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null)" && [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
      echo ">> credential: Claude token from macOS Keychain" >&2
      export CLAUDE_CODE_OAUTH_TOKEN; CRED_ENV=CLAUDE_CODE_OAUTH_TOKEN; return
    fi
  fi

  cat >&2 <<EOF

================================================================================
  No Claude credential found — the AI scans can't run yet.

  One-time setup (stores YOUR token in the macOS login Keychain, encrypted):
    1. claude setup-token        # mint a long-lived token tied to your account
    2. make security-set-token   # paste it once when prompted

  Then re-run your scan. (The static scans — make security-static — need no
  credential and work right now.)

  Alternatives instead of the Keychain:
    - export CLAUDE_CODE_OAUTH_TOKEN=...                             (this shell / CI)
    - export FCM_OP_TOKEN_REF='op://<your-vault>/<item>/credential'  (1Password)
================================================================================
EOF
  exit 1
}

# NET_ADMIN is required to install the egress firewall. The scan agent's tool
# allowlist excludes arbitrary Bash, so a poisoned skill cannot use it to alter
# the firewall.
ai_run() {
  resolve_cred   # check the credential FIRST, before any (slow) image build
  ensure_image
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

  check-cred)
    resolve_cred
    echo ">> Credential OK — the AI tier is ready."
    ;;

  set-token)
    command -v security >/dev/null 2>&1 || { echo "error: macOS 'security' not found (this helper is macOS-only; use CLAUDE_CODE_OAUTH_TOKEN or FCM_OP_TOKEN_REF instead)." >&2; exit 1; }
    echo "Mint a token with 'claude setup-token', then paste it at the prompt (input hidden)."
    # -w with no value prompts interactively, so the token never appears in argv.
    security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -w
    echo "Stored in your login Keychain (service: $KEYCHAIN_SERVICE)."
    ;;

  slither)
    # --fail-medium mirrors the CI gate (.github/workflows/security-static.yml):
    # exit non-zero on Medium-or-higher-impact findings. Low/Informational
    # findings are still written to the report for review but do not fail.
    # Suppress a false positive inline (no baseline DB): put
    #   // slither-disable-next-line <detector>
    # on the line above the flagged statement (detector id = the name printed
    # in the report, e.g. unused-return).
    out="$REPORTS/slither-report-$(stamp).txt"
    static_run bash -c 'cd solidity && slither . --config-file slither.config.json --fail-medium' 2>&1 | tee "$out"
    echo ">> Saved: $out"
    ;;

  aderyn)
    name="aderyn-report-$(stamp).md"
    static_run bash -c "aderyn solidity -o /out/$name"
    echo ">> Saved: security/reports/$name"
    ;;

  solhint)
    out="$REPORTS/solhint-report-$(stamp).txt"
    static_run bash -c 'cd solidity && solhint "src/**/*.sol" "!src/interfaces/external/**"' 2>&1 | tee "$out"

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
    echo "usage: security/scan.sh <build|set-token|check-cred|slither|aderyn|solhint|ai-review|ai-audit|ai-skills [skill]|summarize>" >&2
    exit 2
    ;;
esac
