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
# Mainnet deployment (Flow EVM mainnet — MANUAL ONLY, never run from CI)
#
# All deployments are deliberate, operator-driven actions against real funds.
# Every target has a *-dry variant that fork-simulates the exact transaction
# sequence against live mainnet state for free — ALWAYS dry-run first.
# Runbook: README.md#deployment
#
# Inputs come from the environment:
#   PRIVATE_KEY   deployer key (becomes vault admin/owner on deploy)
#   SEED_AMOUNT   mainnet-seed-market: loan token base units to supply
#   MAX_TVL       mainnet-deploy / mainnet-set-max-tvl: TVL limit (asset base units)
#   VAULT         mainnet-check / mainnet-set-max-tvl / mainnet-grant-access: FCMVault address
#   EARLY_ACCESS_GRANTEES  mainnet-grant-access: comma-separated addrs to allow-list
#   SWAP_AMOUNT   mainnet-swap-weth: FLOW wei to convert (default: half balance)
#   SLIPPAGE_BPS  mainnet-swap-weth: max swap slippage in bps (default 300)
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

# Update a deployed vault's TVL limit (e.g. raise from 0 to open deposits).
.PHONY: mainnet-set-max-tvl mainnet-set-max-tvl-dry
mainnet-set-max-tvl-dry:
	cd solidity && forge script script/SetMaxTvl.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-set-max-tvl:
	cd solidity && forge script script/SetMaxTvl.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --private-key $(PRIVATE_KEY)

# Allow-list accounts on a deployed vault (grant EARLY_ACCESS_ROLE so they can
# deposit/hold/receive shares). Re-runnable; already-listed addresses skipped.
.PHONY: mainnet-grant-access mainnet-grant-access-dry
mainnet-grant-access-dry:
	cd solidity && forge script script/GrantEarlyAccess.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-grant-access:
	cd solidity && forge script script/GrantEarlyAccess.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --private-key $(PRIVATE_KEY)

# Acquire WETH (vault collateral) for the deployer by wrapping native FLOW and
# swapping WFLOW -> WETH on FlowSwap V3. Fund the deployer before mainnet-check.
.PHONY: mainnet-swap-weth mainnet-swap-weth-dry
mainnet-swap-weth-dry:
	cd solidity && forge script script/SwapForWeth.s.sol --rpc-url $(FLOW_MAINNET_RPC) --private-key $(PRIVATE_KEY)
mainnet-swap-weth:
	cd solidity && forge script script/SwapForWeth.s.sol --rpc-url $(FLOW_MAINNET_RPC) --broadcast --private-key $(PRIVATE_KEY)

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

# Full deployment rehearsal on an anvil fork of mainnet: seed -> deploy ->
# live check, with state carried between steps, against real Morpho/FlowSwap/
# Pyth contracts. Zero real funds; needs no PRIVATE_KEY. Run before any real
# deployment. Details: solidity/script/rehearse.sh
.PHONY: mainnet-rehearse
mainnet-rehearse:
	cd solidity && ./script/rehearse.sh

# ---------------------------------------------------------------------------
# Cadence VaultRebalancer deployment (Flow mainnet — MANUAL ONLY, never CI)
#
# The rebalancer is a Cadence resource that pokes FCMVault.rebalance() on an
# interval via FlowTransactionScheduler (FLIP-330). Deploying it is three
# deliberate steps: publish the contract, create the per-target Rebalancer
# resource pointing at the FCMVault, then kick off the self-rescheduling loop.
# Runbook: README.md#deployment
#
# Signing uses the flow.json `mainnet-deployer` account, sourced from the env:
#   FLOW_DEPLOYER_ADDRESS      deployer account address (becomes resource owner)
#   FLOW_DEPLOYER_PRIVATE_KEY  deployer key (ECDSA_P256 / SHA3_256, key index 0)
#
# Per-step inputs:
#   VAULT             setup/schedule: FCMVault EVM address the tick calls (0x…)
#   TICK_INTERVAL     setup: seconds between ticks (e.g. 3600.0)
#   EVM_GAS_LIMIT     setup: gas cap for the rebalance() EVM call (e.g. 200000)
#   EXECUTION_EFFORT  setup: Cadence execution-effort budget per tick
#
# Every target has a *-dry variant that runs against a local emulator forked
# from live mainnet state — ALWAYS dry-run first. Start the fork in another
# terminal with `make mainnet-fork-emulator`; the *-dry targets then sign with
# the real deployer key against the forked account state (--network mainnet-fork).
#
# Calldata is hardcoded to rebalance(false): selector 0xebb61595 + a 32-byte
# zero arg = the UInt8 array below. Scheduler priority is Medium (rawValue 1).
#
# The mainnet-deployer account lives in the flow.mainnet.json overlay (loaded
# only here, via -f), keeping the base flow.json — and `flow test` / `make ci`
# — free of the deployer's required env vars.
# ---------------------------------------------------------------------------

