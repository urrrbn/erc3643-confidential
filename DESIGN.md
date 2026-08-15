# Confidential ERC-3643: design spec

**V1**

**Asset archetype: tokenised money-market fund (MMF) shares**

## Objective

The asset manager issues MMF shares as an ERC-3643 permissioned token. It works, but every balance and every transfer amount is public, so anyone can watch a named investor's position build and unwind.

The goal is a confidential version of the same token: balances and amounts become ERC-7984 ciphertext, the permissioning keeps working, and a named auditor can read everything off chain. The rules that bind today keep binding:


| #   | Rule                                                          |
| --- | ------------------------------------------------------------- |
| R1  | Valid KYC/AML claim from a trusted issuer                     |
| R2  | Permitted jurisdiction                                        |
| R3  | Neither wallet frozen, fund not paused                        |
| R4  | No investor above 10% of supply, on transfer and subscription |
| R5  | Minimum holding of 100,000 units                              |


The end state: an observer sees who is in the fund and when they deal, never for how much. The auditor sees everything. The same rules block the same transfers.

## Pushback

**"Keep the permissioning" cannot mean interface-level ERC-3643 conformance.** `balanceOf` is gone and `canTransfer` is no longer `view`, so any tool expecting the ERC-20 surface breaks. What we commit to is behavioural conformance: the same rules bind the same transfers with the same outcomes.

**The primary market has to be encrypted too**, which was not in the ask. Every subscription and redemption belongs to a named investor, so if those amounts are public, anyone can add them up and recover the balances we just hid.

Encrypting them is not enough on its own. Shares are bought with cash at a published NAV, so the number of shares is the cash divided by a public number. Anyone who sees an investor's subscription payment knows the mint amount exactly, and the redemption payment gives them the burn. So the cash has to be as private as the shares. The design assumes subscriptions and redemptions settle off chain, by wire to the fund's custodian. If the fund ever settles on chain in a public stablecoin, the confidentiality is gone whatever the token does, and the cash leg has to move to a confidential token too.

**The asset manager needs to know about silent zero.** A blocked transfer does not revert, it succeeds and moves zero (see Protocol constraints), so the investor sees a confirmed transaction and an unchanged position. The behaviour is forced.

## Scope

ERC-3643 splits along exactly the line the fund needs: identity logic reads addresses, compliance reads amounts. So the change lands on the amount side and the identity side is reused as deployed.


| Component                                          | Change                                                                                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Token**                                          | **rebuilt**: `ConfidentialTrex` extends ERC7984 instead of ERC-20                                                                    |
| **Compliance** (ModularCompliance and its modules) | **retyped**: `uint256` becomes `euint64`, `bool` becomes `ebool`. Amount-keyed modules retyped with it, address-keyed ones unchanged |


An issuer's existing deployment carries over: same registries, same trusted issuers, same onboarded investors, same agents. This is a token swap, not a re-onboarding.

What each value looks like afterwards:


| Value                                          | Visibility                                                                                |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Holder balances                                | Encrypted                                                                                 |
| Transfer amounts                               | Encrypted                                                                                 |
| Mint and burn amounts                          | Encrypted (see Pushback)                                                                  |
| Which address subscribed or redeemed, and when | Public (see Trade offs)                                                                   |
| Total supply                                   | Public, published periodically under a KMS-signed proof (see Design)                      |
| Holder addresses                               | Public on chain, unchanged from ERC-3643; claim contents stay off chain against ONCHAINID |
| Auditor's view                                 | Full plaintext, off chain (see Design)                                                    |




### Trade offs

- **Who deals with the fund, and when, stays public.** Mint and burn emit the investor's address, so an observer sees that a named holder subscribed or redeemed and at what time, just not for how much. Hiding that means holding through an omnibus account, which moves the investor register off chain and takes ERC-3643 with it. Accepted.
- **The 10% cap reads a published plaintext supply, not the encrypted handle.** That keeps the comparison a cheap scalar operation. The cost is freshness: between publishes the cap binds against the last published figure (see Risks). It also cannot bind before the first publish, so the fund seeds the figure at launch.



### Risks


| Risk                   | Why it matters                                                                                                                                              | Mitigation                                                                                                   |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Auditor key compromise | The key does not just read. Anyone allowed on a handle can grant it onward, or mark it publicly decryptable, and the ACL has no revoke for persistent grants. A stolen key makes disclosure permanent in one transaction, and rotation does not undo it | see ./APPROACH.md |
| ACL grant bug          | A missed grant blinds the auditor permanently for that handle; an over-broad grant is a disclosure that cannot be undone                                    | Covered by the build slice, negative case included: deleting a grant fails the auditor's decrypt. Reviewed as security-critical code |
| Stale published supply | If nobody publishes, R4 enforces 10% of an old number                                                                                                       | Publishing runs at each NAV strike; the stored figure carries a timestamp and staleness is monitored         |




