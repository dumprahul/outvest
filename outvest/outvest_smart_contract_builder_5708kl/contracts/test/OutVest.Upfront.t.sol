// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";

/// @dev Instant settlement: a capped upfront share is paid in the same transaction as the BIND report.
contract UpfrontTest is OutVestBase {
    uint256 internal constant UPFRONT = 30e6; // 10% of the 300e6 cap

    CampaignVault internal uv;

    function setUp() public override {
        super.setUp();
        CampaignVault.Params memory p = _params();
        p.upfrontPpm = 100_000;
        uv = _newVault(p);
        _fundVault(uv, 1_000e6);
    }

    function _bindU(address w, bytes32 vid, uint64 baseline) internal {
        vm.prank(w);
        bytes32 ch = uv.requestBinding(vid);
        _sendTo(uv, 1, _bindPayload(w, vid, ch, baseline));
    }

    function test_Upfront_PaidInSameTxAsBind() public {
        _bindU(alice, VID, 1_000);
        assertEq(usdc.balanceOf(alice), UPFRONT);
        CampaignVault.Creator memory c = uv.creatorInfo(alice);
        assertEq(c.paid, UPFRONT);
        assertEq(c.remaining, 300e6 - UPFRONT);
        assertEq(uv.liability(), 300e6 - UPFRONT);
        assertEq(uv.totalPaid(), UPFRONT);
        assertEq(usdc.balanceOf(address(uv)), 1_000e6 - UPFRONT);
    }

    function test_Upfront_EmitsPaid() public {
        vm.prank(alice);
        bytes32 ch = uv.requestBinding(VID);
        vm.expectEmit(true, false, false, true, address(uv));
        emit CampaignVault.Paid(alice, UPFRONT);
        _sendTo(uv, 1, _bindPayload(alice, VID, ch, 0));
    }

    function test_Upfront_OnlyOnFirstVideo() public {
        _bindU(alice, VID, 0);
        _bindU(alice, VID2, 0);
        assertEq(usdc.balanceOf(alice), UPFRONT);
        assertEq(uv.creatorInfo(alice).videoCount, 2);
    }

    function test_Upfront_EachCreatorGetsOwnShare() public {
        _bindU(alice, VID, 0);
        _bindU(bob, VID2, 0);
        assertEq(usdc.balanceOf(alice), UPFRONT);
        assertEq(usdc.balanceOf(bob), UPFRONT);
        assertEq(uv.totalPaid(), 2 * UPFRONT);
    }

    function test_Upfront_ZeroByDefaultPaysNothingOnBind() public {
        _fund(1_000e6);
        _bind(alice, VID, 0);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_Upfront_NotPaidTwiceOnceViewsEarn() public {
        _bindU(alice, VID, 0);
        // Views reach the cap after the lag window, but the schedule is still near 0%: upfront floor, no extra.
        for (uint256 d = 1; d <= 8; ++d) {
            _day(d);
            _sendTo(uv, 2, _snapPayload(VID, 150_000));
        }
        assertEq(uv.claimable(alice), 0);
        uv.claim(alice);
        assertEq(usdc.balanceOf(alice), UPFRONT);

        // At day 60 the schedule is 80%: entitled 240e6 in total, upfront counts toward it.
        _day(60);
        _sendTo(uv, 2, _snapPayload(VID, 150_000));
        assertEq(uv.claimable(alice), 240e6 - UPFRONT);
        uv.claim(alice);
        assertEq(usdc.balanceOf(alice), 240e6);
    }

    function test_Upfront_StaysClaimableWhenSnapshotsGoStale() public {
        // Make the instant transfer fail, then confirm the amount is still claimable with no fresh snapshot.
        usdc.setBlocked(alice, true);
        _bindU(alice, VID, 0);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(uv.creatorInfo(alice).paid, 0);
        assertEq(uv.liability(), 300e6);

        usdc.setBlocked(alice, false);
        vm.warp(block.timestamp + 30 days); // far past staleAfter, no snapshots sent
        assertEq(uv.claimable(alice), UPFRONT);
        uv.claim(alice);
        assertEq(usdc.balanceOf(alice), UPFRONT);
    }

    function test_Upfront_FailedTransferStillBinds() public {
        usdc.setBlocked(alice, true);
        _bindU(alice, VID, 0);
        assertTrue(uv.creatorInfo(alice).bound);
        assertEq(uv.videoOwner(VID), alice);
    }

    function test_Upfront_FinalSettlementNeverBelowUpfront() public {
        _bindU(alice, VID, 0); // no views ever
        vm.warp(uint256(uv.bindDeadline()) + uv.scheduleLength() + uv.deadmanTimeout());
        uv.finalizeFromLastSnapshot();
        uv.settle(alice);
        assertEq(usdc.balanceOf(alice), UPFRONT);
        assertEq(uv.creatorInfo(alice).remaining, 0);
        assertEq(uv.liability(), 0);
        uv.sweep();
        assertEq(usdc.balanceOf(brand), 1_000e6 - UPFRONT);
    }

    function test_Upfront_TotalNeverExceedsCap() public {
        _bindU(alice, VID, 0);
        for (uint256 d = 1; d <= 8; ++d) {
            _day(d);
            _sendTo(uv, 2, _snapPayload(VID, 150_000));
        }
        _day(120);
        _sendTo(uv, 2, _snapPayload(VID, 150_000));
        uv.claim(alice);
        assertLe(usdc.balanceOf(alice), 300e6);
        assertEq(usdc.balanceOf(alice), 300e6);
    }

    function test_Upfront_RejectsAboveTenPercent() public {
        CampaignVault.Params memory p = _params();
        p.upfrontPpm = 100_001;
        vm.expectRevert(CampaignFactory.InvalidParams.selector);
        factory.createCampaign(p);
    }

    function test_Upfront_IncludedInRulesHash() public {
        CampaignVault.Params memory a = _params();
        CampaignVault.Params memory b = _params();
        b.upfrontPpm = 50_000;
        assertTrue(_newVault(a).rulesHash() != _newVault(b).rulesHash());
    }
}
