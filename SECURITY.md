# Security Policy

## Status of this contract

SwapEscrow has **not** undergone a professional external security audit. It is
deployed and in use on TON mainnet, which is a statement about where it runs,
not an assurance about its safety. It custodies user-deposited assets (NFTs,
GRAM, and Jettons), and — as documented in the [README's Trust model
section](README.md#trust-model) — the deal's supervisor address holds broad,
unilateral powers over deposited funds. Do not deposit assets you cannot
afford to lose, and do not treat this contract as audited.

## Reporting a vulnerability

If you find a security vulnerability in this contract, please report it
privately rather than opening a public issue. Use GitHub's private
vulnerability reporting on this repository:

1. Go to https://github.com/menabarter/contract/security
2. Click "Report a vulnerability"
3. Fill in the advisory form with as much detail as you can (affected file
   and line, reproduction steps, and — if applicable — a test case).

Please do not disclose the issue publicly (including in public GitHub
issues, pull requests, or elsewhere) until it has been addressed.

## What to expect

This is a small, actively-worked project without a dedicated security team,
so please be patient. We will acknowledge new reports and follow up as we
investigate. There is no bug bounty program at this time.