### Protocol constraints

- **No branching on a ciphertext.** A failed amount-keyed rule cannot revert, so it zeroes the transfer instead. This is the only change in observable behaviour, and the only one the fund's operations team has to absorb.
- **HCU ceilings**, currently 20,000,000 per transaction and 5,000,000 on the longest dependency chain. A compliant transfer carrying both amount rules measures 1,929,160, and its longest chain sits between 700,000 and 800,000. Neither ceiling is close, so the chain has room for several more modules than first assumed (see Build slice).
- **Access is transitive and permanent.** The ACL draws no line between using a handle and handing it on: anyone allowed on one can grant it to any address, or make it publicly decryptable, and persistent grants have no revoke. A transient grant is no weaker in this respect, because its holder can upgrade it to a persistent one before the transaction ends. So every contract on the transfer path, the compliance and each module, is a trusted component rather than a sandboxed one, and adding a module is an owner-gated action.
- **Decryption is async, in seconds.** No rule may depend on a decrypted value, and the auditor reads off chain rather than on.
- `euint64` **tops out near 1.8e19.** This is why the token uses 6 decimals rather than 18: at 18, a fund of any size overflows, and there is no headroom left for intermediate products.



## Out of scope

- **The Identity Verifier.** `IdentityRegistry` and the ONCHAINID claim stack remain untouchable, reused exactly as deployed. Everything in them is address-keyed and never sees an amount, so encryption changes nothing. The token calls only `isVerified` on the transfer path.
- **Batch operations.** ERC-3643 specifies `batchTransfer`, `batchMint` and the batch freeze calls. Each element carries its own FHE cost, so batch sizes that are routine today exceed the per-transaction cap and have to be chunked.
- **Partial freeze and wallet recovery.** `getFrozenTokens` turns a `uint256` into encrypted state, which adds a comparison to every transfer, and `recoveryAddress` has to move handles and re-grant the ACL to the new wallet.
- **The yield layer.** What is being made confidential is an investor's claim on the pool, not what the pool earns. In an accumulating class the two do not interact anyway: income accrues into NAV rather than being distributed.



## Design



### End-to-end flow

```mermaid
sequenceDiagram
    participant Investor as Investor / agent
    participant Token as Token<br/>ConfidentialTrex, extends ERC7984
    participant IV as Identity Verifier<br/>IdentityRegistry + ONCHAINID (unchanged)
    participant CC as Compliance Contract<br/>ModularCompliance (retyped)
    participant Mod as Compliance modules<br/>R4, R5
    participant Relayer as Relayer / Gateway / KMS
    participant Auditor

    Investor->>Token: confidentialTransfer(encrypted amount + input proof)
    Token->>Token: R3: freeze and pause flags, failure reverts
    Token->>IV: isVerified(to)  (R1, R2)
    IV-->>Token: bool, false reverts
    Token->>CC: canTransfer(from, to, euint64), granting the amount and both balances
    CC->>Mod: moduleCheck, re-granting every handle: a grant does not survive a call
    Mod-->>CC: ebool, granted back
    CC-->>Token: ebool verdict, granted back
    Token->>Token: FHE.select: amount or encrypted zero
    Token->>Token: balances and supply move, ACL grants to token, holders, auditor
    Token->>CC: transferred(actual amount)
    Auditor->>Relayer: EIP-712 signed decryption request
    Relayer-->>Auditor: plaintext for every granted handle
    Note over Token,Relayer: on mint and burn the supply handle becomes publicly decryptable; anyone decrypts it and publishTotalSupply verifies the KMS proof on chain
```




One transfer, end to end:

1. The investor's client encrypts the amount through the Zama SDK and gets a handle plus an input proof bound to the token contract.
2. `confidentialTransfer` lands in `_update`, the single interception point.
3. The token checks the address rules (R1 to R3) in plaintext, against the Identity Verifier and its own freeze and pause flags. A failure reverts here, before any FHE work.
4. The token grants the Compliance Contract transient access to the amount and to both balances, then asks `canTransfer`. The compliance re-grants each handle to each module, because a grant does not survive a call, and folds R4 and R5 into one `ebool`.
5. `FHE.select` turns the verdict into the permitted amount: the requested one, or an encrypted zero.
6. `super._update` moves the balances. ERC7984 applies its own select on top for insufficient balance.
7. The new handles are granted to the token, both holders and the auditor, and the compliance hooks get the actually transferred amount.
8. Off chain, the auditor decrypts any handle they were granted, through the relayer with an EIP-712 signed request. On mint and burn the supply handle is also marked publicly decryptable, which feeds the supply publishing loop.



### Core components

