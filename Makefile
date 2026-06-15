.PHONY: ci
ci: solidity-fmt solidity-build solidity-test cadence-test

.PHONY: solidity-fmt
solidity-fmt:
	cd solidity && forge fmt --check

.PHONY: solidity-fmt-fix
solidity-fmt-fix:
	cd solidity && forge fmt

.PHONY: solidity-build
solidity-build:
	cd solidity && FOUNDRY_PROFILE=ci forge build --sizes

.PHONY: solidity-test
solidity-test:
	cd solidity && FOUNDRY_PROFILE=ci forge test -vvv

.PHONY: cadence-test
cadence-test:
	flow test

# ---------------------------------------------------------------------------
# Pyth oracle maintenance (Flow EVM mainnet — MANUAL ONLY)
#
# Pyth on Flow is a pull oracle: the FLOW/ETH/BTC feeds backing the Morpho
# market oracles lapse after their heartbeat (~1h) and then revert with
# StalePrice. Push a fresh Hermes update before any vault operation.
# Needs curl (forge --ffi). PRIVATE_KEY signs + pays the (tiny) update fee.
# ---------------------------------------------------------------------------
FLOW_MAINNET_RPC ?= https://mainnet.evm.nodes.onflow.org

.PHONY: mainnet-update-oracle mainnet-update-oracle-dry
mainnet-update-oracle-dry:
	cd solidity && forge script script/UpdatePythPrices.s.sol --rpc-url $(FLOW_MAINNET_RPC) --ffi --private-key $(PRIVATE_KEY)
mainnet-update-oracle:
	cd solidity && forge script script/UpdatePythPrices.s.sol --rpc-url $(FLOW_MAINNET_RPC) --ffi --broadcast --private-key $(PRIVATE_KEY)

# ---------------------------------------------------------------------------
# Security scanning (LOCAL ONLY, containerized)
#
# This repository is PUBLIC and the contracts hold real value. Security scans
# are intentionally NOT run in CI — public Actions logs, issues, PR comments,
# and artifacts would leak live vulnerabilities. Every scanner runs inside a
# locked-down Docker container (see security/docker/) so untrusted analysis —
# especially community AI skills — cannot read host files or secrets:
#   static tier -> no network at all
#   AI tier     -> egress restricted to the Anthropic API; needs a Claude
#                  credential (see Credentials in docs/security-scanning.md)
# Reports stay in security/reports/ (gitignored) and are never committed/posted.
#
# Requires Docker. Build the image once with `make security-build`.
# ---------------------------------------------------------------------------

SKILL ?= solidity-auditor

# Run all security scans (local only).
.PHONY: security
security: security-build security-static security-ai

# Build the pinned scanner toolchain image.
.PHONY: security-build
security-build:
	./security/scan.sh build

# Store your Claude Code OAuth token in the macOS Keychain (one-time, per-dev).
.PHONY: security-set-token
security-set-token:
	./security/scan.sh set-token

# Verify a Claude credential is available (preflight for the AI tier).
.PHONY: security-check-cred
security-check-cred:
	./security/scan.sh check-cred

# Run all non-AI static analyzers (sealed, no network).
.PHONY: security-static
security-static: security-slither security-aderyn security-solhint

.PHONY: security-slither
security-slither:
	./security/scan.sh slither

.PHONY: security-aderyn
security-aderyn:
	./security/scan.sh aderyn

.PHONY: security-solhint
security-solhint:
	./security/scan.sh solhint

.PHONY: security-ai
security-ai: security-check-cred security-ai-review security-ai-audit security-ai-skills security-ai-summarize

# AI reviews (need a Claude credential — see docs). Output is local + gitignored.
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
