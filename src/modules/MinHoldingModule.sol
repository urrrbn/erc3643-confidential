// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

import {IComplianceModule} from "../interfaces/IComplianceModule.sol";

/// @notice DEMO-ONLY. R5: minimum holding of 100,000 units, both sides. NEVER USE THIS IN PRODUCTION.
contract MinHoldingModule is ZamaEthereumConfig, IComplianceModule {
    uint64 public constant MIN_HOLDING = 100_000 * 10 ** 6;

    function moduleCheck(address from, address, euint64 amount, euint64 fromBalance, euint64 toBalance)
        external
        returns (ebool ok)
    {
        // Wraps when toBalance + amount overflows, which reads as a tiny
        // position and blocks. Harmless: such an amount exceeds any real
        // balance, so ERC7984 zeroes the transfer anyway.
        euint64 landed = FHE.add(toBalance, amount);
        ebool okTo = FHE.or(FHE.eq(landed, 0), FHE.ge(landed, MIN_HOLDING));

        if (from == address(0)) {
            ok = okTo; // mint: no sender position to leave behind
        } else {
            // Underflows when amount > fromBalance, which reads as "well above
            // the floor" and approves. Harmless: ERC7984 zeroes the transfer
            // anyway on insufficient balance.
            euint64 rest = FHE.sub(fromBalance, amount);
            ok = FHE.and(FHE.or(FHE.eq(rest, 0), FHE.ge(rest, MIN_HOLDING)), okTo);
        }
        FHE.allowTransient(ok, msg.sender);
    }
}
