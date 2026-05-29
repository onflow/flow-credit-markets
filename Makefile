.PHONY: ci
ci: solidity-fmt solidity-build solidity-test

.PHONY: solidity-fmt
solidity-fmt:
	cd solidity && forge fmt --check

.PHONY: solidity-build
solidity-build:
	cd solidity && FOUNDRY_PROFILE=ci forge build --sizes

.PHONY: solidity-test
solidity-test:
	cd solidity && FOUNDRY_PROFILE=ci forge test -vvv

# ---------------------------------------------------------------------------
# Security scanning (LOCAL ONLY, containerized)
#
# This repository is PUBLIC and the contracts hold real value. Security scans
# are intentionally NOT run in CI — public Actions logs, issues, PR comments,
# and artifacts would leak live vulnerabilities. Every scanner runs inside a
# locked-down Docker container (see security/docker/) so untrusted analysis —
# especially community AI skills — cannot read host files or secrets:
#   static tier -> no network at all
#   AI tier     -> egress restricted to the Anthropic API; needs ANTHROPIC_API_KEY
# Reports stay in security/reports/ (gitignored) and are never committed/posted.
#
# Requires Docker. Build the image once with `make security-build`.
# ---------------------------------------------------------------------------

SKILL ?= solidity-auditor

# Build the pinned scanner toolchain image.
.PHONY: security-build
security-build:
	./security/scan.sh build

# Run all non-AI static analyzers (sealed, no network).
.PHONY: security
security: security-slither security-aderyn security-solhint

.PHONY: security-slither
security-slither:
	./security/scan.sh slither

.PHONY: security-aderyn
security-aderyn:
	./security/scan.sh aderyn

.PHONY: security-solhint
security-solhint:
	./security/scan.sh solhint

# AI reviews (needs ANTHROPIC_API_KEY). Output is local + gitignored.
.PHONY: security-ai-review
security-ai-review:
	./security/scan.sh ai-review

.PHONY: security-ai-audit
security-ai-audit:
	./security/scan.sh ai-audit

# Skills-based audit. Override the skill: `make security-ai-skills SKILL=scv-scan`
.PHONY: security-ai-skills
security-ai-skills:
	./security/scan.sh ai-skills $(SKILL)

# Summarize all reports in security/reports/ by severity (stdout only).
.PHONY: security-ai-summarize
security-ai-summarize:
	./security/scan.sh summarize
