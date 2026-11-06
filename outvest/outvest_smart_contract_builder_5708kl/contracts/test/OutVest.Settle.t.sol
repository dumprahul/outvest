// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";

/// @dev Finalize paths, settle + sweep lifecycle, direct donations and blocklisted recipients.
contract VaultSettleTest is OutVestBase {
    // day 8, 50k credited views, default schedule: floor(100e6 * 8695 / 1e6)
    uint256 internal constant DAY8_CLAIM = 869_500;

    function _setupAlice() internal {
        _fund(300e6);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 50_000);
    }

    /// @dev alice, bob, carol bound at T0 with 50k views each observed on day 8. Vault funded with `funding`.
    function _threeCreators(uint256 funding) internal returns (bytes32[] memory ids) {
        _fund(funding);
        ids = new bytes32[](3);
        ids[0] = _vid(0);
        ids[1] = _vid(1);
        ids[2] = _vid(2);
        _bind(alice, ids[0], 0);
        _bind(bob, ids[1], 0);
        _bind(carol, ids[2], 0);
        _day(8);
        uint64[] memory vs = new uint64[](3);
        vs[0] = 50_000;
        vs[1] = 50_000;
        vs[2] = 50_000;
        _sendT(2, abi.encode(ids, vs));
    }

    function _three() internal view returns (address[] memory w) {
        w = new address[](3);
        w[0] = alice;
        w[1] = bob;
        w[2] = carol;
    }

    // ------------------------------------------------------------ finalize paths

    function test_Finalize_ApplyFinalEmitsDeadmanFalse() public {
        _setupAlice();
        vm.warp(_finalTime());
        vm.expectEmit(false, false, false, true, address(vault));
        emit CampaignVault.Finalized(uint64(block.timestamp), false);
        _final(VID, 60_000);
        assertTrue(vault.finalized());
        assertEq(vault.finalizedAt(), uint64(block.timestamp));
        assertEq(vault.creatorInfo(alice).creditedViews, 60_000);
    }

    function test_Finalize_FromLastSnapshotEmitsDeadmanTrue() public {
        _setupAlice();
        vm.warp(_finalTime() + vault.deadmanTimeout());
        vm.expectEmit(false, false, false, true, address(vault));
        emit CampaignVault.Finalized(uint64(block.timestamp), true);
        vault.finalizeFromLastSnapshot();
        assertTrue(vault.finalized());
        assertEq(vault.finalizedAt(), uint64(block.timestamp));
        assertEq(vault.creatorInfo(alice).creditedViews, 50_000, "deadman keeps the last snapshot credit");
    }

    function test_Finalize_FinalizedAtIsZeroUntilFinalized() public {
        _setupAlice();
        assertEq(vault.finalizedAt(), 0);
        assertFalse(vault.finalized());
    }

    function test_Finalize_SecondFinalRejectedSoft() public {
        _setupAlice();
        vm.warp(_finalTime());
        _final(VID, 60_000);
        uint64 at = vault.finalizedAt();
        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 3, bytes32("FINALIZED"));
        _final(VID, 70_000);
        assertEq(vault.finalizedAt(), at);
        assertEq(vault.creatorInfo(alice).creditedViews, 60_000);
    }

    function test_Finalize_TooEarlyViaReport() public {
        _setupAlice();
        vm.warp(_finalTime() - 1);
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 3, bytes32("FINAL_TOO_EARLY"));
        _final(VID, 60_000);
        assertFalse(vault.finalized());
    }

    function test_Finalize_PaysFullEarnedRegardlessOfSchedule() public {
        _setupAlice();
        vm.warp(_finalTime());
        _final(VID, 50_000);
        assertEq(vault.claimable(alice), 100e6);
    }

    // ------------------------------------------------------------ settle + sweep

    function test_SettleThenSweep_ReturnsUnearnedToBrand() public {
        _fund(1000e6);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 50_000);
        _finalizeByDeadman();
        vault.settle(alice);
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(vault.liability(), 0);
        assertEq(vault.settledCount(), 1);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 900e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Sweep_BeforeSettleKeepsFullCapReserved() public {
        _fund(1000e6);
        _bind(alice, VID, 0);
        _finalizeByDeadman();
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 700e6, "alice's 300e6 cap still reserved until settled");
        vault.settle(alice); // earned 0 -> releases the reservation
        assertEq(vault.liability(), 0);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 1000e6);
    }

    function test_Sweep_RepeatedAfterBindDeadlineAllowed() public {
        _fund(500e6);
        _bind(alice, VID, 0);
        vm.warp(vault.bindDeadline());
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 200e6);
        // further sweeps are no-ops without reverting
        vault.sweep();
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 200e6);
        assertEq(usdc.balanceOf(address(vault)), 300e6);
    }

    function test_Sweep_DirectDonationCountsAsSurplus() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        vm.warp(vault.bindDeadline());
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 0);
        usdc.mint(stranger, 7e6);
        vm.prank(stranger);
        usdc.transfer(address(vault), 7e6); // bypasses fund()
        assertEq(vault.totalFunded(), 300e6, "donation not in totalFunded");
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Swept(brand, 7e6);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 7e6);
        assertEq(vault.liability(), 300e6);
        assertEq(usdc.balanceOf(address(vault)), 300e6);
    }

    function test_Sweep_DonationDoesNotInflateBudgetCheckBeyondBalance() public {
        usdc.mint(address(vault), 300e6); // donated, never funded
        bytes32 ch = _request(alice, VID);
        assertEq(_applyBind(alice, VID, ch, 0), bytes32(0), "balance (not totalFunded) backs the reserve");
        assertEq(vault.liability(), 300e6);
    }

    function test_Sweep_BlockedBrandEmitsPayoutFailedAndKeepsFunds() public {
        _fund(50e6);
        vm.warp(vault.bindDeadline());
        usdc.setBlocked(brand, true);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(brand, 50e6);
        vault.sweep();
        assertEq(usdc.balanceOf(address(vault)), 50e6);
        usdc.setBlocked(brand, false);
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 50e6);
    }

    // ------------------------------------------------------------ blocklist

    function test_Blocklist_BatchContinuesPastFailedWallet() public {
        _threeCreators(1000e6);
        usdc.setBlocked(bob, true);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(alice, DAY8_CLAIM);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.PayoutFailed(bob, DAY8_CLAIM);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Paid(carol, DAY8_CLAIM);
        _sendT(4, abi.encode(_three()));

        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(carol), DAY8_CLAIM, "later wallet still paid");
        CampaignVault.Creator memory c = vault.creatorInfo(bob);
        assertEq(c.paid, 0, "state rolled back");
        assertEq(c.remaining, 300e6);
        assertEq(vault.totalPaid(), 2 * DAY8_CLAIM);
        assertEq(vault.liability(), 900e6 - 2 * DAY8_CLAIM);
        assertEq(vault.claimable(bob), DAY8_CLAIM, "still claimable once unblocked");
    }

    function test_Blocklist_SweepExcludesBlockedCreatorsReservedRemaining() public {
        _threeCreators(1000e6);
        usdc.setBlocked(bob, true);
        _sendT(4, abi.encode(_three()));
        assertGt(block.timestamp, vault.bindDeadline());
        vault.sweep();
        // surplus = 1000e6 - 900e6 reserved (bob's full 300e6 remaining stays reserved)
        assertEq(usdc.balanceOf(brand), 100e6);
        assertEq(usdc.balanceOf(address(vault)), vault.liability());
        assertGe(usdc.balanceOf(address(vault)), vault.creatorInfo(bob).remaining);

        usdc.setBlocked(bob, false);
        vault.claim(bob);
        assertEq(usdc.balanceOf(bob), DAY8_CLAIM);
    }

    function test_Blocklist_ReturnFalseTokenAlsoRollsBackBatchEntry() public {
        _threeCreators(1000e6);
        usdc.setBlocked(bob, true);
        usdc.setReturnFalse(true);
        _sendT(4, abi.encode(_three()));
        assertEq(usdc.balanceOf(alice), DAY8_CLAIM);
        assertEq(usdc.balanceOf(carol), DAY8_CLAIM);
        assertEq(vault.creatorInfo(bob).paid, 0);
        assertEq(vault.liability(), 900e6 - 2 * DAY8_CLAIM);
    }

    function test_Blocklist_SettleKeepsBlockedCreatorReservedAcrossSweep() public {
        _threeCreators(1000e6);
        _finalizeByDeadman();
        usdc.setBlocked(bob, true);
        vault.settle(alice);
        vault.settle(bob);
        vault.settle(carol);
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(usdc.balanceOf(carol), 100e6);
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(vault.liability(), 100e6, "only bob's earned amount stays reserved");
        vault.sweep();
        assertEq(usdc.balanceOf(brand), 700e6);
        assertEq(usdc.balanceOf(address(vault)), 100e6);
        usdc.setBlocked(bob, false);
        vault.settle(bob);
        assertEq(usdc.balanceOf(bob), 100e6);
        assertEq(vault.liability(), 0);
    }
}
