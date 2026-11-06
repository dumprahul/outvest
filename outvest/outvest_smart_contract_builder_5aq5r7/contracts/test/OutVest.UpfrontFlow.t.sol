// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UpfrontBase} from "./OutVest.Upfront.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ScheduleLib} from "../ScheduleLib.sol";

/// @dev Upfront inside the entitlement, stale freeze, settle floor, and full timelines (cap 300e6, upfront 30e6).
contract UpfrontFlowTest is UpfrontBase {
    /// @dev Filler 6 days earlier with the same views so the 7-day rolling minimum equals the target value.
    function _observe(uint256 dayNo, uint64 views_) internal {
        _day(dayNo - 6);
        _snap(VID, views_);
        _day(dayNo);
        _snap(VID, views_);
    }

    function _claimNow() internal returns (uint256 got) {
        uint256 before = usdc.balanceOf(alice);
        vault.claim(alice);
        got = usdc.balanceOf(alice) - before;
        assertLe(vault.creatorInfo(alice).paid, CAP, "paid above cap");
        assertLe(vault.totalPaid(), CAP, "total above cap");
    }

    function _demoSchedule() internal pure returns (ScheduleLib.Segment[] memory s) {
        s = new ScheduleLib.Segment[](4);
        s[0] = ScheduleLib.Segment(0, 250_000, 500_000);
        s[1] = ScheduleLib.Segment(30 days, 500_000, 800_000);
        s[2] = ScheduleLib.Segment(60 days, 800_000, 1_000_000);
        s[3] = ScheduleLib.Segment(90 days, 1_000_000, 1_000_000);
    }

    // ------------------------------------------------------------ entitlement includes upfront

    function test_Upfront_NoDoublePayWhileViewShareBelowUpfront() public {
        _bind(alice, VID, 0);
        _observe(20, 50_000); // 100e6 earned * 113043 ppm = 11_304_300 < 30e6
        assertEq(vault.claimable(alice), 0);
        assertEq(_claimNow(), 0);
        _observe(24, 100_000); // 200e6 * 147826 ppm = 29_565_200 < 30e6 (still inside the upfront)
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.creatorInfo(alice).paid, UP);
        assertEq(usdc.balanceOf(alice), UP);
    }

    function test_Upfront_ViewShareAboveUpfrontPaysOnlyDifference() public {
        _bind(alice, VID, 0);
        _observe(30, 100_000); // 200e6 * 50% = 100e6 entitled
        assertEq(vault.claimable(alice), 100e6 - UP);
        assertEq(_claimNow(), 70e6);
        assertEq(vault.creatorInfo(alice).paid, 100e6);
        assertEq(vault.claimable(alice), 0);
        _observe(90, 1_000_000); // entitled capped at 300e6
        assertEq(vault.claimable(alice), 200e6);
        assertEq(_claimNow(), 200e6);
        assertEq(vault.creatorInfo(alice).paid, CAP);
        assertEq(vault.creatorInfo(alice).remaining, 0);
        assertEq(vault.claimable(alice), 0);
    }

    // ------------------------------------------------------------ blocked + stale

    function test_Upfront_BlockedThenStaleStillClaimableExactly() public {
        _bindAliceBlocked(false);
        _unblockAlice();
        vm.warp(uint256(vault.lastSnapshotTs()) + vault.staleAfter() + 1);
        assertEq(vault.claimable(alice), UP, "stale: only upfront");
        uint256 before = vault.totalPaid();
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.totalPaid() - before, UP);
        assertEq(vault.creatorInfo(alice).remaining, CAP - UP);
        assertEq(vault.liability(), CAP - UP);
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), UP, "no second pay");
    }

    function test_Upfront_StaleFreezeBlocksViewShareButNotUpfront() public {
        _bindAliceBlocked(true);
        _unblockAlice();
        _observe(30, 100_000);
        assertEq(vault.claimable(alice), 100e6, "fresh: view share dominates, paid is 0");
        vm.warp(uint256(vault.lastSnapshotTs()) + vault.staleAfter() + 1);
        assertEq(vault.claimable(alice), UP, "stale: view share frozen, upfront stays");
        assertEq(_claimNow(), UP);
        assertEq(vault.claimable(alice), 0);
    }

    function test_Upfront_StaleAfterUpfrontPaidClaimsNothing() public {
        _bind(alice, VID, 0);
        _observe(30, 100_000);
        vm.warp(uint256(vault.lastSnapshotTs()) + vault.staleAfter() + 1);
        assertEq(vault.claimable(alice), 0);
        assertEq(_claimNow(), 0);
        assertEq(usdc.balanceOf(alice), UP);
    }

    // ------------------------------------------------------------ settle floor

    function test_Upfront_SettleWithUnpaidUpfrontPaysItAndReleasesRest() public {
        _freshVault(_upParams(100_000), 0);
        _fund(300e6);
        _bindAliceBlocked(false);
        assertEq(vault.liability(), CAP);
        _unblockAlice();
        _finalizeByDeadman(); // zero views ever reported
        uint256 liabBefore = vault.liability();

        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Settled(alice, UP, UP);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, UP);
        vault.settle(alice);

        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.settled);
        assertEq(c.paid, UP);
        assertEq(c.remaining, 0);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(liabBefore - vault.liability(), CAP, "30e6 paid + 270e6 released");
        assertEq(vault.liability(), 0);
        assertEq(usdc.balanceOf(address(vault)), CAP - UP);

        vault.sweep();
        assertEq(usdc.balanceOf(brand), CAP - UP, "270e6 back to brand");
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Upfront_SettleWhileStillBlockedKeepsUpfrontClaimable() public {
        _freshVault(_upParams(100_000), 300e6);
        _bindAliceBlocked(false);
        _finalizeByDeadman();
        vault.settle(alice); // transfer fails again
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.settled);
        assertEq(c.paid, 0);
        assertEq(c.remaining, UP, "270e6 released, upfront kept");
        assertEq(vault.liability(), UP);
        _unblockAlice();
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.liability(), 0);
    }

    function test_Upfront_SettlePaidUpfrontZeroViewsLeavesNothing() public {
        _freshVault(_upParams(100_000), 300e6);
        _bind(alice, VID, 0);
        _finalizeByDeadman();
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Settled(alice, UP, 0);
        vault.settle(alice);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.paid, UP);
        assertEq(c.remaining, 0);
        assertEq(vault.liability(), 0);
        assertEq(usdc.balanceOf(alice), UP);
        assertEq(vault.claimable(alice), 0);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), CAP - UP);
    }

    // ------------------------------------------------------------ full timelines

    /// @dev Demo schedule (0,25%->50%),(30d,50%->80%),(60d,80%->100%),(90d,100%). 2 USDC / 1k views.
    function test_Upfront_FullTimelineDemoSchedule() public {
        CampaignVault.Params memory p = _upParams(100_000);
        p.schedule = _demoSchedule();
        _freshVault(p, 900e6);
        _bind(alice, VID, 0);
        assertEq(vault.creatorInfo(alice).paid, UP);

        _observe(15, 30_000); // 60e6 * 375000 ppm = 22.5e6 < upfront
        assertEq(vault.claimable(alice), 0);
        assertEq(_claimNow(), 0);

        _observe(30, 75_000); // 150e6 * 500000 ppm = 75e6
        assertEq(_claimNow(), 45e6);
        assertEq(vault.creatorInfo(alice).paid, 75e6);

        _observe(60, 120_000); // 240e6 * 800000 ppm = 192e6
        assertEq(_claimNow(), 117e6);
        assertEq(vault.creatorInfo(alice).paid, 192e6);

        _observe(90, 200_000); // 400e6 capped 300e6 * 100%
        assertEq(_claimNow(), 108e6);
        assertEq(vault.creatorInfo(alice).paid, CAP);

        vm.warp(_finalTime());
        _final(VID, 200_000);
        assertTrue(vault.finalized());
        vault.settle(alice);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.paid, CAP);
        assertEq(c.remaining, 0);
        assertEq(vault.totalPaid(), CAP);
        assertEq(usdc.balanceOf(alice), CAP);
        assertEq(vault.liability(), 0);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 600e6);
    }

    function test_Upfront_FullTimelineDefaultSchedule() public {
        _bind(alice, VID, 0);
        _observe(20, 50_000); // 11_304_300 < upfront -> nothing
        assertEq(_claimNow(), 0);
        assertEq(vault.creatorInfo(alice).paid, UP);

        _observe(30, 100_000); // 100e6
        assertEq(_claimNow(), 70e6);
        assertEq(vault.creatorInfo(alice).paid, 100e6);

        _observe(60, 140_000); // 224e6
        assertEq(_claimNow(), 124e6);
        assertEq(vault.creatorInfo(alice).paid, 224e6);

        _observe(90, 180_000); // 300e6
        assertEq(_claimNow(), 76e6);
        assertEq(vault.creatorInfo(alice).paid, CAP);

        vm.warp(_finalTime());
        _final(VID, 180_000);
        vault.settle(alice);
        assertEq(vault.creatorInfo(alice).paid, CAP);
        assertEq(vault.creatorInfo(alice).remaining, 0);
        assertEq(vault.totalPaid(), CAP);
        assertEq(usdc.balanceOf(alice), CAP);
        assertEq(vault.liability(), 0);
    }

    function test_Upfront_FinalizeAfterPartialViewsPaysEntitlementOnce() public {
        _bind(alice, VID, 0);
        _observe(30, 100_000); // not claimed; claimable = 70e6 on top of upfront
        vm.warp(_finalTime());
        _final(VID, 100_000); // 200e6 earned, finalized -> fraction 100%
        vault.settle(alice);
        assertEq(vault.creatorInfo(alice).paid, 200e6);
        assertEq(usdc.balanceOf(alice), 200e6);
        assertEq(vault.creatorInfo(alice).remaining, 0);
        assertEq(vault.liability(), 0);
    }
}
