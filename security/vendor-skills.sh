#!/usr/bin/env bash
#
# Vendor community Solidity-audit skills into .claude/skills/ (gitignored).
# Re-run any time to refresh. This directory is managed by these scripts; it is
# wiped and rebuilt on each run, so do not put hand-written skills here.
#
# Skills (per the Continuous Security Testing recommendation):
#   pashov/skills:            solidity-auditor, x-ray
#   CDSecurity/cdsecurity:    audit-prep
#   kadenzipfel/scv-scan:     scv-scan
#   auditmos/skills:          (all)

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/.claude/skills"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo ">> Vendoring audit skills into $dest (gitignored)"
rm -rf "$dest"
mkdir -p "$dest"

git clone --depth 1 -q https://github.com/pashov/skills "$tmp/pashov"
git clone --depth 1 -q https://github.com/auditmos/skills "$tmp/auditmos"
git clone --depth 1 -q https://github.com/CDSecurity/cdsecurity-skills "$tmp/cdsecurity"
git clone --depth 1 -q https://github.com/kadenzipfel/scv-scan "$tmp/scv-scan"

cp -R "$tmp/pashov/solidity-auditor" "$dest/solidity-auditor"
cp -R "$tmp/pashov/x-ray"            "$dest/x-ray"
cp -R "$tmp/cdsecurity/audit-prep"   "$dest/audit-prep"
mkdir -p "$dest/scv-scan"
cp -R "$tmp/scv-scan/SKILL.md" "$tmp/scv-scan/references" "$dest/scv-scan/"
cp -R "$tmp/auditmos/skills/"* "$dest/"

echo ">> Vendored skills:"
ls -1 "$dest"
