// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";

import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {ICompliance} from "./interfaces/ICompliance.sol";

/// @notice DEMO-ONLY: ERC-3643 permissioning over an ERC-7984 confidential token. NEVER USE THIS IN PRODUCTION.
contract ConfidentialTrex is ZamaEthereumConfig, ERC7984 {
    IIdentityRegistry public immutable identityRegistry;
    ICompliance public immutable compliance;
    address public immutable auditor;

 
    address public immutable agent;

    uint64 public disclosedTotalSupply;

    mapping(address holder => bool) private _frozen;

    error WalletFrozen(address holder);
    error IdentityNotVerified(address account);
    error OnlyAgent(address caller);

    constructor(address identityRegistry_, address compliance_, address auditor_, address agent_)
        ERC7984("ConfidentialTrex", "CTREX", "")
    {
        identityRegistry = IIdentityRegistry(identityRegistry_);
        compliance = ICompliance(compliance_);
        auditor = auditor_;
        agent = agent_;
    }

    modifier onlyAgent() {
        require(msg.sender == agent, OnlyAgent(msg.sender));
        _;
    }

    function isFrozen(address holder) external view returns (bool) {
        return _frozen[holder];
    }

    function setFrozen(address holder, bool frozen) external onlyAgent {
        _frozen[holder] = frozen;
    }

    /// DEMO-ONLY: the agent writes the figure directly. In the design it arrives
    /// through a KMS-signed decryption proof, which is its own work package.
    function setDisclosedTotalSupply(uint64 supply) external onlyAgent {
        disclosedTotalSupply = supply;
    }

    function mint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external
        onlyAgent
        returns (euint64)
    {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function _update(address from, address to, euint64 amount) internal override returns (euint64 transferred) {
        _enforceAddressRules(from, to);

        euint64 permitted = FHE.select(_canTransfer(from, to, amount), amount, FHE.asEuint64(0));
        transferred = super._update(from, to, permitted);

        _grantAuditor(from, to, transferred);
        _notifyCompliance(from, to, transferred);
    }

    function _enforceAddressRules(address from, address to) private view {
        if (from != address(0)) require(!_frozen[from], WalletFrozen(from));
        require(!_frozen[to], WalletFrozen(to));
        require(identityRegistry.isVerified(to), IdentityNotVerified(to));
    }

    function _canTransfer(address from, address to, euint64 amount) private returns (ebool) {
        FHE.allowTransient(amount, address(compliance));
        _grantBalance(from);
        _grantBalance(to);
        return compliance.canTransfer(from, to, amount);
    }

    function _grantBalance(address holder) private {
        if (holder == address(0)) return;
        euint64 balance = confidentialBalanceOf(holder);
        if (FHE.isInitialized(balance)) FHE.allowTransient(balance, address(compliance));
    }

    /// Every write mints a new handle, so the auditor grant has to be re-applied
    /// on every transfer. A miss blinds them permanently for that handle.
    function _grantAuditor(address from, address to, euint64 transferred) private {
        FHE.allow(transferred, auditor);
        if (from != address(0)) FHE.allow(confidentialBalanceOf(from), auditor);
        FHE.allow(confidentialBalanceOf(to), auditor);
    }

    /// Hooks take the amount actually moved, so a blocked transfer contributes
    /// an encrypted zero and accumulators self-correct.
    function _notifyCompliance(address from, address to, euint64 transferred) private {
        FHE.allowTransient(transferred, address(compliance));

        if (from == address(0)) compliance.created(to, transferred);
        else compliance.transferred(from, to, transferred);
    }
}
