// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @notice DEMO-ONLY: stands in for the ERC-3643 IdentityRegistry. NEVER USE THIS IN PRODUCTION.
contract IdentityRegistryMock is IIdentityRegistry {
    mapping(address account => bool) public override isVerified;

    function setVerified(address account, bool verified) external {
        isVerified[account] = verified;
    }
}
