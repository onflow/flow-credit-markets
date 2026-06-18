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
# Needs curl (forge --ffi). ACCOUNT signs + pays the (tiny) update fee.
# ---------------------------------------------------------------------------
FLOW_MAINNET_RPC ?= https://mainnet.evm.nodes.onflow.org

.PHONY: mainnet-update-oracle mainnet-update-oracle-dry
mainnet-update-oracle-dry:
	cd solidity && forge script script/UpdatePythPrices.s.sol --rpc-url $(FLOW_MAINNET_RPC) --ffi --account $(ACCOUNT)
mainnet-update-oracle:
	cd solidity && forge script script/UpdatePythPrices.s.sol --rpc-url $(FLOW_MAINNET_RPC) --ffi --broadcast --account $(ACCOUNT)

# ---------------------------------------------------------------------------
# Mainnet deployment (Flow EVM mainnet)
#
# All deployments are deliberate, operator-driven actions against real funds.
# Every target has a *-dry variant that fork-simulates the exact transaction
# sequence against live mainnet state.
#
# The signer is a Foundry encrypted keystore account. Set it up once with
# `make setup-evm-deployer`, then pass its name via ACCOUNT (default: flow-evm-deployer).
#
# Inputs come from the environment:
#   ACCOUNT       keystore account name to sign with (becomes vault admin/owner
#                 on deploy); default flow-evm-deployer
#   SEED_AMOUNT   mainnet-seed-market: loan token base units to supply
#   MAX_TVL       mainnet-deploy / mainnet-set-max-tvl: TVL limit (asset base units)
#   VAULT         mainnet-check / mainnet-set-max-tvl / mainnet-grant-access / mainnet-rebalance: FCMVault address
#   EARLY_ACCESS_GRANTEES  mainnet-grant-access: comma-separated addrs to allow-list
#   SWAP_AMOUNT   mainnet-swap-weth: FLOW wei to convert (default: half balance)
#   SLIPPAGE_BPS  mainnet-swap-weth: max swap slippage in bps (default 300)
#   FORCE         mainnet-rebalance: rebalance even inside the dead band (default false)
# ---------------------------------------------------------------------------

FLOW_MAINNET_RPC ?= https://mainnet.evm.nodes.onflow.org
ACCOUNT ?= flow-evm-deployer

# Import the EVM deployer key into Foundry's encrypted keystore (one-time,
# per-dev). Prompts for the raw key and a password to encrypt it under
# ~/.foundry/keystores/$(ACCOUNT). All mainnet-* targets sign via this account.
.PHONY: setup-evm-deployer
setup-evm-deployer:
	cast wallet import $(ACCOUNT) --interactive

# Read-only report: market/pool/oracle state and (optional DEPLOYER=0x...)
# account balances. Run before anything else.
.PHONY: mainnet-status
mainnet-status:
	cd solidity && forge script script/Status.s.sol --rpc-url $(FLOW_MAINNET_RPC)

# Supply loan-token liquidity to the Morpho market (one-time prerequisite).
.PHONY: mainnet-seed-market mainnet-seed-market-dry
mainnet-seed-market-dry:
	cd solidity && forge script script/SeedMarket.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-seed-market:
	cd solidity && forge script script/SeedMarket.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Deploy the yield oracle (if not in deployments/mainnet.json yet) + FCMVault,
# then grant EARLY_ACCESS_ROLE and set the TVL limit.
.PHONY: mainnet-deploy mainnet-deploy-dry
mainnet-deploy-dry:
	cd solidity && forge script script/DeployVault.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-deploy:
	cd solidity && forge script script/DeployVault.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Update a deployed vault's TVL limit (e.g. raise from 0 to open deposits).
.PHONY: mainnet-set-max-tvl mainnet-set-max-tvl-dry
mainnet-set-max-tvl-dry:
	cd solidity && forge script script/SetMaxTvl.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-set-max-tvl:
	cd solidity && forge script script/SetMaxTvl.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Allow-list accounts on a deployed vault (grant EARLY_ACCESS_ROLE so they can
# deposit/hold/receive shares). Re-runnable; already-listed addresses skipped.
.PHONY: mainnet-grant-access mainnet-grant-access-dry
mainnet-grant-access-dry:
	cd solidity && forge script script/GrantEarlyAccess.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-grant-access:
	cd solidity && forge script script/GrantEarlyAccess.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Acquire WETH (vault collateral) for the deployer by wrapping native FLOW and
# swapping WFLOW -> WETH on FlowSwap V3. Fund the deployer before mainnet-check.
.PHONY: mainnet-swap-weth mainnet-swap-weth-dry
mainnet-swap-weth-dry:
	cd solidity && forge script script/SwapForWeth.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-swap-weth:
	cd solidity && forge script script/SwapForWeth.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Rebalance a deployed vault's leveraged position back toward its target health
# factor (permissionless). FORCE=true rebalances even when HF is inside the
# dead band. Push a fresh oracle update (mainnet-update-oracle) first.
.PHONY: mainnet-rebalance mainnet-rebalance-dry
mainnet-rebalance-dry:
	cd solidity && forge script script/Rebalance.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-rebalance:
	cd solidity && forge script script/Rebalance.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --account $(ACCOUNT)

# Live integration check: real deposit + redeem against a deployed vault.
# Spends real funds (swap fees) — dry-run first.
.PHONY: mainnet-check mainnet-check-dry
mainnet-check-dry:
	cd solidity && forge script script/LiveCheck.s.sol --rpc-url $(FLOW_MAINNET_RPC) --account $(ACCOUNT)
mainnet-check:
	cd solidity && forge script script/LiveCheck.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --slow --account $(ACCOUNT)

# Offline + fork tests for the yield oracle (fork tests auto-skip without the env var).
.PHONY: mainnet-fork-test
mainnet-fork-test:
	cd solidity && FLOW_MAINNET_RPC_URL=$(FLOW_MAINNET_RPC) forge test --match-contract YieldTokenOracle -vvv

# Full deployment rehearsal on an anvil fork of mainnet: seed -> deploy ->
# live check, with state carried between steps, against real Morpho/FlowSwap/
# Pyth contracts. Zero real funds; needs no signer/ACCOUNT. Run before any real
# deployment. Details: solidity/script/rehearse.sh
.PHONY: mainnet-rehearse
mainnet-rehearse:
	cd solidity && ./script/rehearse.sh

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