- **Token**: `ConfidentialTrex`, rebuilt. An ERC-7984 confidential token that holds the encrypted balances and carries the ERC-3643 permissioning.
- **Compliance Contract**: a separate contract that validates transfers, minting and burning operations. `ModularCompliance` and its modules, retyped.

The Identity Verifier, the separate contract responsible for verifying user identities, stays in the diagram because the token calls it on every transfer, but it is untouchable and out of scope (see Out of scope).

### Token

`ConfidentialTrex`, rebuilt from scratch on OpenZeppelin's `ERC7984`.

Requirements:

- **Satisfies ERC-3643 behaviourally.** The same rules bind the same transfers, mints and burns with the same outcomes. What runs on each path is ERC-3643's own asymmetry, kept:


| Path                       | What runs                                                            |
| -------------------------- | -------------------------------------------------------------------- |
| `transfer`, `transferFrom` | address rules, amount rules, then `transferred`                      |
| `mint`                     | both, then `created`                                                 |
| `burn`                     | address rules only, then `destroyed`                                 |
| `forcedTransfer`           | address rules only, as in ERC-3643: the agent override skips compliance |


- **Cannot satisfy ERC-20 fully.** Balances and amounts are handles, so `balanceOf`, `totalSupply` and the plaintext transfer functions are replaced by the ERC-7984 surface (see Pushback).
- **Transfer, balance, mint and burn amounts stay private.** They exist on chain only as ciphertext, and no code path or event ever exposes them in plaintext.
- **A transfer blocked by an amount rule succeeds and moves zero.** Only address-rule failures (R1 to R3) revert; a revert keyed on an amount would leak it.
- **The auditor sees everything.** A named auditor address, set at deployment, can decrypt every balance and every amount off chain from the moment it is written. No key escrow, no plaintext on chain. Failure modes in Risks.
- **Total supply is a handle, publishable by anyone.** Once a day, at the NAV strike, someone decrypts it through the relayer and posts the figure back on chain, where it is verified against the KMS signature and stored with a timestamp for everyone to read. The agent does this in practice, but nothing requires it to be the agent. R4 reads the stored figure.

The interface. ERC-7984 is satisfied in full by inheritance: confidential balances, supply, both transfer overloads, `transferFrom`, the `AndCall` variants and operators all come from OpenZeppelin's `ERC7984`. On top of it, the ERC-3643 surface that survives:

```solidity
import {euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "@openzeppelin/confidential-contracts/interfaces/IERC7984.sol";

interface IConfidentialTrex is IERC7984 {
    event TotalSupplyPublished(uint64 totalSupply, uint64 timestamp);
    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);

    // ERC-3643 management, kept plaintext: none of it touches an amount
    function onchainID() external view returns (address);
    function identityRegistry() external view returns (address);
    function compliance() external view returns (address);
    function paused() external view returns (bool);
    function isFrozen(address userAddress) external view returns (bool);
    function auditor() external view returns (address);
    function setOnchainID(address onchainID) external;
    function setIdentityRegistry(address identityRegistry) external;
    function setCompliance(address compliance) external;
    function setAddressFrozen(address userAddress, bool freeze) external;
    function pause() external;
    function unpause() external;

    // ERC-3643 transfer actions, retyped: amounts enter encrypted, and each
    // returns the amount actually moved (a blocked one moves an encrypted zero)
    function mint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external returns (euint64 transferred);
    function burn(address from, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external returns (euint64 transferred);
    function forcedTransfer(address from, address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external returns (euint64 transferred);

    // supply disclosure: the once-a-day loop
    function publishTotalSupply(uint64 cleartextSupply, bytes calldata decryptionProof) external;
    function disclosedTotalSupply() external view returns (uint64);
    function disclosedSupplyAt() external view returns (uint64);

    // dropped from ERC-3643: partial freeze, recoveryAddress, batch operations
    // (see Out of scope)
}
```

### Compliance Contract

`ModularCompliance` and its modules. The token asks it `canTransfer` before moving value and notifies it afterwards through `transferred`, `created` and `destroyed`.

Requirements:

- **Retyped, not redesigned.** Same four functions on the transfer path; `uint256` becomes `euint64` and `bool` becomes `ebool`.
- **No** `view`**.** FHE operations write handles, so the check cannot be a `staticcall`. This also breaks ERC-3643's requirement of a pre-check before sending: front ends lose the ability to preview a transfer.
- **Every module is its own ACL identity.** `_callModuleFunction` dispatches with a plain `call`, not a `delegatecall`. A grant the token gave the compliance does not reach the module behind it, so every handle has to be re-granted at each hop, and the verdict granted back the same way. One missing grant anywhere reverts the transfer. Module accumulators that were `uint256` become handles needing `FHE.allowThis` in the module's own context.
- **Modules can no longer read the token.** An ERC-3643 module calls `token.balanceOf` freely because balances are public. A handle is useless without a grant, and the token does not know the module list, so the compliance becomes the relay: it holds what the token granted it and passes the balances down as arguments. This changes the shape of `moduleCheck`, and it is the one interface change the retyping forces.
- **Hooks take the actually transferred amount**, not the requested one. A blocked transfer contributes an encrypted zero, so accumulators self-correct without knowing the transfer was blocked.

