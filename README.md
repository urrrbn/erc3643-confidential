# Confidential T-REX

A confidential version of an ERC-3643 permissioned token: balances and transfer
amounts encrypted under ERC-7984 (FHEVM), the permissioning kept, and a named
auditor with full off-chain oversight. The asset archetype is a tokenised
money-market fund.

- [DESIGN.md](DESIGN.md): the design spec, the primary deliverable
- [APPROACH.md](APPROACH.md): reflection, what would come next and how AI was used
- `src/`, `test/`: the build slice, the token-compliance boundary with Foundry tests

### Prerequisites

- **Foundry**: [Installation guide](https://book.getfoundry.sh/getting-started/installation)

### Installation

1. **Install dependencies**

   ```bash
   forge soldeer install
   ```

2. **Compile and test**

   ```bash
   forge build
   forge test -vvv
   ```


## What the tests show

`test/ComplianceSeam.t.sol` runs one confidential transfer end to end, from the
token through the compliance to both modules and back, and tests the claims the
design rests on:

- the ACL grant relay across plain `call` boundaries holds, and a single
  missed grant breaks the transfer;
- a transfer carrying both amount rules (10% cap, minimum holding) fits the
  production HCU budgets
- the auditor decrypts every balance and amount after every write through the
  ACL-checked path, and nothing they were not granted;
- address rules (identity, freeze) still revert in plaintext, while amount
  rules block silently by moving an encrypted zero.

Demo-only shortcuts are marked `// DEMO-ONLY:` in the source.

There is no deployment script: the slice is test-only by design. 