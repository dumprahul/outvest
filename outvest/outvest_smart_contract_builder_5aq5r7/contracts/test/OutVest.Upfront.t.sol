// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";

/// @dev Shared fixture for the instant-settlement (upfront) suites: vault with upfrontPpm = 100_000, cap 300e6 -> 30e6.
abstract contract UpfrontBase is OutVestBase {
    uint256 internal constant UP = 30e6;
    uint256 internal constant CAP = 300e6;
    bytes32 internal constant PAID_SIG = keccak256("Paid(address,uint256)");

    function setUp() public virtual override {
        super.setUp();
        vault = _newVault(_upParams(100_000));
        _fund(900e6);
    }

    function _upParams(uint32 ppm) internal view returns (CampaignVault.Params memory p) {
        p = _params();
        p.upfrontPpm = ppm;
    }

    function _freshVault(CampaignVault.Params memory p, uint256 funding) internal {
        vault = _newVault(p);
        if (funding != 0) _fund(funding);
    }

    function _paidLogs(Vm.Log[] memory logs) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == PAID_SIG) ++n;
        }
    }

    /// @dev alice's upfront transfer is rejected (revert or `false` mode) when she is bound.
    function _bindAliceBlocked(bool returnFalse) internal {
        usdc.setBlocked(alice, true);
        usdc.setReturnFalse(returnFalse);
        bytes32 ch = _request(alice, VID);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(alice, UP);
        _sendT(1, _bindPayload(alice, VID, ch, 0));
    }

    function _unblockAlice() internal {
        usdc.setBlocked(alice, false);
        usdc.setReturnFalse(false);
    }
}

