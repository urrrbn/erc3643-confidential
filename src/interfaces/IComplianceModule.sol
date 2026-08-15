// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

/// @notice DEMO-ONLY: ERC-3643 `IModule.moduleCheck`, retyped.
interface IComplianceModule {
    function moduleCheck(address from, address to, euint64 amount, euint64 fromBalance, euint64 toBalance)
        external
        returns (ebool);
}
