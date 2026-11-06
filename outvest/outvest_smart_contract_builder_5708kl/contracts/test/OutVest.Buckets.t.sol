// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";

/// @dev Rolling-minimum bucket filter + growth clamp behaviour of applySnapshot.
///      bucketLen is one day in the default params, so a bucket "epoch" is `timestamp / 1 days` and a bucket is
///      inside the window while `epoch(bucket) + 7 > epoch(now)`, i.e. for the current epoch and the 6 before it.
contract VaultBucketsTest is OutVestBase {
    function _credited() internal view returns (uint256) {
        return vault.creatorInfo(alice).creditedViews;
    }

    function _videoCredited(bytes32 vid) internal view returns (uint256) {
        return vault.videoInfo(vid).credited;
    }

    function _growthVault(uint64 growth, uint32 bucketLen_) internal {
        CampaignVault.Params memory p = _params();
        p.maxGrowthPerDay = growth;
        p.bucketLen = bucketLen_;
        vault = _newVault(p);
        _fund(900e6);
    }

    // ------------------------------------------------------------ dips

    function test_Dip_LowersCreditedImmediatelyWithoutThrottle() public {
        _growthVault(1000, 1 days);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 8000, "rise throttled by 8 days * 1000");
        _day(9);
        _snap(VID, 2000); // genuine drop
        assertEq(_credited(), 2000, "dip applied at once, not rate limited");
        assertEq(_videoCredited(VID), 2000);
        assertEq(vault.videoInfo(VID).lastUpdateTs, uint64(block.timestamp));
        // views bounce back: new bucket is high but the window still holds the 2000 low
        _day(10);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 2000, "window min (2000) still governs");
    }

    function test_Dip_BelowBaselineClampsNetAtZero() public {
        _bindOne(1000);
        _day(8);
        _snap(VID, 4000);
        assertEq(_credited(), 3000);
        _day(9);
        _snap(VID, 500); // below baseline: net = 0
        assertEq(_credited(), 0);
    }

    function _bindOne(uint64 baseline) internal {
        _fund(300e6);
        _bind(alice, VID, baseline);
    }

    function test_Dip_AggregatesAcrossVideos() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        _bind(alice, VID2, 0);
        _day(8);
        bytes32[] memory ids = new bytes32[](2);
        uint64[] memory vs = new uint64[](2);
        ids[0] = VID;
        ids[1] = VID2;
        vs[0] = 1000;
        vs[1] = 3000;
        _sendT(2, abi.encode(ids, vs));
        assertEq(_credited(), 4000);
        _day(9);
        vs[0] = 500;
        vs[1] = 3000;
        _sendT(2, abi.encode(ids, vs));
        assertEq(_videoCredited(VID), 500);
        assertEq(_videoCredited(VID2), 3000);
        assertEq(_credited(), 3500);
    }

    // ------------------------------------------------------------ rising / growth clamp

    function test_Rising_ThrottledByGrowthClamp() public {
        _growthVault(1000, 1 days);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 8000);
        vm.warp(block.timestamp + 12 hours);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 8500, "half a day => +500");
        vm.warp(block.timestamp + 12 hours);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 9000, "another half day");
    }

    function test_Rising_BelowAllowanceIsCreditedInFull() public {
        _growthVault(1e6, 1 days);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 5000);
        assertEq(_credited(), 5000);
    }

    function test_GrowthClamp_AllowanceWindowCappedAt14Days() public {
        _growthVault(1000, 1 days);
        _bind(alice, VID, 0);
        _day(20);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 14_000, "20 days since bind, only 14 count");
        _day(60); // 40 day gap
        _snap(VID, 1_000_000);
        assertEq(_credited(), 28_000, "another capped 14 day allowance, not 40");
    }

    function test_GrowthClamp_ZeroGrowthFreezesRises() public {
        _growthVault(0, 1 days);
        _bind(alice, VID, 0);
        _day(8);
        _snap(VID, 1_000_000);
        assertEq(_credited(), 0);
    }

    // ------------------------------------------------------------ expiry / gaps

    function test_Gap_MoreThanSevenEpochsExpiresOldBuckets() public {
        _bindOne(0);
        _day(8);
        _snap(VID, 1000);
        assertEq(_credited(), 1000);
        _day(20); // 12 epochs later: the 1000 low is outside the window
        _snap(VID, 7000);
        assertEq(_credited(), 7000, "old low no longer clamps the minimum");
    }

    function test_Window_BoundaryEpochSix_Valid_EpochSeven_Expired() public {
        _bindOne(0); // bind bucket: baseline 0 in epoch E
        _day(6);
        _snap(VID, 5000);
        assertEq(_credited(), 0, "epoch E+6: bind bucket (min 0) is still in the window");
        _day(7);
        _snap(VID, 5000);
        assertEq(_credited(), 5000, "epoch E+7: bind bucket has expired");
    }

    function test_Window_SlotReusedByLaterEpoch() public {
        _bindOne(0);
        _day(8);
        _snap(VID, 1000);
        uint32 e8 = uint32((T0 + 8 days) / 1 days);
        assertEq(vault.videoInfo(VID).bucketEpoch[e8 % 7], e8);
        _day(15); // same slot index (15 % 7 == 8 % 7); previous occupant is stale
        _snap(VID, 9000);
        uint32 e15 = uint32((T0 + 15 days) / 1 days);
        CampaignVault.VideoState memory v = vault.videoInfo(VID);
        assertEq(v.bucketEpoch[e15 % 7], e15);
        assertEq(v.bucketMin[e15 % 7], 9000);
        assertEq(_credited(), 9000);
    }

    function test_EmptySlotsAreNotTreatedAsZeroMinimum() public {
        _bindOne(100);
        CampaignVault.VideoState memory v0 = vault.videoInfo(VID);
        uint256 used;
        for (uint256 i; i < 7; ++i) {
            if (v0.bucketEpoch[i] != 0) ++used;
            else assertEq(v0.bucketMin[i], 0);
        }
        assertEq(used, 1);
        _day(8);
        _snap(VID, 5000);
        // if empty (epoch 0, min 0) slots counted, the candidate would be 0
        assertEq(_credited(), 4900);
    }

    // ------------------------------------------------------------ epoch 0 => no valid bucket

    /// Timestamps inside the very first bucket have epoch 0, which marks an empty slot. A snapshot that finds no
    /// valid bucket is skipped: nothing credited and the video's lastUpdateTs is not advanced.
    function test_NoValidBucket_SnapshotSkippedInEpochZero() public {
        vm.warp(1000);
        vault = _newVault(_params());
        _fund(300e6);
        _bind(alice, VID, 0);
        assertEq(vault.videoInfo(VID).lastUpdateTs, 1000);

        vm.warp(5000);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.SnapshotApplied(5000, 1, false);
        _snap(VID, 777);
        assertEq(_credited(), 0, "skipped: no valid bucket");
        assertEq(_videoCredited(VID), 0);
        assertEq(vault.videoInfo(VID).lastUpdateTs, 1000, "not advanced");
        assertEq(vault.lastSnapshotTs(), 5000, "snapshot clock still advances");

        // once timestamps reach epoch >= 1 the video is credited normally
        vm.warp(1 days + 10);
        _snap(VID, 777);
        assertEq(_credited(), 777);
        assertEq(vault.videoInfo(VID).lastUpdateTs, uint64(block.timestamp));
    }

    // ------------------------------------------------------------ other bucket lengths

    function test_HourlyBuckets_WindowIsSevenHours() public {
        _growthVault(1e12, 1 hours);
        _bind(alice, VID, 100);
        vm.warp(T0 + 6 hours);
        _snap(VID, 5000);
        assertEq(_credited(), 0, "bind bucket still valid 6 buckets later");
        vm.warp(T0 + 7 hours);
        _snap(VID, 5000);
        assertEq(_credited(), 4900);
    }

    function test_WeeklyBuckets_Valid() public {
        _growthVault(1e12, 7 days);
        _bind(alice, VID, 100);
        _day(8);
        _snap(VID, 5000);
        // window is 7 weeks: the bind bucket (baseline 100) is still valid
        assertEq(_credited(), 0);
        vm.warp(T0 + 8 weeks);
        _snap(VID, 5000);
        assertEq(_credited(), 4900);
    }
}
