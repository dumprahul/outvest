// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";

/// @dev THE WORKED EXAMPLE: 2 USDC / 1k views, cap 300 USDC, default schedule, creator bound at t0, baseline 0.
///      Each target-day observation is preceded by a "filler" report 6 days earlier carrying the same view count
///      so the rolling 7-day minimum filter equals the target value. Snapshots keep lastSnapshotTs fresh.
contract WorkedExampleTest is OutVestBase {
    function _observe(uint256 dayNo, uint64 views_) internal {
        _day(dayNo - 6);
        _snap(VID, views_);
        _day(dayNo);
        _snap(VID, views_);
    }

    function _claimAndGet() internal returns (uint256 paidNow) {
        uint256 before = usdc.balanceOf(alice);
        vault.claim(alice);
        paidNow = usdc.balanceOf(alice) - before;
    }

    function test_WorkedExample() public {
        _fund(300e6);
        _bind(alice, VID, 0); // t0
        assertEq(vault.creatorInfo(alice).boundAt, uint64(T0));

        // ---- day 20, 50k credited views: 100 USDC earned * 113043/1e6 (ramp 7d..30d, 0 -> 200000)
        _observe(20, 50_000);
        assertEq(vault.creatorInfo(alice).creditedViews, 50_000);
        uint256 day20 = vault.claimable(alice);
        // fraction floors to ppm first: floor(100e6 * 113043 / 1e6) = 11_304_300 units, EXACTLY.
        assertEq(day20, 11_304_300, "floor(100e6 * floor(13/23*200000) / 1e6)");
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, day20);
        assertEq(_claimAndGet(), day20);

        // ---- day 30, 100k views: earned 200 USDC * 50% = 100 USDC cumulative
        _observe(30, 100_000);
        assertEq(vault.claimable(alice), 100e6 - day20);
        assertEq(vault.claimable(alice), 88_695_700, "exact: 100e6 - 11_304_300");
        _claimAndGet();
        assertEq(vault.creatorInfo(alice).paid, 100e6);

        // ---- day 60, 140k views: earned 280 USDC * 80% = 224 USDC cumulative (124 more)
        _observe(60, 140_000);
        assertEq(vault.claimable(alice), 124e6);
        assertEq(_claimAndGet(), 124e6);
        assertEq(vault.creatorInfo(alice).paid, 224e6);

        // ---- day 90, 180k views (360 USDC earned, capped to 300): 100% -> 300 USDC cumulative (76 more)
        _observe(90, 180_000);
        assertEq(vault.claimable(alice), 76e6);
        assertEq(_claimAndGet(), 76e6);

        // ---- totals
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.paid, 300e6);
        assertEq(c.remaining, 0);
        assertEq(usdc.balanceOf(alice), 300e6);
        assertEq(vault.totalPaid(), 300e6);
        assertEq(c.creditedViews, 180_000);
        assertEq(vault.liability(), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
        // nothing left to claim even with more views
        _day(91);
        _snap(VID, 500_000);
        assertEq(vault.claimable(alice), 0);
    }
}
