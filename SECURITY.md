# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability in Flow Credit Markets, please report it privately before publishing details.

Recommended intake fields:

- Affected contract, script, workflow, or dependency
- A clear impact statement and affected user or asset class
- Reproduction steps, proof of concept, or test case
- Preconditions, required permissions, and network/environment assumptions
- Suggested severity and rationale
- Any public disclosure deadline or coordination constraints

Do not include private keys, seed phrases, live user data, or secrets in a report.

## In Scope

This draft program is intended to cover security defects in this repository's Flow Credit Markets code and deployment/supporting automation, including:

- `solidity/src/FCMVault.sol`
- Solidity tests and deployment scripts under `solidity/`
- CI/build configuration that can affect release integrity
- Documented configuration or operational assumptions that could cause loss of funds, incorrect accounting, or unsafe deployment

## Out of Scope

The following should not be treated as eligible bounty findings unless maintainers explicitly expand the scope:

- Attacks requiring leaked private keys, compromised maintainers, or malicious privileged governance/admin actions
- Social engineering, phishing, spam, or physical attacks
- Denial-of-service against GitHub, RPC providers, explorers, or other third-party infrastructure
- Vulnerabilities only present in stale forks or modified local deployments
- Issues already disclosed publicly or already known to maintainers
- Reports without a reproducible impact path

## Severity Guide

Maintainers should make the final severity call based on exploitability, asset exposure, and required privileges.

| Severity | Example impact |
| --- | --- |
| Critical | Direct loss or theft of funds, unauthorized withdrawal, permanent insolvency, or critical accounting corruption |
| High | Unauthorized privileged action, severe price/accounting manipulation, or realistic path to significant user loss under plausible conditions |
| Medium | Limited asset/accounting impact, denial of core protocol action, or unsafe configuration that requires non-default conditions |
| Low | Hardening issue, missing validation with limited impact, documentation/deployment footgun, or defense-in-depth improvement |
| Informational | Non-exploitable observation, best-practice suggestion, or missing documentation |

## Draft Payout Tiers

These tiers are placeholders for maintainer approval and can be adjusted to match the selected bounty vendor, treasury budget, and launch stage.

| Severity | Suggested bounty range |
| --- | ---: |
| Critical | US$10,000 - US$50,000 |
| High | US$3,000 - US$10,000 |
| Medium | US$500 - US$3,000 |
| Low | US$100 - US$500 |
| Informational | No bounty or discretionary acknowledgement |

Payment should only be made after maintainer validation, duplicate checks, and agreement on severity. If a third-party bounty vendor is used, that vendor's rules should control payment eligibility and dispute handling.

## Disclosure Expectations

A coordinated disclosure process should aim for:

1. Reporter submits private report with reproducible evidence.
2. Maintainers acknowledge receipt and assign an owner.
3. Maintainers validate severity, affected versions, and remediation path.
4. Fix is prepared, reviewed, and released where applicable.
5. Bounty eligibility is confirmed after duplicate and scope checks.
6. Public disclosure happens only after remediation or by explicit maintainer agreement.

## Safe Harbor Draft

Maintainers may choose to publish a formal safe harbor statement through their selected bug bounty vendor. A conservative draft posture:

- Researchers must act in good faith and avoid privacy violations, asset loss, service disruption, or data destruction.
- Research must stay within the explicit scope above.
- Researchers must stop testing and report immediately if they encounter sensitive data or discover an active exploit path.
- Maintainers will not pursue legal action for good-faith research that follows the published program rules.

This document is a starting template, not a replacement for final legal, vendor, or governance review.
