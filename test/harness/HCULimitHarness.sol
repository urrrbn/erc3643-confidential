// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {HCULimit} from "@fhevm/host-contracts/contracts/HCULimit.sol";

contract HCULimitHarness is HCULimit {
    /// @dev Immutable, so it lives in code rather than in proxy storage and
    /// cannot collide with the namespaced storage of the contract it replaces.
    uint256 public immutable maxDepthPerTx;

    /// @param maxDepthPerTx_ The sequential depth cap to enforce. Pass
    /// `PRODUCTION_MAX_DEPTH_PER_TX` to keep production behaviour and use this
    /// contract purely as a meter.
    constructor(uint256 maxDepthPerTx_) {
        maxDepthPerTx = maxDepthPerTx_;
    }

    /// @notice The depth cap the vendored `HCULimit` compiles in.
    function productionMaxDepthPerTx() external pure returns (uint256) {
        return 5_000_000;
    }

    /// @notice HCU charged across the current transaction so far.
    /// @dev Transient storage, which Foundry clears per test rather than per
    /// call, so a test reads this after the call it wants to measure.
    function transactionHCU() external view returns (uint256) {
        return _getHCUForTransaction();
    }

    /// @notice Sequential depth accumulated on a single handle.
    function handleHCU(bytes32 handle) external view returns (uint256) {
        return _getHCUForHandle(handle);
    }

    function _adjustAndCheckFheTransactionLimitOneOp(uint256 opHCU, bytes32 op1, bytes32 result)
        internal
        virtual
        override
    {
        _updateAndVerifyHCUTransactionLimit(opHCU);

        uint256 totalHCU = opHCU + _getHCUForHandle(op1);
        if (totalHCU >= maxDepthPerTx) revert HCUTransactionDepthLimitExceeded();

        _setHCUForHandle(result, totalHCU);
    }

    function _adjustAndCheckFheTransactionLimitTwoOps(uint256 opHCU, bytes32 op1, bytes32 op2, bytes32 result)
        internal
        virtual
        override
    {
        _updateAndVerifyHCUTransactionLimit(opHCU);

        uint256 totalHCU = opHCU + _maxOf(_getHCUForHandle(op1), _getHCUForHandle(op2));
        if (totalHCU >= maxDepthPerTx) revert HCUTransactionDepthLimitExceeded();

        _setHCUForHandle(result, totalHCU);
    }

    function _adjustAndCheckFheTransactionLimitThreeOps(
        uint256 opHCU,
        bytes32 op1,
        bytes32 op2,
        bytes32 op3,
        bytes32 result
    ) internal virtual override {
        _updateAndVerifyHCUTransactionLimit(opHCU);

        uint256 totalHCU = opHCU + _maxOf(_getHCUForHandle(op1), _maxOf(_getHCUForHandle(op2), _getHCUForHandle(op3)));
        if (totalHCU >= maxDepthPerTx) revert HCUTransactionDepthLimitExceeded();

        _setHCUForHandle(result, totalHCU);
    }

    /// @dev The base contract's `_max` is `private`.
    function _maxOf(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? a : b;
    }
}
