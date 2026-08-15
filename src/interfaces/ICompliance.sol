// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

/// @notice DEMO-ONLY: ERC-3643 `ICompliance`, retyped.
interface ICompliance {
    function canTransfer(address from, address to, euint64 amount) external returns (ebool);

    function transferred(address from, address to, euint64 amount) external;

    function created(address to, euint64 amount) external;
}
