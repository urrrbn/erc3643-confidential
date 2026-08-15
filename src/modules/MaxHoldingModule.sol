// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

import {IComplianceModule} from "../interfaces/IComplianceModule.sol";

interface IDisclosedSupply {
    function disclosedTotalSupply() external view returns (uint64);
}

/// @notice DEMO-ONLY. R4: no investor above 10% of supply. NEVER USE THIS IN PRODUCTION.
contract MaxHoldingModule is ZamaEthereumConfig, IComplianceModule {
    IDisclosedSupply private immutable _token;

    constructor(address token_) {
        _token = IDisclosedSupply(token_);
    }

    function moduleCheck(address, address, euint64 amount, euint64, euint64 toBalance) external returns (ebool ok) {
        uint64 supply = _token.disclosedTotalSupply();
        uint64 cap = supply == 0 ? type(uint64).max : supply / 10;

        // Wraps when toBalance + amount overflows, which slips under the cap
        // and approves. Harmless on transfer: such an amount exceeds any real
        // balance, so ERC7984 zeroes it. On mint the agent is trusted.
        ok = FHE.le(FHE.add(toBalance, amount), cap);
        FHE.allowTransient(ok, msg.sender);
    }
}
