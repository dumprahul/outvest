// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";

contract VaultPayoutTest is OutVestBase {
    // day 8: elapsed 8d => fraction floor(86400*200000/(23*86400)) = 8695 ppm; earned = 50_000 views * 2 / 1k = 100e6
    uint256 internal constant DAY8_CLAIM = 100e6 * 8695 / 1e6; // 869_500

    function _setupAlice() internal {
        _fund(300e6);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 50_000);
    }

    // ------------------------------------------------------------ claim

    function test_Claim_PaysBoundWalletEvenIfCalledByAnotherAddress() public {
        _setupAlice();
        assertEq(vault.claimable(alice), DAY8_CLAIM);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, DAY8_CLAIM);
        vm.prank(stranger);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
        assertEq(usdc.balanceOf(stranger), 0);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.paid, DAY8_CLAIM);
        assertEq(c.remaining, 300e6 - DAY8_CLAIM);
        assertEq(vault.liability(), 300e6 - DAY8_CLAIM);
        assertEq(vault.totalPaid(), DAY8_CLAIM);
        // nothing more accrues at the same instant
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
    }

    function test_Claim_UnboundWalletGetsNothing() public {
        _setupAlice();
        vault.claim(stranger);
        vault.claim(address(0));
        vault.claim(brand);
        assertEq(usdc.balanceOf(stranger), 0);
        assertEq(usdc.balanceOf(brand), 0);
        assertEq(vault.claimable(stranger), 0);
        assertEq(vault.totalPaid(), 0);
    }

    function test_Claim_FrozenWhenSnapshotStale() public {
        _setupAlice();
        uint256 last = vault.lastSnapshotTs();
        vm.warp(last + vault.staleAfter()); // boundary: still live (strict >)
        assertGt(vault.claimable(alice), 0);
        vm.warp(last + vault.staleAfter() + 1);
        assertEq(vault.claimable(alice), 0);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), 0);
        // a fresh snapshot thaws it and the creator catches up to the schedule fraction at the new time
        _snap(VID, 50_000);
        uint256 elapsed = block.timestamp - T0;
        uint256 fraction = 200_000 * (elapsed - 7 days) / 23 days; // ramp 7d..30d, 0 -> 200000
        uint256 expected = 100e6 * fraction / 1e6;
        assertGt(expected, DAY8_CLAIM);
        assertEq(vault.claimable(alice), expected, "caught up, nothing lost while frozen");
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), expected);
    }

    function test_Claim_StaleFreezeAlsoBlocksPayoutReports() public {
        _setupAlice();
        vm.warp(vault.lastSnapshotTs() + vault.staleAfter() + 1);
        _payout(alice);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.totalPaid(), 0);
    }

    function test_Claim_ZeroBeforeAnyCredit() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        _day(3);
        _snap(VID, 9999);
        assertEq(vault.claimable(alice), 0);
    }

    // ------------------------------------------------------------ PayoutFailed

    function test_PayoutFailed_RestoresStateAndEmits() public {
        _setupAlice();
        usdc.setBlocked(alice, true);
        uint256 bal = usdc.balanceOf(address(vault));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(alice, DAY8_CLAIM);
        vault.claim(alice);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.paid, 0);
        assertEq(c.remaining, 300e6);
        assertEq(vault.liability(), 300e6);
        assertEq(vault.totalPaid(), 0);
        assertEq(usdc.balanceOf(address(vault)), bal);
        assertEq(vault.claimable(alice), DAY8_CLAIM);

        usdc.setBlocked(alice, false);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
        assertEq(vault.totalPaid(), DAY8_CLAIM);
    }

    function test_PayoutFailed_WhenTokenReturnsFalse() public {
        _setupAlice();
        usdc.setBlocked(alice, true);
        usdc.setReturnFalse(true);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(alice, DAY8_CLAIM);
        vault.claim(alice);
        assertEq(vault.creatorInfo(alice).paid, 0);
        assertEq(vault.liability(), 300e6);
    }

    function test_PayoutFailed_ViaPayoutReportStillAccepted() public {
        _setupAlice();
        usdc.setBlocked(alice, true);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(alice, DAY8_CLAIM);
        _payout(alice);
        assertEq(vault.totalPaid(), 0);
        assertEq(vault.liability(), 300e6);
    }

    // ------------------------------------------------------------ applyPayout

    function test_ApplyPayout_PaysViaReport() public {
        _setupAlice();
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, DAY8_CLAIM);
        _payout(alice);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
    }

    function test_ApplyPayout_IgnoresUnboundWallets() public {
        _setupAlice();
        address[] memory w = new address[](3);
        w[0] = stranger;
        w[1] = brand;
        w[2] = alice;
        _sendT(4, abi.encode(w));
        assertEq(usdc.balanceOf(stranger), 0);
        assertEq(usdc.balanceOf(brand), 0);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
    }

    function test_ApplyPayout_MinPayoutFloorAppliesToBatchesNotClaims() public {
        CampaignVault.Params memory p = _params();
        p.minPayout = 1e6; // above DAY8_CLAIM
        vault = _newVault(p);
        _setupAlice();
        _payout(alice);
        assertEq(usdc.balanceOf(alice), 0, "below floor: skipped by payout batch");
        assertEq(vault.totalPaid(), 0);
        vault.claim(alice); // self-claim has no floor
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
    }

    function test_ApplyPayout_FloorSatisfiedPays() public {
        CampaignVault.Params memory p = _params();
        p.minPayout = DAY8_CLAIM; // exactly equal passes (strict <)
        vault = _newVault(p);
        _setupAlice();
        _payout(alice);
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
    }

    function test_ApplyPayout_Max25() public {
        vm.prank(receiver);
        assertEq(vault.applyPayout(new address[](26)), bytes32("BATCH_TOO_LARGE"));
        vm.prank(receiver);
        assertEq(vault.applyPayout(new address[](25)), bytes32(0));
        assertEq(vault.MAX_BATCH(), 25);
    }

    function test_ApplyPayout_OverLimitRejectedSoftViaReport() public {
        _setupAlice();
        address[] memory w = new address[](26);
        w[0] = alice;
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 4, bytes32("BATCH_TOO_LARGE"));
        _sendT(4, abi.encode(w));
        assertEq(usdc.balanceOf(alice), 0, "nothing paid from an oversized batch");
        assertEq(vault.totalPaid(), 0);
    }

    function test_ApplyPayout_Pays25Creators() public {
        CampaignVault.Params memory p = _params();
        p.maxCreators = 30;
        vault = _newVault(p);
        _fund(30 * 300e6);
        address[] memory w = new address[](25);
        bytes32[] memory ids = new bytes32[](25);
        uint64[] memory vs = new uint64[](25);
        for (uint256 i; i < 25; ++i) {
            w[i] = address(uint160(0x1000 + i));
            ids[i] = _vid(i);
            vs[i] = 10_000;
            _bind(w[i], ids[i], 0);
        }
        _day(8);
        _sendT(2, abi.encode(ids, vs));
        _sendT(4, abi.encode(w));
        uint256 expected = 20e6 * 8695 / 1e6;
        for (uint256 i; i < 25; ++i) {
            assertEq(usdc.balanceOf(w[i]), expected);
        }
        assertEq(vault.totalPaid(), 25 * expected);
    }

    // ------------------------------------------------------------ settle

    function test_Settle_RevertsBeforeFinalizeAndForUnbound() public {
        _setupAlice();
        vm.expectRevert(CampaignVault.NotFinalized.selector);
        vault.settle(alice);
        _finalizeByDeadman();
        vm.expectRevert(CampaignVault.NotBound.selector);
        vault.settle(stranger);
    }

    function test_Settle_ReleasesUnearnedLiabilityAndPaysOut() public {
        _setupAlice();
        vault.claim(alice); // partial payment first
        _finalizeByDeadman();
        uint256 remaining = 100e6 - DAY8_CLAIM;
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Settled(alice, 100e6, remaining);
        vault.settle(alice);
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(vault.liability(), 0);
        assertEq(vault.settledCount(), 1);
        assertTrue(vault.creatorInfo(alice).settled);
        // idempotent
        vault.settle(alice);
        assertEq(vault.settledCount(), 1);
        assertEq(usdc.balanceOf(alice), 100e6);
        // brand can sweep the unearned 200e6
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 200e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Settle_BlockedWalletKeepsLiabilityForRetry() public {
        _setupAlice();
        _finalizeByDeadman();
        usdc.setBlocked(alice, true);
        vault.settle(alice);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.liability(), 100e6, "earned amount stays reserved");
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 200e6);
        usdc.setBlocked(alice, false);
        vault.settle(alice);
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(vault.liability(), 0);
    }

    // ------------------------------------------------------------ sweep

    function test_Sweep_TooEarlyBeforeDeadline() public {
        _fund(10e6);
        vm.warp(vault.bindDeadline() - 1);
        vm.expectRevert(CampaignVault.TooEarly.selector);
        vault.sweep();
    }

    function test_Sweep_SendsOnlyUnreservedFundsToBrand() public {
        _fund(1000e6);
        _bind(alice, VID, 0);
        vm.warp(vault.bindDeadline());
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Swept(brand, 700e6);
        vm.prank(stranger);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 700e6);
        assertEq(usdc.balanceOf(address(vault)), 300e6);
        assertEq(usdc.balanceOf(stranger), 0);
        // second sweep: nothing unreserved, no revert
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 700e6);
    }

    function test_Sweep_NothingBoundReturnsEverything() public {
        _fund(50e6);
        vm.warp(vault.bindDeadline());
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 50e6);
    }

    // ------------------------------------------------------------ views

    function test_Creators_Pagination() public {
        CampaignVault.Params memory p = _params();
        p.maxCreators = 5;
        vault = _newVault(p);
        _fund(5 * 300e6);
        for (uint256 i; i < 3; ++i) _bind(address(uint160(0x2000 + i)), _vid(i), 0);
        assertEq(vault.creators(0, 50).length, 3);
        assertEq(vault.creators(1, 1).length, 1);
        assertEq(vault.creators(1, 1)[0], address(uint160(0x2001)));
        assertEq(vault.creators(3, 10).length, 0);
        vm.expectRevert(CampaignVault.InvalidPage.selector);
        vault.creators(0, 51);
        vm.expectRevert(CampaignVault.InvalidPage.selector);
        vault.creators(4, 1);
    }
}
