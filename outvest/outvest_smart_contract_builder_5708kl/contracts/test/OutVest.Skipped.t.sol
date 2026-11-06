// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";

/// @dev EntrySkipped(videoId, reason) emitted by applySnapshot/applyFinal for unknown videos and stale timestamps.
contract VaultEntrySkippedTest is OutVestBase {
    bytes32 internal constant UNKNOWN = bytes32("zzzzzzzzzzz");

    function _countSkipped(Vm.Log[] memory logs) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == CampaignVault.EntrySkipped.selector) ++n;
        }
    }

    function _bindBoth() internal {
        _fund(600e6);
        _bind(alice, VID, 0);
        _bind(bob, VID2, 0);
    }

    // ------------------------------------------------------------ snapshot

    function test_Snapshot_UnknownVideoEmitsEntrySkipped() public {
        _bindBoth();
        _day(8);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(UNKNOWN, bytes32("UNKNOWN_VIDEO"));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.SnapshotApplied(uint64(block.timestamp), 1, false);
        _snap(UNKNOWN, 123);
    }

    function test_Snapshot_StaleTsEmitsEntrySkipped() public {
        _bindBoth();
        _day(9);
        _snap(VID, 500); // lastUpdateTs(VID) = day 9
        uint64 staleTs = uint64(T0 + 8 days);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(VID, bytes32("STALE_TS"));
        assertEq(_direct(VID, 900, staleTs), bytes32(0));
    }

    function test_Snapshot_StaleTsViaReceiverReportEmitsEntrySkipped() public {
        _bindBoth();
        _fund(300e6); // budget for a third creator
        _day(5);
        _bind(carol, _vid(7), 0); // lastUpdateTs(_vid(7)) = day 5
        // an older-but-fresh-enough report timestamp (age 2 days) is accepted by the receiver
        bytes memory rep = _envelope(2, address(vault), _nextSeq(address(vault), 2), uint64(T0 + 3 days), _snapPayload(_vid(7), 99));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(_vid(7), bytes32("STALE_TS"));
        _send(rep);
        assertEq(vault.creatorInfo(carol).creditedViews, 0);
        assertEq(vault.videoInfo(_vid(7)).lastUpdateTs, uint64(T0 + 5 days));
    }

    function test_Snapshot_NormalEntryEmitsNoEntrySkipped() public {
        _bindBoth();
        _day(8);
        vm.recordLogs();
        _snap(VID, 400);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countSkipped(logs), 0);
        assertEq(vault.creatorInfo(alice).creditedViews, 400);
    }

    function test_Snapshot_EqualTsToLastUpdateIsNotStale() public {
        _bindBoth();
        _day(8);
        _snap(VID, 400); // lastUpdateTs = day 8
        vm.recordLogs();
        assertEq(_direct(VID, 300, uint64(block.timestamp)), bytes32(0));
        assertEq(_countSkipped(vm.getRecordedLogs()), 0, "ts == lastUpdateTs is processed");
        assertEq(vault.creatorInfo(alice).creditedViews, 300);
    }

    function test_Snapshot_SkippedEntriesDoNotChangeCreditedOrOtherVideos() public {
        _bindBoth();
        _day(9);
        _snap(VID, 1000); // VID lastUpdateTs = day 9, alice credited 1000

        CampaignVault.VideoState memory before_ = vault.videoInfo(VID);
        uint256 aliceBefore = vault.creatorInfo(alice).creditedViews;
        uint256 lastSnap = vault.lastSnapshotTs();
        assertEq(aliceBefore, 1000);

        bytes32[] memory ids = new bytes32[](3);
        uint64[] memory vs = new uint64[](3);
        ids[0] = UNKNOWN;
        vs[0] = 5;
        ids[1] = VID; // stale: ts below its lastUpdateTs
        vs[1] = 1; // would lower credited if processed
        ids[2] = VID2; // valid
        vs[2] = 700;
        uint64 ts = uint64(T0 + 8 days + 12 hours);

        vm.recordLogs();
        _asReceiver();
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(UNKNOWN, bytes32("UNKNOWN_VIDEO"));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(VID, bytes32("STALE_TS"));
        assertEq(vault.applySnapshot(ids, vs, ts), bytes32(0));
        assertEq(_countSkipped(vm.getRecordedLogs()), 2);

        CampaignVault.VideoState memory after_ = vault.videoInfo(VID);
        assertEq(after_.credited, before_.credited);
        assertEq(after_.lastUpdateTs, before_.lastUpdateTs);
        for (uint256 i; i < 7; ++i) {
            assertEq(after_.bucketMin[i], before_.bucketMin[i]);
            assertEq(after_.bucketEpoch[i], before_.bucketEpoch[i]);
        }
        assertEq(vault.creatorInfo(alice).creditedViews, aliceBefore);
        assertEq(vault.videoInfo(UNKNOWN).creator, address(0));
        assertEq(vault.videoInfo(UNKNOWN).lastUpdateTs, 0);
        // the valid entry in the same batch is still applied
        assertEq(vault.creatorInfo(bob).creditedViews, 700);
        assertEq(vault.videoInfo(VID2).lastUpdateTs, ts);
        assertEq(vault.lastSnapshotTs(), lastSnap, "ts below lastSnapshotTs does not move it");
    }

    // ------------------------------------------------------------ final

    function test_Final_UnknownVideoEmitsEntrySkipped() public {
        _bindBoth();
        vm.warp(_finalTime());
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(UNKNOWN, bytes32("UNKNOWN_VIDEO"));
        _final(UNKNOWN, 77);
        assertTrue(vault.finalized(), "skip does not block finalization");
        assertEq(vault.creatorInfo(alice).creditedViews, 0);
        assertEq(vault.creatorInfo(bob).creditedViews, 0);
    }

    function test_Final_StaleTsEmitsEntrySkipped() public {
        _bindBoth();
        vm.warp(_finalTime() - 1 hours);
        _snap(VID, 1000); // lastUpdateTs(VID) = finalTime - 1h
        assertEq(vault.creatorInfo(alice).creditedViews, 1000);
        vm.warp(_finalTime());
        bytes32[] memory ids = _ids(VID);
        uint64[] memory vs = _vals(10);
        uint64 staleTs = uint64(_finalTime() - 2 hours);
        _asReceiver();
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(VID, bytes32("STALE_TS"));
        assertEq(vault.applyFinal(ids, vs, staleTs), bytes32(0));
        assertTrue(vault.finalized());
        assertEq(vault.creatorInfo(alice).creditedViews, 1000, "stale final entry did not change credit");
    }

    function test_Final_NormalEntryEmitsNoEntrySkipped() public {
        _bindBoth();
        vm.warp(_finalTime());
        vm.recordLogs();
        _final(VID, 250);
        assertEq(_countSkipped(vm.getRecordedLogs()), 0);
        assertTrue(vault.finalized());
        assertEq(vault.creatorInfo(alice).creditedViews, 250);
    }

    function testFuzz_Snapshot_UnknownIdsNeverTouchState(bytes32 id, uint64 views_) public {
        _bindBoth();
        vm.assume(id != VID && id != VID2);
        _day(8);
        uint256 a = vault.creatorInfo(alice).creditedViews;
        uint256 b = vault.creatorInfo(bob).creditedViews;
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.EntrySkipped(id, bytes32("UNKNOWN_VIDEO"));
        _snap(id, views_);
        assertEq(vault.creatorInfo(alice).creditedViews, a);
        assertEq(vault.creatorInfo(bob).creditedViews, b);
        assertEq(vault.videoOwner(id), address(0));
    }
}
