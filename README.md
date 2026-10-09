# Confidential ERC-3643

An ERC-3643 permissioned token on top of ERC-7984. Balances and transfer amounts are encrypted with Zama's FHEVM.

I built it as a take-home for the Solutions Engineer role at [Zama](https://www.zama.ai). The brief: an asset manager issues a permissioned token on ERC-3643 and wants a confidential version that keeps the permissioning and gives an auditor oversight. They asked for a design doc, a small build of the riskiest part, and a short reflection.

The design and the reasoning behind it are in DESIGN.md. The code in `src/` and `test/` checks the hand-off between the token and the compliance modules, the part I was least sure about.

## Run it

Needs [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge soldeer install
forge build
forge test -vvv
```

Research prototype, not audited. Demo shortcuts are marked `// DEMO-ONLY:`.

## How I used AI

Claude Code with Zama's official skills. I read the docs, sketched the design doc with my own questions, then used Claude for the details and to ship the build slice fast.
