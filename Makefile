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

# Live integration check: real deposit + rebalance + redeem against a deployed
# vault. The rebalance is forced but runs against live state, so it may be a
# no-op. Spends real funds (swap fees) — dry-run first.
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

# ---------------------------------------------------------------------------
# Cadence VaultRebalancer deployment (Flow mainnet)
#
# Runbook: README.md#deployment
# Signing uses the `mainnet-deployer` account from flow.mainnet.json.
#
# Per-step inputs:
#   VAULT             setup/schedule: FCMVault EVM address the tick calls (0x…)
#   TICK_INTERVAL     setup: seconds between ticks (e.g. 3600.0)
#   EVM_GAS_LIMIT     setup: gas cap for the rebalance() EVM call (e.g. 200000)
#   EXECUTION_EFFORT  setup: Cadence execution-effort budget per tick
#
# Every target has a *-dry variant that runs against a local emulator forked
# from live mainnet state. Start the fork in another terminal with
# `make mainnet-fork-emulator`. the *-dry targets then sign with
# the real deployer key against the forked account state (--network mainnet-fork).
#
# Calldata is hardcoded to rebalance(): the bare 4-byte selector 0x7d7c2a1c
# (no arguments) = the UInt8 array below. Scheduler priority is Medium (rawValue 1).
# ---------------------------------------------------------------------------

# Base config + mainnet-deployer overlay, for every deploy/setup/schedule target.
FLOW_CONFIG := -f flow.json -f flow.mainnet.json

# rebalance() calldata as a JSON-CDC [UInt8]: the 4 selector bytes 0x7d,0x7c,0x2a,0x1c.
REBALANCE_CALLDATA := {"type":"Array","value":[{"type":"UInt8","value":"125"},{"type":"UInt8","value":"124"},{"type":"UInt8","value":"42"},{"type":"UInt8","value":"28"}]}

# Full JSON-CDC argument list for setup_rebalancer.cdc. coaPath /storage/evm and
# feeProviderPath /storage/flowTokenVault are the deployer's COA + FlowToken vault.
SETUP_ARGS := [{"type":"String","value":"$(VAULT)"},{"type":"Path","value":{"domain":"storage","identifier":"evm"}},{"type":"Path","value":{"domain":"storage","identifier":"flowTokenVault"}},$(REBALANCE_CALLDATA),{"type":"UInt8","value":"1"},{"type":"UFix64","value":"$(TICK_INTERVAL)"},{"type":"UInt64","value":"$(EVM_GAS_LIMIT)"},{"type":"UInt64","value":"$(EXECUTION_EFFORT)"}]

# Start a local emulator forked from live mainnet state (run in its own terminal
# for the *-dry rehearsals; Ctrl-C to stop).
.PHONY: mainnet-fork-emulator
mainnet-fork-emulator:
	flow emulator --fork mainnet

# Step 1: publish the VaultRebalancer contract to the deployer account. Idempotent:
# --update re-deploys in place when the contract already exists (e.g. to ship an
# additive change), subject to Cadence contract-update validation.
.PHONY: mainnet-deploy-rebalancer mainnet-deploy-rebalancer-dry
mainnet-deploy-rebalancer-dry:
	flow project deploy $(FLOW_CONFIG) --network mainnet-fork --update
mainnet-deploy-rebalancer:
	flow project deploy $(FLOW_CONFIG) --network mainnet --update

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

# Teardown: cancel the pending tick (refunding its fee to the deployer's FlowToken
# vault) and destroy the Rebalancer resource for VAULT, freeing its storage path.
# Stops the loop and reclaims fee funds from an unused/misconfigured rebalancer;
# the same target can then be re-created with mainnet-setup-rebalancer. Debugging /
# operational cleanup only.
.PHONY: mainnet-remove-rebalancer mainnet-remove-rebalancer-dry
mainnet-remove-rebalancer-dry:
	flow transactions send cadence/transactions/remove_rebalancer.cdc $(FLOW_CONFIG) --network mainnet-fork --signer mainnet-deployer --args-json '[{"type":"String","value":"$(VAULT)"}]'
mainnet-remove-rebalancer:
	flow transactions send cadence/transactions/remove_rebalancer.cdc $(FLOW_CONFIG) --network mainnet --signer mainnet-deployer --args-json '[{"type":"String","value":"$(VAULT)"}]'

# ---------------------------------------------------------------------------
# Security scanning (containerized)
#
# This repository is PUBLIC and the contracts hold real value, so the tiers
# differ in where they may run:
#
#   AI tier (ai-review/ai-audit/ai-skills) + Aderyn -> LOCAL ONLY.
#     The AI tier synthesizes exploit paths that are NOT trivially reproducible
#     from source; publishing them (public Actions logs / PR comments) would
#     leak live vulnerabilities. Its reports stay in security/reports/
#     (gitignored) and are never committed or posted.
#
#   Static gate (Slither + Solhint) -> ALSO RUNS IN CI as a merge gate.
#     Both are deterministic and reproducible from the (public) source, so an
#     attacker can already run them against this repo — surfacing their output
#     in CI leaks nothing new, while the gate keeps flagged code from shipping.
#     See .github/workflows/security-static.yml. Reproduce it locally with
#     `make security-ci`.
#
# Every scanner still runs inside a locked-down Docker container (see
# security/docker/) so untrusted analysis — especially community AI skills —
# cannot read host files or secrets:
#   static tier -> no network at all
#   AI tier     -> egress restricted to the Anthropic API; needs a Claude
#                  credential (see Credentials in docs/security-scanning.md)
#
# SEVERITY GATE: `make security-ci` (and CI) run Slither with --fail-medium, so
# Medium-or-higher-impact findings fail; Low/Info are reported but do not block.
# Solhint fails on `error`-severity rules only. Pre-existing benign Mediums are
# suppressed inline at their source (grep the contracts for slither-disable).
#
# IGNORING A FALSE ALARM (inline suppression — we do NOT keep a baseline DB):
#   Slither: on the line ABOVE the flagged statement, with a justification —
#              // <why this is safe>
#              // slither-disable-next-line <detector>   (e.g. unused-return)
#   Solhint: // solhint-disable-next-line <rule-id>      above the flagged line
#   The detector/rule id is the name printed in the report output.
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

# Reproduce the CI merge gate locally: exactly Slither + Solhint (no Aderyn, no
# AI tier), same tools/versions/config as .github/workflows/security-static.yml.
# Aderyn is excluded from the gate on purpose: its severity model is only
# High/Low (too coarse to gate on), its sole "High" here was a false positive,
# and its suppression story is weaker. Run it separately with `make
# security-aderyn` as an advisory local check.
.PHONY: security-ci
security-ci: security-slither security-solhint

# Run all non-AI static analyzers locally (sealed, no network). Superset of the
# CI gate — adds Aderyn as an advisory (non-gating) check.
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
