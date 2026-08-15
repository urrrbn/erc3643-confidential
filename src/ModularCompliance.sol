// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC7984} from "@openzeppelin/confidential-contracts/interfaces/IERC7984.sol";

import {ICompliance} from "./interfaces/ICompliance.sol";
import {IComplianceModule} from "./interfaces/IComplianceModule.sol";

/// @notice DEMO-ONLY: ERC-3643 `ModularCompliance`, retyped. NEVER USE THIS IN PRODUCTION.
contract ModularCompliance is ZamaEthereumConfig, ICompliance {
    address public token;
    address[] public modules;

    euint64 public totalTransferred;

    error OnlyToken(address caller);
    error AlreadyBound();

    function bindToken(address token_) external {
        require(token == address(0), AlreadyBound());
        token = token_;
    }

    function addModule(address module) external {
        modules.push(module);
    }

    modifier onlyToken() {
        require(msg.sender == token, OnlyToken(msg.sender));
        _;
    }

    function canTransfer(address from, address to, euint64 amount) external onlyToken returns (ebool ok) {
        euint64 fromBalance = _balance(from);
        euint64 toBalance = _balance(to);

        ok = FHE.asEbool(true);
        for (uint256 i; i < modules.length; ++i) {
            address module = modules[i];

            // The token's grant stopped at this contract: transient access does
            // not follow a `call`. Re-grant every handle for each module.
            FHE.allowTransient(amount, module);
            FHE.allowTransient(fromBalance, module);
            FHE.allowTransient(toBalance, module);

            ok = FHE.and(ok, IComplianceModule(module).moduleCheck(from, to, amount, fromBalance, toBalance));
        }

        FHE.allowTransient(ok, msg.sender);
    }

    function transferred(address, address, euint64 amount) external onlyToken {
        _accumulate(amount);
    }

    function created(address, euint64 amount) external onlyToken {
        _accumulate(amount);
    }

    /// Normalises a balance into a handle this contract can hand on. An
    /// uninitialised balance is not a handle at all, so it has to be
    /// materialised as an encrypted zero.
    function _balance(address holder) private returns (euint64 balance) {
        if (holder != address(0)) {
            balance = IERC7984(token).confidentialBalanceOf(holder);
            if (FHE.isInitialized(balance)) return balance;
        }
        return FHE.asEuint64(0);
    }

    function _accumulate(euint64 amount) private {
        totalTransferred = FHE.isInitialized(totalTransferred) ? FHE.add(totalTransferred, amount) : amount;
        // Transient access from the token expires with the transaction; state
        // that outlives it needs a persistent grant here.
        FHE.allowThis(totalTransferred);
    }
}