Interface to satisfy, from ERC-3643, annotated:

```solidity
interface ICompliance {
    // events and binding: kept as-is, no amounts involved
    event TokenBound(address _token);
    event TokenUnbound(address _token);
    function bindToken(address _token) external;
    function unbindToken(address _token) external;
    function isTokenBound(address _token) external view returns (bool);
    function getTokenBound() external view returns (address);

    // retyped: uint256 -> euint64, bool -> ebool, and view is gone.
    // Becomes: canTransfer(address, address, euint64) external returns (ebool)
    function canTransfer(address _from, address _to, uint256 _amount) external view returns (bool);

    // retyped: uint256 -> euint64, same names and order
    function transferred(address _from, address _to, uint256 _amount) external;
    function created(address _to, uint256 _amount) external;
    function destroyed(address _from, uint256 _amount) external;
}
```

And the module interface, which does not survive unchanged. Balances arrive as arguments because the module cannot read them off the token:

```solidity
interface IComplianceModule {
    // was: moduleCheck(address _from, address _to, uint256 _value, address _compliance)
    function moduleCheck(address from, address to, euint64 amount, euint64 fromBalance, euint64 toBalance)
        external
        returns (ebool);
}
```



## Proposed sequence of work

The sequence exists to de-risk delivery: the parts that can falsify the design run first, the periphery follows.


| WP  | Work                                                                                    | Depends on           |
| --- | --------------------------------------------------------------------------------------- | -------------------- |
| WP1 | Map R1 to R3 onto claim topics and registry configuration                               | none                 |
| WP2 | Token core: `ConfidentialTrex`, `_update`, supply publishing, auditor grants            | none                 |
| WP3 | FHE compliance modules: R4, R5, aggregator, HCU tuning                                  | `ICompliance` frozen |
| WP4 | Auditor tooling: SDK client, batch decryption, position reconstruction, grant monitor   | WP2                  |
| WP5 | Ops: NAV-strike publishing runbook, staleness monitoring, key handling                  | WP3, WP4             |
| WP6 | Testnet pass: supply-proof replay and the live auditor decrypt against the real Relayer | WP4                  |


WP2 and WP3 build against the same interface, so they run in parallel. Where they compete for people, WP3 goes first: it owns the boundary the build slice below was written to test.

## Build slice: the token–compliance boundary

One thing in this design could cause problems, and it sits where the token hands off to the compliance. Modules are reached with a plain `call`, so every encrypted handle needs an ACL grant at every hop, in both directions. If handles cannot cross that boundary, the rules have to move inside the compliance contract as internal code, and ERC-3643 modules stop being separately deployable and swappable at runtime, which is quite sad. 

The slice runs one transfer end to end (token, compliance, both modules and back) under `forge-fhevm`. It also measures what the rule set costs, because nothing on paper said how deep the chain runs. Outcome:

- The grant relay holds, and it is load-bearing: a dispatcher variant with a single `allowTransient` deleted reverts the transfer with `ACLNotAllowed`.
- A transfer costs 1,929,160 HCU, asserted under a 2,500,000 budget against the 20,000,000 cap. Its dependency chain is bracketed by tests between 700,000 and 800,000 against 5,000,000. Depth is the tighter of the two and grows with every module added, so it is the budget that decides how many rules a transfer can carry.
- Auditor grants survive every write, through the ACL-checked decrypt path; a handle missing its grant fails the auditor's decrypt with `UserNotAuthorizedForDecrypt`.
- One interface change: modules cannot read the token, so the compliance passes balances down as arguments (see Compliance Contract).

Out of the slice: `burn` and `forcedTransfer` (same shape, fewer rules), supply publishing, the ERC-3643 periphery. 


## Dependencies


| Dependency                                       | What breaks if it moves                                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `@openzeppelin/confidential-contracts` (ERC7984) | The `_update` signature and the disclosure path are load-bearing. Pin it.                               |
| `@fhevm/solidity`                                | ACL and select semantics. Pin it, re-test on upgrade.                                                   |
| Relayer                                          | On the write path, not just the read one: clients need it to build the input proof behind every encrypted amount, so down means no transfers, subscriptions or redemptions. |
| Gateway, KMS                                     | Liveness of decryption, so the auditor flow and supply publishing. Transfers keep working without them. |
| ONCHAINID and ERC-3643 periphery                 | Reused as is. A customised deployment means re-mapping R1 to R3.                                        |
| Auditor key custody                              | Not code, but the biggest residual risk. Settle before launch.                                          |


