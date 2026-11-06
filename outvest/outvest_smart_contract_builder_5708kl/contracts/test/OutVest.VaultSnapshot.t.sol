// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";

contract VaultSnapshotTest is OutVestBase {
    function _credited() internal view returns (uint256) {
        return vault.creatorInfo(alice).creditedViews;
    }

    function _bindAlice(uint64 baseline) internal {
        _fund(300e6);
        _bind(alice, VID, baseline);
    }

    function _growthVault(uint64 growth) internal {
        CampaignVault.Params memory p = _params();
        p.maxGrowthPerDay = growth;
        vault = _newVault(p);
    }

    // ------------------------------------------------------------ snapshots

    function test_Snapshot_BindBucketFloorsFirstWeek() public {
        _bindAlice(100);
        _day(3);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.SnapshotApplied(uint64(block.timestamp), 1, false);
        _snap(VID, 5000);
        assertEq(_credited(), 0, "baseline bucket is still inside the 7-day window");
        assertEq(vault.lastSnapshotTs(), uint64(block.timestamp));
    }

    function test_Snapshot_CreditsNetOfBaselineOnceBindBucketExpires() public {
        _bindAlice(100);
        _day(8);
        _snap(VID, 5000);
        assertEq(_credited(), 4900);
        assertEq(vault.videoInfo(VID).credited, 4900);
        assertEq(vault.videoInfo(VID).lastUpdateTs, uint64(block.timestamp));
    }

    function test_Snapshot_SpikeIsFilteredByRollingMinimum() public {
        _bindAlice(0);
        _day(8);
        _snap(VID, 1000);
        assertEq(_credited(), 1000);
        _day(9);
        _snap(VID, 50_000); // spike: window min is yesterday's 1000
        assertEq(_credited(), 1000);
        _day(10);
        _snap(VID, 800); // genuine drop is honoured immediately
        assertEq(_credited(), 800);
    }

    function test_Snapshot_SameBucketKeepsMinimum() public {
        _bindAlice(0);
        _day(8);
        _snap(VID, 5000);
        vm.warp(block.timestamp + 1 hours);
        _snap(VID, 3000);
        vm.warp(block.timestamp + 1 hours);
        _snap(VID, 9000);
        assertEq(_credited(), 3000);
        CampaignVault.VideoState memory v = vault.videoInfo(VID);
        assertEq(v.bucketMin[(block.timestamp / 86400) % 7], 3000);
    }

    function test_Snapshot_GrowthAllowanceCapsIncrease() public {
        _growthVault(1000);
        _bindAlice(0);
        _day(8);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 8000, "8 days * 1000/day");
        _day(9);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 9000, "+1 day * 1000/day");
    }

    function test_Snapshot_GrowthAllowanceElapsedCappedAt14Days() public {
        _growthVault(1000);
        _bindAlice(0);
        _day(20);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 14_000);
    }

    function test_Snapshot_UnknownVideoSkipped() public {
        _bindAlice(0);
        _day(8);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = VID2; // never bound
        ids[1] = VID;
        uint64[] memory vs = new uint64[](2);
        vs[0] = 999;
        vs[1] = 2000;
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.SnapshotApplied(uint64(block.timestamp), 2, false);
        _sendT(2, abi.encode(ids, vs));
        assertEq(_credited(), 2000);
        assertEq(vault.videoOwner(VID2), address(0));
        assertEq(vault.videoInfo(VID2).lastUpdateTs, 0);
    }

    function test_Snapshot_OldTimestampSkippedPerVideo() public {
        _bindAlice(0);
        _day(9);
        assertEq(_direct(VID, 2000, uint64(block.timestamp)), bytes32(0));
        assertEq(_credited(), 2000);
        uint64 last = vault.lastSnapshotTs();
        // older than the video's lastUpdateTs: skipped, no effect, lastSnapshotTs not rolled back
        assertEq(_direct(VID, 1, uint64(T0 + 8 days)), bytes32(0));
        assertEq(_credited(), 2000);
        assertEq(vault.videoInfo(VID).lastUpdateTs, uint64(block.timestamp));
        assertEq(vault.lastSnapshotTs(), last);
        // ts before the bind itself is also ignored
        assertEq(_direct(VID, 1, uint64(T0 - 1)), bytes32(0));
        assertEq(_credited(), 2000);
    }

    function test_Snapshot_LengthMismatchAndBatchLimit() public {
        _bindAlice(0);
        uint64 before = vault.lastSnapshotTs();
        vm.prank(receiver);
        assertEq(vault.applySnapshot(_ids(VID), new uint64[](2), uint64(T0 + 1 days)), bytes32("LENGTH_MISMATCH"));
        vm.prank(receiver);
        assertEq(
            vault.applySnapshot(new bytes32[](51), new uint64[](51), uint64(T0 + 1 days)), bytes32("BATCH_TOO_LARGE")
        );
        assertEq(vault.lastSnapshotTs(), before);
        vm.prank(receiver);
        assertEq(vault.applySnapshot(new bytes32[](50), new uint64[](50), uint64(T0 + 1 days)), bytes32(0));
        assertEq(vault.lastSnapshotTs(), uint64(T0 + 1 days));
    }

    // ------------------------------------------------------------ final / finalization

    function test_Final_TooEarly() public {
        _bindAlice(0);
        vm.warp(_finalTime() - 1);
        vm.prank(receiver);
        assertEq(vault.applyFinal(_ids(VID), _vals(10), uint64(block.timestamp)), bytes32("FINAL_TOO_EARLY"));
        assertFalse(vault.finalized());
    }

    function test_Final_FinalizesAndRecordsViews() public {
        _bindAlice(0);
        vm.warp(_finalTime());
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.SnapshotApplied(uint64(block.timestamp), 1, true);
        vm.expectEmit(false, false, false, true, address(vault));
        emit CampaignVault.Finalized(uint64(block.timestamp), false);
        _final(VID, 10_000);
        assertTrue(vault.finalized());
        assertEq(vault.finalizedAt(), uint64(block.timestamp));
        assertEq(_credited(), 10_000);
    }

    function test_Final_BadObservationsDoNotFinalize() public {
        _bindAlice(0);
        vm.warp(_finalTime());
        vm.prank(receiver);
        assertEq(vault.applyFinal(_ids(VID), new uint64[](2), uint64(block.timestamp)), bytes32("LENGTH_MISMATCH"));
        assertFalse(vault.finalized());
    }

    function test_AfterFinalize_SnapshotsAndFinalRejected() public {
        _bindAlice(0);
        vm.warp(_finalTime());
        _final(VID, 10_000);
        vm.prank(receiver);
        assertEq(vault.applySnapshot(_ids(VID), _vals(99_999), uint64(block.timestamp)), bytes32("FINALIZED"));
        vm.prank(receiver);
        assertEq(vault.applyFinal(_ids(VID), _vals(99_999), uint64(block.timestamp)), bytes32("FINALIZED"));
        assertEq(_credited(), 10_000);
        // through the receiver: business rejection, not a revert
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 2, bytes32("FINALIZED"));
        _snap(VID, 99_999);
    }

    function test_FinalizeFromLastSnapshot_Deadman() public {
        _bindAlice(0);
        uint256 t = _finalTime() + vault.deadmanTimeout();
        vm.warp(t - 1);
        vm.expectRevert(CampaignVault.TooEarly.selector);
        vault.finalizeFromLastSnapshot();
        vm.warp(t);
        vm.expectEmit(false, false, false, true, address(vault));
        emit CampaignVault.Finalized(uint64(block.timestamp), true);
        vm.prank(stranger); // permissionless
        vault.finalizeFromLastSnapshot();
        assertTrue(vault.finalized());
        assertEq(vault.finalizedAt(), uint64(block.timestamp));
        vm.expectRevert(CampaignVault.CampaignFinalized.selector);
        vault.finalizeFromLastSnapshot();
    }

    function test_Deadman_FinalizedClaimIgnoresStalenessAndSchedule() public {
        _bindAlice(0);
        _day(8);
        _snap(VID, 50_000); // earned = 100e6
        vm.warp(_finalTime() + vault.deadmanTimeout()); // snapshot long stale
        assertEq(vault.claimable(alice), 0, "stale and unfinalized");
        vault.finalizeFromLastSnapshot();
        assertEq(vault.claimable(alice), 100e6, "finalized: full earned amount, no stale freeze");
        vault.claim(alice);
        assertEq(usdc.balanceOf(alice), 100e6);
    }
}
