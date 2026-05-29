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
# Security scanning (LOCAL ONLY)
#
# This repository is PUBLIC and the contracts hold real value. Security scans
# are intentionally NOT run in CI — public Actions logs, issues, PR comments,
# and artifacts would leak live vulnerabilities. Run these locally; reports go
# to security/reports/ (gitignored) and are never committed or posted.
#
# Static tools require local installs:
#   slither  -> pipx install slither-analyzer   (https://github.com/crytic/slither)
#   aderyn   -> curl -L https://github.com/cyfrin/aderyn/releases/latest/download/aderyn-installer.sh | bash
#   solhint  -> run via npx (no install needed)
# AI tools require the Claude Code CLI (`claude`).
# ---------------------------------------------------------------------------

SKILL ?= solidity-auditor

# Install all tools needed for the security scans (idempotent).
.PHONY: install-tools
install-tools:
	./security/install-tools.sh

# Run all non-AI static analyzers.
.PHONY: security
security: security-slither security-aderyn security-solhint

.PHONY: security-slither
security-slither:
	mkdir -p security/reports
	cd solidity && slither . --config-file slither.config.json 2>&1 | tee ../security/reports/slither-report.txt

.PHONY: security-aderyn
security-aderyn:
	mkdir -p security/reports
	aderyn solidity -o security/reports/aderyn-report.md
	@echo "Report: security/reports/aderyn-report.md"

.PHONY: security-solhint
security-solhint:
	cd solidity && npx --yes solhint 'src/**/*.sol'

# AI reviews (Claude Code). Output is local + gitignored.
.PHONY: security-ai-review
security-ai-review:
	./security/run-ai.sh security/prompts/review-changes.md ai-review

.PHONY: security-ai-audit
security-ai-audit:
	./security/run-ai.sh security/prompts/full-audit.md ai-audit

# Skills-based audit. Override the skill: `make security-ai-skills SKILL=scv-scan`
.PHONY: security-ai-skills
security-ai-skills:
	./security/run-skills.sh $(SKILL)