# Base config + mainnet-deployer overlay, for every deploy/setup/schedule target.
FLOW_CONFIG := -f flow.json -f flow.mainnet.json

# rebalance(false) calldata as a JSON-CDC [UInt8]: 0xeb,0xb6,0x15,0x95 then 32 zero bytes.
REBALANCE_CALLDATA := {"type":"Array","value":[{"type":"UInt8","value":"235"},{"type":"UInt8","value":"182"},{"type":"UInt8","value":"21"},{"type":"UInt8","value":"149"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"},{"type":"UInt8","value":"0"}]}

# Full JSON-CDC argument list for setup_rebalancer.cdc. coaPath /storage/evm and
# feeProviderPath /storage/flowTokenVault are the deployer's COA + FlowToken vault.
SETUP_ARGS := [{"type":"String","value":"$(VAULT)"},{"type":"Path","value":{"domain":"storage","identifier":"evm"}},{"type":"Path","value":{"domain":"storage","identifier":"flowTokenVault"}},$(REBALANCE_CALLDATA),{"type":"UInt8","value":"1"},{"type":"UFix64","value":"$(TICK_INTERVAL)"},{"type":"UInt64","value":"$(EVM_GAS_LIMIT)"},{"type":"UInt64","value":"$(EXECUTION_EFFORT)"}]

# Start a local emulator forked from live mainnet state (run in its own terminal
# for the *-dry rehearsals; Ctrl-C to stop).
.PHONY: mainnet-fork-emulator
mainnet-fork-emulator:
	flow emulator --fork mainnet

# Step 1: publish the VaultRebalancer contract to the deployer account.
.PHONY: mainnet-deploy-rebalancer mainnet-deploy-rebalancer-dry
mainnet-deploy-rebalancer-dry:
	flow project deploy $(FLOW_CONFIG) --network mainnet-fork
mainnet-deploy-rebalancer:
	flow project deploy $(FLOW_CONFIG) --network mainnet

# Step 2: create + save the Rebalancer resource targeting VAULT (FCMVault).
.PHONY: mainnet-setup-rebalancer mainnet-setup-rebalancer-dry
mainnet-setup-rebalancer-dry:
	flow transactions send cadence/transactions/setup_rebalancer.cdc $(FLOW_CONFIG) --network mainnet-fork --signer mainnet-deployer --args-json '$(SETUP_ARGS)'
mainnet-setup-rebalancer:
	flow transactions send cadence/transactions/setup_rebalancer.cdc $(FLOW_CONFIG) --network mainnet --signer mainnet-deployer --args-json '$(SETUP_ARGS)'

# Step 3: kick off the self-rescheduling tick loop (permissionless, idempotent).
.PHONY: mainnet-schedule-rebalancer mainnet-schedule-rebalancer-dry
mainnet-schedule-rebalancer-dry:
	flow transactions send cadence/transactions/schedule_next.cdc $(FLOW_CONFIG) --network mainnet-fork --signer mainnet-deployer --args-json '[{"type":"String","value":"$(VAULT)"}]'
mainnet-schedule-rebalancer:
	flow transactions send cadence/transactions/schedule_next.cdc $(FLOW_CONFIG) --network mainnet --signer mainnet-deployer --args-json '[{"type":"String","value":"$(VAULT)"}]'

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
