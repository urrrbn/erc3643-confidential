// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {HCULimit} from "@fhevm/host-contracts/contracts/HCULimit.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {hcuLimitAdd} from "forge-fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC7984} from "@openzeppelin/confidential-contracts/interfaces/IERC7984.sol";

import {ConfidentialTrex} from "../src/Token.sol";
import {ModularCompliance} from "../src/ModularCompliance.sol";
import {IdentityRegistryMock} from "../src/IdentityRegistryMock.sol";
import {ICompliance} from "../src/interfaces/ICompliance.sol";
import {IComplianceModule} from "../src/interfaces/IComplianceModule.sol";
import {MaxHoldingModule} from "../src/modules/MaxHoldingModule.sol";
import {MinHoldingModule} from "../src/modules/MinHoldingModule.sol";
import {HCULimitHarness} from "./harness/HCULimitHarness.sol";

/// DEMO-ONLY test double: `ModularCompliance` with the single
/// `FHE.allowTransient(amount, module)` deleted, to show that grant is
/// load-bearing.
contract LeakyCompliance is ZamaEthereumConfig, ICompliance {
    address public token;
    address[] public modules;

    function bindToken(address token_) external {
        token = token_;
    }

    function addModule(address module) external {
        modules.push(module);
    }

    function canTransfer(address from, address to, euint64 amount) external returns (ebool ok) {
        euint64 fromBalance = _balance(from);
        euint64 toBalance = _balance(to);

        ok = FHE.asEbool(true);
        for (uint256 i; i < modules.length; ++i) {
            address module = modules[i];

            // The deleted line: FHE.allowTransient(amount, module);
            FHE.allowTransient(fromBalance, module);
            FHE.allowTransient(toBalance, module);

            ok = FHE.and(ok, IComplianceModule(module).moduleCheck(from, to, amount, fromBalance, toBalance));
        }

        FHE.allowTransient(ok, msg.sender);
    }

    function transferred(address, address, euint64) external {}

    function created(address, euint64) external {}

    function _balance(address holder) private returns (euint64 balance) {
        if (holder != address(0)) {
            balance = IERC7984(token).confidentialBalanceOf(holder);
            if (FHE.isInitialized(balance)) return balance;
        }
        return FHE.asEuint64(0);
    }
}

