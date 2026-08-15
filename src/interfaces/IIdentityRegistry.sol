// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

/// @notice DEMO-ONLY: ERC-3643 `IIdentityRegistry`, retyped.
interface IIdentityRegistry {
    function isVerified(address account) external view returns (bool);
}
