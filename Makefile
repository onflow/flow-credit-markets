.PHONY: ci
ci: solidity-fmt solidity-build solidity-test

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

# ---------------------------------------------------------------------------
# Mainnet deployment (Flow EVM mainnet — MANUAL ONLY, never run from CI)
#
# All deployments are deliberate, operator-driven actions against real funds.
# Every target has a *-dry variant that fork-simulates the exact transaction
# sequence against live mainnet state for free — ALWAYS dry-run first.
# Runbook: solidity/README.md#mainnet-deployment
#
# Inputs come from the environment:
#   PRIVATE_KEY   deployer key (becomes vault admin/owner on deploy)
#   SEED_AMOUNT   mainnet-seed-market: loan token base units to supply
#   MAX_TVL       mainnet-deploy: initial TVL limit (asset base units)
#   VAULT         mainnet-check: address of the deployed FCMVault
# ---------------------------------------------------------------------------

FLOW_MAINNET_RPC ?= https://mainnet.evm.nodes.onflow.org

# Read-only report: market/pool/oracle state and (optional DEPLOYER=0x...)
# account balances. Run before anything else.
.PHONY: mainnet-status
mainnet-status:
	cd solidity && forge script script/Status.s.sol --rpc-url $(FLOW_MAINNET_RPC)

# Supply loan-token liquidity to the Morpho market (one-time prerequisite).
.PHONY: mainnet-seed-market mainnet-seed-market-dry
mainnet-seed-market-dry:
	cd solidity && forge script script/SeedMarket.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-seed-market:
	cd solidity && forge script script/SeedMarket.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --private-key $(PRIVATE_KEY)

# Deploy the yield oracle (if not in deployments/mainnet.json yet) + FCMVault,
# then grant EARLY_ACCESS_ROLE and set the TVL limit.
.PHONY: mainnet-deploy mainnet-deploy-dry
mainnet-deploy-dry:
	cd solidity && forge script script/DeployVault.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-deploy:
	cd solidity && forge script script/DeployVault.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --private-key $(PRIVATE_KEY)

# Live integration check: real deposit + redeem against a deployed vault.
# Spends real funds (swap fees) — dry-run first.
.PHONY: mainnet-check mainnet-check-dry
mainnet-check-dry:
	cd solidity && forge script script/LiveCheck.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-check:
	cd solidity && forge script script/LiveCheck.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --slow --private-key $(PRIVATE_KEY)

# Offline + fork tests for the yield oracle (fork tests auto-skip without the env var).
.PHONY: mainnet-fork-test
mainnet-fork-test:
	cd solidity && FLOW_MAINNET_RPC_URL=$(FLOW_MAINNET_RPC) forge test --match-contract YieldTokenOracle -vvv

# mainnet-deploy-rebalancer: Cadence VaultRebalancer (PR #38) deployment will
# slot in here once that PR merges — it consumes the FCMVault address.

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