/// The seam: one transfer through token -> compliance -> two modules and back.
/// Covers the ACL relay across `call` boundaries, the HCU budget, auditor
/// visibility, and silent-block semantics.
contract ComplianceSeamTest is FhevmTest {
    uint64 constant UNIT = 10 ** 6;
    uint256 constant AUDITOR_PK = 0xA11CE;

    /// The depth cap the vendored `HCULimit` compiles in as a private constant.
    uint256 constant PRODUCTION_MAX_DEPTH = 5_000_000;

    ConfidentialTrex token;
    ModularCompliance compliance;
    IdentityRegistryMock registry;

    address auditor = vm.addr(AUDITOR_PK);
    address agent = makeAddr("agent");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address dave = makeAddr("dave");
    address mallory = makeAddr("mallory");

    function setUp() public override {
        super.setUp();

        registry = new IdentityRegistryMock();
        compliance = new ModularCompliance();
        token = new ConfidentialTrex(address(registry), address(compliance), auditor, agent);
        compliance.bindToken(address(token));
        compliance.addModule(address(new MaxHoldingModule(address(token))));
        compliance.addModule(address(new MinHoldingModule()));

        registry.setVerified(alice, true);
        registry.setVerified(bob, true);
        registry.setVerified(dave, true);

        _mint(alice, 10_000_000 * UNIT);
        _mint(dave, 200_000 * UNIT);
        vm.prank(agent);
        token.setDisclosedTotalSupply(10_200_000 * UNIT);

        vm.roll(block.number + 1); // fresh block HCU budget per test
    }

    /// Every handle survives the round trip.
    function test_grantChainSurvivesTransfer() public {
        _transfer(alice, bob, 500_000 * UNIT);

        assertEq(decrypt(token.confidentialBalanceOf(bob)), 500_000 * UNIT);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 9_500_000 * UNIT);
        assertEq(decrypt(compliance.totalTransferred()), 10_700_000 * UNIT);
    }

    /// And breaks without the grant: the module's first touch of the amount
    /// reverts, failing the whole transfer rather than moving anything silently.
    function test_missingDispatcherGrantReverts() public {
        LeakyCompliance leaky = new LeakyCompliance();
        ConfidentialTrex leakyToken = new ConfidentialTrex(address(registry), address(leaky), auditor, agent);
        leaky.bindToken(address(leakyToken));

        // Fund before adding the module: with no modules nothing reads the
        // amount, so the mint clears the leaky dispatcher.
        (externalEuint64 handle, bytes memory proof) = encryptUint64(1_000_000 * UNIT, agent, address(leakyToken));
        vm.prank(agent);
        leakyToken.mint(alice, handle, proof);

        leaky.addModule(address(new MinHoldingModule()));

        (handle, proof) = encryptUint64(500_000 * UNIT, alice, address(leakyToken));
        vm.expectPartialRevert(FHEVMExecutor.ACLNotAllowed.selector);
        vm.prank(alice);
        leakyToken.confidentialTransfer(bob, handle, proof);
    }

    /// R4 + R5 + the token's select + ERC7984's own select, against the
    /// production per-transaction cap.
    ///
    /// One transfer per test on purpose: handle depth lives in transient storage,
    /// which Foundry clears per test rather than per call, so a second transfer
    /// would inherit the first one's depth and measure nothing real.
    function test_hcuWithinBudget() public {
        HCULimitHarness meter = _installHCULimit(PRODUCTION_MAX_DEPTH);

        uint256 before = meter.transactionHCU();
        _transfer(alice, bob, 500_000 * UNIT);
        uint256 usedHCU = meter.transactionHCU() - before;

        emit log_named_uint("HCU for one compliant transfer", usedHCU);
        assertLt(usedHCU, 2_500_000, "over the 2,500,000 budget the slice commits to");
    }

    /// The next two bracket the depth chain between 700,000 and 800,000 with two
    /// modules, rather than settling for "somewhere under 5,000,000". Depth grows
    /// with every module, so the budget decides how many rules a transfer carries.
    function test_depthHeadroomUpperBracket() public {
        _installHCULimit(800_000);

        _transfer(alice, bob, 500_000 * UNIT);
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 500_000 * UNIT);
    }

    /// The failing half, so the passing one above is not vacuous.
    function test_depthHeadroomLowerBracket() public {
        _installHCULimit(700_000);

        (externalEuint64 handle, bytes memory proof) = encryptUint64(500_000 * UNIT, alice, address(token));
        vm.expectRevert(HCULimit.HCUTransactionDepthLimitExceeded.selector);
        vm.prank(alice);
        token.confidentialTransfer(bob, handle, proof);
    }

    /// Handles are new on every write, so the grant has to be re-applied each
    /// time. Decrypts through the ACL-checked path, not the test backdoor.
    function test_auditorDecryptsAfterEveryWrite() public {
        _transfer(alice, bob, 500_000 * UNIT);
        _transfer(alice, bob, 300_000 * UNIT);

        bytes memory sig = signUserDecrypt(AUDITOR_PK, address(token));
        assertEq(_auditorSees(token.confidentialBalanceOf(bob), sig), 800_000 * UNIT);
        assertEq(_auditorSees(token.confidentialBalanceOf(alice), sig), 9_200_000 * UNIT);
    }

    /// And that path really is ACL-checked: the compliance's own accumulator was
    /// never granted, so it fails to decrypt. A missed grant means a blind auditor.
    function test_ungrantedHandleFailsAuditorDecrypt() public {
        _transfer(alice, bob, 500_000 * UNIT);

        bytes32 handle = euint64.unwrap(compliance.totalTransferred());
        bytes memory sig = signUserDecrypt(AUDITOR_PK, address(compliance));

        vm.expectRevert(abi.encodeWithSelector(UserNotAuthorizedForDecrypt.selector, handle, auditor));
        this.userDecryptExternal(handle, auditor, address(compliance), sig);
    }

    /// Amount rules block silently: a failed check lands as zero, never a revert,
    /// so the reason stays private. R4 over the cap, R5 leaving dust, full exit.
    function test_amountRulesBlockSilently() public {
        _transfer(alice, bob, 2_000_000 * UNIT); // over 10% of supply
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 0);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 10_000_000 * UNIT);

        _transfer(dave, bob, 150_000 * UNIT); // would leave dave under the floor
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 0);

        _transfer(dave, bob, 200_000 * UNIT); // full exit
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 200_000 * UNIT);
    }

    /// R5 binds the receiver too, on transfer and on subscription, because the
    /// floor is also the minimum ticket. At the floor exactly, both clear.
    function test_receiverBelowFloorBlocksSilently() public {
        _transfer(alice, bob, 50_000 * UNIT);
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 0);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 10_000_000 * UNIT);

        _mint(bob, 50_000 * UNIT);
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 0);

        _transfer(alice, bob, 100_000 * UNIT); // exactly at the floor
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 100_000 * UNIT);
    }

    /// R4 binds on subscription too, as the brief requires.
    function test_mintOverCapBlocksSilently() public {
        _mint(bob, 2_000_000 * UNIT); // over 10% of the disclosed supply
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 0);

        _mint(bob, 200_000 * UNIT);
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 200_000 * UNIT);
    }

    /// Address rules keep reverting in plaintext alongside the encrypted path.
    function test_addressRulesStillRevert() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(1 * UNIT, alice, address(token));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ConfidentialTrex.IdentityNotVerified.selector, mallory));
        token.confidentialTransfer(mallory, handle, proof);

        vm.prank(agent);
        token.setFrozen(alice, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ConfidentialTrex.WalletFrozen.selector, alice));
        token.confidentialTransfer(bob, handle, proof);
    }

    /// `userDecrypt` is internal, so the negative test needs an external hop for
    /// `vm.expectRevert`.
    function userDecryptExternal(bytes32 handle, address user, address contractAddress, bytes memory sig)
        external
        returns (uint256)
    {
        return userDecrypt(handle, user, contractAddress, sig);
    }

    /// Swaps the host `HCULimit` implementation for one that reports its meter
    /// and enforces `maxDepthPerTx`. The host contract exposes neither, so the
    /// only way at them is the proxy the test harness already put in place.
    function _installHCULimit(uint256 maxDepthPerTx) private returns (HCULimitHarness) {
        address implementation = address(new HCULimitHarness(maxDepthPerTx));
        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(payable(hcuLimitAdd)).upgradeToAndCall(implementation, "");
        return HCULimitHarness(hcuLimitAdd);
    }

    function _transfer(address from, address to, uint64 amount) private {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(amount, from, address(token));
        vm.prank(from);
        token.confidentialTransfer(to, handle, proof);
    }

    function _mint(address to, uint64 amount) private {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(amount, agent, address(token));
        vm.prank(agent);
        token.mint(to, handle, proof);
    }

    function _auditorSees(euint64 handle, bytes memory sig) private returns (uint256) {
        return userDecrypt(euint64.unwrap(handle), auditor, address(token), sig);
    }
}
