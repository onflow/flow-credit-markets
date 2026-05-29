SCOPE — the FULL current codebase of this Foundry/Solidity project:
- Audit every contract under `solidity/src/`.
- Do NOT audit the vendored dependencies under `solidity/lib/`, the tests under
  `solidity/test/`, or scripts under `solidity/script/` (read for context only).

Use the threat model relevant to a value-bearing vault: fund drainage via
arbitrary calldata, access-control / privilege boundaries, NAV / share-price
manipulation, reentrancy, withdrawal-timing attacks, rounding & precision,
oracle / flash-loan manipulation, untested adapter code paths, and unsafe ERC20
assumptions.

Rate each finding CRITICAL / HIGH / MEDIUM / LOW with file, line, a concrete
exploit scenario, and a recommended fix. Print a clear, severity-grouped report
to stdout. If you find nothing material, say so.

SECURITY — THIS REPOSITORY IS PUBLIC AND THE CONTRACTS HOLD REAL VALUE:
- Do NOT create issues, post PR/issue comments, open advisories, or push commits.
- Do NOT write findings into any tracked file or anywhere under the repo except
  by printing to stdout (the wrapper script saves it to a local, gitignored
  report). Leaking a live vulnerability could cause users to lose funds.
