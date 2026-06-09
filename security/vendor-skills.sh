#!/usr/bin/env bash
#
# Vendor community Solidity-audit skills into .claude/skills/ (gitignored),
# PINNED to specific reviewed commit SHAs.
#
# Why pinned: these are third-party, community-writable repos whose contents are
# loaded as instructions into a tool-enabled agent. A floating branch would let a
# poisoned upstream commit run on a developer's machine the next time they scan.
# Pinning to a content-addressed SHA means we only ever run what we reviewed; if
# a SHA is rewritten away, the checkout fails closed.
#
# To bump a skill: review the upstream diff, then update the SHA below.
#
#   pashov/skills            -> solidity-auditor, x-ray
#   auditmos/skills          -> all
#   CDSecurity/cdsecurity    -> audit-prep
#   kadenzipfel/scv-scan     -> scv-scan

set -euo pipefail

# --- Pinned, reviewed commits (update only after reviewing the upstream diff) ---
PASHOV_SHA=749903d4a068477344739f9bb3346ca35a06be60
AUDITMOS_SHA=c958b3abb0ce189d9f39a05caf94b5a5da655010
CDSECURITY_SHA=930cc41bf0baa36d46e7d49f7e9db20226869ddf
SCVSCAN_SHA=114985581450cfed35c277831a065c6478e2c328

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/.claude/skills"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Clone a repo and check out an exact pinned commit. Fails closed if the commit
# is no longer reachable (history rewrite / repo takeover).
fetch_pinned() {
  local url="$1" name="$2" sha="$3"
  git clone -q --filter=blob:none "$url" "$tmp/$name"
  if ! ( cd "$tmp/$name" && git checkout -q "$sha" ); then
    echo "ERROR: pinned commit $sha not found in $url — refusing to vendor." >&2
    echo "       Upstream history may have changed. Review before updating the SHA." >&2
    exit 1
  fi
}

echo ">> Vendoring audit skills (pinned) into $dest (gitignored)"
rm -rf "$dest"
mkdir -p "$dest"

fetch_pinned https://github.com/pashov/skills            pashov     "$PASHOV_SHA"
fetch_pinned https://github.com/auditmos/skills          auditmos   "$AUDITMOS_SHA"
fetch_pinned https://github.com/CDSecurity/cdsecurity-skills cdsecurity "$CDSECURITY_SHA"
fetch_pinned https://github.com/kadenzipfel/scv-scan      scv-scan   "$SCVSCAN_SHA"

cp -R "$tmp/pashov/solidity-auditor" "$dest/solidity-auditor"
cp -R "$tmp/pashov/x-ray"            "$dest/x-ray"
cp -R "$tmp/cdsecurity/audit-prep"   "$dest/audit-prep"
mkdir -p "$dest/scv-scan"
cp -R "$tmp/scv-scan/SKILL.md" "$tmp/scv-scan/references" "$dest/scv-scan/"
cp -R "$tmp/auditmos/skills/"* "$dest/"

# Strip any Claude settings/permission files shipped by upstream skills. We
# control permissions via the scan's --allowedTools; a stray acceptEdits/Edit
# settings file from a third-party repo must not live in our skills tree.
# (Security-review finding: auditmos ships such a settings.local.json.)
find "$dest" -name 'settings*.json' -type f -delete

echo ">> Vendored skills (pinned):"
ls -1 "$dest"