contract UpfrontBindTest is UpfrontBase {
    // ------------------------------------------------------------ paid at bind

    function test_Upfront_PaidInSameTxAsBind() public {
        bytes32 ch = _request(alice, VID);
        vm.expectEmit(true, true, false, true, address(vault));
        emit CampaignVault.Bound(alice, VID, 0, uint64(T0));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, UP);
        _sendT(1, _bindPayload(alice, VID, ch, 0));

        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.bound);
        assertEq(c.upfront, UP);
        assertEq(c.paid, UP);
        assertEq(c.remaining, CAP - UP);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.liability(), CAP - UP);
        assertEq(vault.totalPaid(), UP);
        assertGe(usdc.balanceOf(address(vault)), vault.liability());
        assertEq(usdc.balanceOf(address(vault)), 900e6 - UP);
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.upfrontPpm(), 100_000);
    }

    function test_Upfront_SecondVideoPaysNothingExtraAndKeepsBoundAt() public {
        _bind(alice, VID, 0);
        _day(2);
        vm.recordLogs();
        _bind(alice, VID2, 5);
        assertEq(_paidLogs(vm.getRecordedLogs()), 0, "second video must not emit Paid");

        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.videoCount, 2);
        assertEq(c.boundAt, uint64(T0));
        assertEq(c.paid, UP);
        assertEq(c.remaining, CAP - UP);
        assertEq(c.upfront, UP);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.liability(), CAP - UP);
        assertEq(vault.totalPaid(), UP);
    }

    function test_Upfront_SecondCreatorGetsOwnUpfront() public {
        _bind(alice, VID, 0);
        _bind(bob, VID2, 0);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(usdc.balanceOf(bob), UP);
        assertEq(vault.creatorInfo(bob).paid, UP);
        assertEq(vault.creatorInfo(bob).remaining, CAP - UP);
        assertEq(vault.liability(), 2 * (CAP - UP));
        assertEq(vault.totalPaid(), 2 * UP);
        assertGe(usdc.balanceOf(address(vault)), vault.liability());
    }

    function test_Upfront_BypassesMinPayoutFloor() public {
        CampaignVault.Params memory p = _upParams(100_000);
        p.minPayout = 100e6;
        _freshVault(p, 900e6);
        assertGt(vault.minPayout(), UP);
        _bind(alice, VID, 0);
        assertEq(usdc.balanceOf(alice), UP, "upfront ignores minPayout");
        assertEq(vault.creatorInfo(alice).paid, UP);
    }

    function test_Upfront_ZeroPpmBehavesAsBefore() public {
        _freshVault(_upParams(0), 900e6);
        assertEq(vault.upfrontPpm(), 0);
        vm.recordLogs();
        _bind(alice, VID, 0);
        assertEq(_paidLogs(vm.getRecordedLogs()), 0);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.bound);
        assertEq(c.upfront, 0);
        assertEq(c.paid, 0);
        assertEq(c.remaining, CAP);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.liability(), CAP);
        assertEq(vault.totalPaid(), 0);
        assertEq(vault.claimable(alice), 0);
    }

    // ------------------------------------------------------------ bounds

    function test_Upfront_BoundaryAcceptedByFactoryAndVault() public {
        assertEq(vault.MAX_UPFRONT_PPM(), 100_000);
        CampaignVault v = _newVault(_upParams(100_000));
        assertEq(v.upfrontPpm(), 100_000);
        CampaignVault d = new CampaignVault(_upParams(100_000), receiver, address(factory), bytes32(0));
        assertEq(d.upfrontPpm(), 100_000);
    }

    function test_Upfront_AboveMaxRejectedByFactory() public {
        vm.expectRevert(CampaignFactory.InvalidParams.selector);
        factory.createCampaign(_upParams(100_001));
        vm.expectRevert(CampaignFactory.InvalidParams.selector);
        factory.createCampaign(_upParams(type(uint32).max));
    }

    function test_Upfront_AboveMaxRejectedByVaultConstructor() public {
        vm.expectRevert(CampaignVault.InvalidParams.selector);
        new CampaignVault(_upParams(100_001), receiver, address(factory), bytes32(0));
        vm.expectRevert(CampaignVault.InvalidParams.selector);
        new CampaignVault(_upParams(type(uint32).max), receiver, address(factory), bytes32(0));
    }

    function testFuzz_Upfront_PpmBoundEnforcedEverywhere(uint32 ppm) public {
        CampaignVault.Params memory p = _upParams(ppm);
        if (ppm > 100_000) {
            vm.expectRevert(CampaignFactory.InvalidParams.selector);
            factory.createCampaign(p);
            vm.expectRevert(CampaignVault.InvalidParams.selector);
            new CampaignVault(p, receiver, address(factory), bytes32(0));
        } else {
            assertEq(_newVault(p).upfrontPpm(), ppm);
            assertEq(new CampaignVault(p, receiver, address(factory), bytes32(0)).upfrontPpm(), ppm);
        }
    }

    // ------------------------------------------------------------ rounding

    function test_Upfront_CapRoundsDown() public {
        CampaignVault.Params memory p = _upParams(100_000);
        p.capPerCreator = 12_345_679; // 10% = 1_234_567.9
        _freshVault(p, 12_345_679);
        _bind(alice, VID, 0);
        assertEq(vault.creatorInfo(alice).upfront, 1_234_567);
        assertEq(usdc.balanceOf(alice), 1_234_567);
        assertEq(vault.liability(), 12_345_679 - 1_234_567);

        p = _upParams(33_333);
        p.capPerCreator = 100; // 3.3333 -> 3
        _freshVault(p, 100);
        _bind(bob, VID2, 0);
        assertEq(vault.creatorInfo(bob).upfront, 3);
        assertEq(usdc.balanceOf(bob), 3);
    }

    function testFuzz_Upfront_AmountIsFlooredShareOfCap(uint256 cap, uint32 ppm) public {
        cap = bound(cap, 1, 1e12);
        ppm = uint32(bound(ppm, 0, 100_000));
        CampaignVault.Params memory p = _upParams(ppm);
        p.capPerCreator = cap;
        _freshVault(p, cap);
        _bind(alice, VID, 0);
        uint256 up = cap * ppm / 1_000_000;
        assertEq(vault.creatorInfo(alice).upfront, up);
        assertEq(usdc.balanceOf(alice), up);
        assertEq(vault.creatorInfo(alice).paid, up);
        assertEq(vault.liability(), cap - up);
        assertLe(up * 10, cap);
        assertGe(usdc.balanceOf(address(vault)), vault.liability());
    }

    // ------------------------------------------------------------ misc views

    function test_Upfront_CreatorInfoReturnsUpfront() public {
        assertEq(vault.creatorInfo(alice).upfront, 0, "unbound has no upfront");
        assertEq(vault.claimable(alice), 0, "unbound claimable is 0");
        _bind(alice, VID, 0);
        assertEq(vault.creatorInfo(alice).upfront, UP);
    }

    function test_Upfront_RulesHashDiffersByUpfrontPpm() public {
        CampaignVault a = _newVault(_upParams(0));
        CampaignVault b = _newVault(_upParams(100_000));
        CampaignVault b2 = _newVault(_upParams(100_000));
        assertTrue(a.rulesHash() != b.rulesHash());
        assertEq(b.rulesHash(), b2.rulesHash(), "control: identical params hash identically");
    }

    // ------------------------------------------------------------ no double pay

    function test_Upfront_ClaimAndPayoutAfterBindDoNotDoublePay() public {
        _bind(alice, VID, 0);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), UP);
        _payout(alice);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.creatorInfo(alice).paid, UP);
        assertEq(vault.totalPaid(), UP);
        assertEq(vault.liability(), CAP - UP);
    }

    // ------------------------------------------------------------ blocked wallet

    function _checkRestoredAfterFailedUpfront() internal view {
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.bound, "still bound");
        assertEq(c.upfront, UP);
        assertEq(c.paid, 0);
        assertEq(c.remaining, CAP);
        assertEq(vault.liability(), CAP);
        assertEq(vault.totalPaid(), 0);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.claimable(alice), UP, "upfront claimable after failure");
        assertGe(usdc.balanceOf(address(vault)), vault.liability());
    }

    function test_Upfront_BlockedWalletBindSucceedsStateRestored_Revert() public {
        _bindAliceBlocked(false);
        _checkRestoredAfterFailedUpfront();
    }

    function test_Upfront_BlockedWalletBindSucceedsStateRestored_ReturnFalse() public {
        _bindAliceBlocked(true);
        _checkRestoredAfterFailedUpfront();
    }

    function test_Upfront_FailedUpfrontNotRetriedOnSecondBind() public {
        _bindAliceBlocked(false);
        _unblockAlice();
        _bind(alice, VID2, 0); // videoCount == 2 -> no upfront attempt
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.creatorInfo(alice).paid, 0);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.creatorInfo(alice).paid, UP);
    }
}
