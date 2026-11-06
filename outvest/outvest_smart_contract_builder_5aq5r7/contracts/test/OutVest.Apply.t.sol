// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";

/// @dev applyBind success + every soft-reject reason, onlyReceiver gating.
contract VaultApplyBindTest is OutVestBase {
    // ------------------------------------------------------------ success

    function test_ApplyBind_Success() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        vm.expectEmit(true, true, false, true, address(vault));
        emit CampaignVault.Bound(alice, VID, 1234, uint64(block.timestamp));
        assertEq(_applyBind(alice, VID, ch, 1234), bytes32(0));

        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertTrue(c.bound);
        assertFalse(c.settled);
        assertEq(c.boundAt, uint64(block.timestamp));
        assertEq(c.videoCount, 1);
        assertEq(c.videoIds[0], VID);
        assertEq(c.remaining, 300e6);
        assertEq(c.paid, 0);
        assertEq(c.creditedViews, 0);
        assertEq(vault.liability(), 300e6);
        assertEq(vault.creatorCount(), 1);
        assertEq(vault.videoOwner(VID), alice);
        assertEq(vault.videosOf(alice).length, 1);
        assertEq(vault.creators(0, 10)[0], alice);
    }

    function test_ApplyBind_StoresBaselineInBindEpochBucket() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        _applyBind(alice, VID, ch, 1234);
        CampaignVault.VideoState memory v = vault.videoInfo(VID);
        assertEq(v.creator, alice);
        assertEq(v.baseline, 1234);
        assertEq(v.credited, 0);
        assertEq(v.lastUpdateTs, uint64(block.timestamp));
        uint256 epoch = block.timestamp / 1 days;
        uint256 idx = epoch % 7;
        assertEq(v.bucketMin[idx], 1234);
        assertEq(v.bucketEpoch[idx], uint32(epoch));
        for (uint256 i; i < 7; ++i) {
            if (i == idx) continue;
            assertEq(v.bucketEpoch[i], 0, "other slots stay empty");
            assertEq(v.bucketMin[i], 0);
        }
    }

    function test_ApplyBind_DeletesPendingEntry() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        vm.prank(alice);
        vault.submitForVerification();
        assertEq(_applyBind(alice, VID, ch, 0), bytes32(0));
        (bytes32 pv, bytes32 pc, uint64 at, uint32 nonce, uint64 ls) = vault.pendingBinding(alice);
        assertEq(pv, bytes32(0));
        assertEq(pc, bytes32(0));
        assertEq(at, 0);
        assertEq(nonce, 1, "nonce preserved: equals number of requestBinding calls");
        assertEq(ls, 0);
        // the consumed challenge cannot be replayed
        assertEq(_applyBind(alice, VID, ch, 0), bytes32("NO_MATCH"));
        vm.prank(alice);
        vm.expectRevert(CampaignVault.NoPendingBinding.selector);
        vault.submitForVerification();
    }

    function test_ApplyBind_SecondVideoDoesNotAddLiabilityOrChangeBoundAt() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        uint64 boundAt = vault.creatorInfo(alice).boundAt;
        _day(2);
        _bind(alice, VID2, 5);
        assertEq(vault.liability(), 300e6);
        assertEq(vault.creatorCount(), 1);
        assertEq(vault.videosOf(alice).length, 2);
        CampaignVault.Creator memory c = vault.creatorInfo(alice);
        assertEq(c.boundAt, boundAt, "boundAt fixed by first bind");
        assertEq(c.boundAt, uint64(T0));
        assertEq(c.videoCount, 2);
        assertEq(c.videoIds[1], VID2);
        assertEq(c.remaining, 300e6);
        // second video baseline lives in its own bind epoch bucket
        CampaignVault.VideoState memory v2 = vault.videoInfo(VID2);
        assertEq(v2.baseline, 5);
        assertEq(v2.lastUpdateTs, uint64(T0 + 2 days));
        assertEq(v2.bucketEpoch[((T0 + 2 days) / 1 days) % 7], uint32((T0 + 2 days) / 1 days));
        assertEq(vault.creators(0, 10).length, 1);
    }

    // ------------------------------------------------------------ soft rejects

    function test_ApplyBind_NoMatch_WrongChallengeOrVideo() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        assertEq(_applyBind(alice, VID, bytes32(uint256(1)), 0), bytes32("NO_MATCH"));
        assertEq(_applyBind(alice, VID2, ch, 0), bytes32("NO_MATCH"), "wrong video");
        assertEq(_applyBind(alice, VID, bytes32(0), 0), bytes32("NO_MATCH"), "zero challenge");
        assertFalse(vault.creatorInfo(alice).bound);
        // pending survives rejected attempts; the right one still works
        assertEq(_applyBind(alice, VID, ch, 0), bytes32(0));
    }

    function test_ApplyBind_NoMatch_WrongWallet() public {
        _fund(600e6);
        bytes32 ch = _request(alice, VID);
        assertEq(_applyBind(bob, VID, ch, 0), bytes32("NO_MATCH"), "bob has no pending request");
        bytes32 chBob = _request(bob, VID2);
        assertEq(_applyBind(bob, VID2, ch, 0), bytes32("NO_MATCH"), "alice's challenge on bob's pending");
        assertEq(_applyBind(alice, VID, chBob, 0), bytes32("NO_MATCH"));
        assertFalse(vault.creatorInfo(bob).bound);
        assertEq(vault.creatorCount(), 0);
    }

    function test_ApplyBind_NoPendingAndZeroChallenge() public {
        _fund(300e6);
        assertEq(_applyBind(alice, VID, bytes32(0), 0), bytes32("NO_MATCH"));
    }

    function test_ApplyBind_VideoTaken_SecondRacerRejected() public {
        _fund(600e6);
        bytes32 chA = _request(alice, VID);
        bytes32 chB = _request(bob, VID); // both requested before either was bound
        assertEq(_applyBind(alice, VID, chA, 0), bytes32(0));
        assertEq(_applyBind(bob, VID, chB, 0), bytes32("VIDEO_TAKEN"));
        assertFalse(vault.creatorInfo(bob).bound);
        assertEq(vault.videoOwner(VID), alice);
        assertEq(vault.creatorCount(), 1);
        assertEq(vault.liability(), 300e6, "loser reserves nothing");
    }

    function test_ApplyBind_VideoTaken_ViaReports() public {
        _fund(600e6);
        bytes32 chA = _request(alice, VID);
        bytes32 chB = _request(bob, VID);
        _sendT(1, _bindPayload(alice, VID, chA, 0));
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 1, bytes32("VIDEO_TAKEN"));
        _sendT(1, _bindPayload(bob, VID, chB, 0));
        assertFalse(vault.creatorInfo(bob).bound);
    }

    function test_ApplyBind_Full() public {
        CampaignVault.Params memory p = _params();
        p.maxCreators = 1;
        vault = _newVault(p);
        _fund(600e6);
        bytes32 chA = _request(alice, VID);
        bytes32 chB = _request(bob, VID2);
        assertEq(_applyBind(alice, VID, chA, 0), bytes32(0));
        assertEq(_applyBind(bob, VID2, chB, 0), bytes32("FULL"));
        assertEq(vault.creatorCount(), 1);
        assertFalse(vault.creatorInfo(bob).bound);
    }

    function test_ApplyBind_Full_ExistingCreatorMayStillAddVideos() public {
        CampaignVault.Params memory p = _params();
        p.maxCreators = 1;
        vault = _newVault(p);
        _fund(300e6);
        _bind(alice, VID, 0);
        bytes32 ch = _request(alice, VID2);
        assertEq(_applyBind(alice, VID2, ch, 0), bytes32(0));
        assertEq(vault.creatorInfo(alice).videoCount, 2);
    }

    function test_ApplyBind_Budget() public {
        _fund(299e6);
        bytes32 ch = _request(alice, VID);
        assertEq(_applyBind(alice, VID, ch, 0), bytes32("BUDGET"));
        assertEq(vault.liability(), 0);
        assertFalse(vault.creatorInfo(alice).bound);
        _fund(1e6);
        assertEq(_applyBind(alice, VID, ch, 0), bytes32(0));
        // reserve covers exactly one creator; a second one is rejected
        bytes32 ch2 = _request(bob, VID2);
        assertEq(_applyBind(bob, VID2, ch2, 0), bytes32("BUDGET"));
        assertEq(vault.creatorCount(), 1);
    }

    function test_ApplyBind_Budget_SecondVideoNeedsNoExtraReserve() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        bytes32 ch = _request(alice, VID2);
        assertEq(_applyBind(alice, VID2, ch, 0), bytes32(0));
    }

    function test_ApplyBind_Deadline() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        vm.warp(vault.bindDeadline() - 1);
        // still open one second before the deadline
        bytes32 ch2 = _request(bob, VID2);
        vm.warp(vault.bindDeadline());
        assertEq(_applyBind(alice, VID, ch, 0), bytes32("DEADLINE"));
        assertEq(_applyBind(bob, VID2, ch2, 0), bytes32("DEADLINE"));
        assertFalse(vault.creatorInfo(alice).bound);
    }

    function test_ApplyBind_DeadlineReasonAlsoWhenFinalized() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        _finalizeByDeadman();
        assertEq(_applyBind(alice, VID, ch, 0), bytes32("DEADLINE"));
    }

    /// MAX_VIDEOS is defence-in-depth: requestBinding already reverts VideoLimit and a wallet has a single pending
    /// request, so the only way to reach it is to bump the stored videoCount between request and bind.
    /// Layout dependent: `_creator` mapping is slot 8, `videoCount` (uint16) sits at bit offset 80 of the first word.
    function test_ApplyBind_MaxVideos() public {
        CampaignVault.Params memory p = _params();
        p.maxVideosPerCreator = 2;
        vault = _newVault(p);
        _fund(300e6);
        _bind(alice, VID, 0);
        bytes32 ch = _request(alice, VID2);
        bytes32 slot = keccak256(abi.encode(alice, uint256(8)));
        uint256 w = uint256(vm.load(address(vault), slot));
        assertEq((w >> 80) & 0xffff, 1, "layout sanity: videoCount == 1");
        w = (w & ~(uint256(0xffff) << 80)) | (uint256(2) << 80);
        vm.store(address(vault), slot, bytes32(w));
        assertEq(vault.creatorInfo(alice).videoCount, 2);
        assertEq(_applyBind(alice, VID2, ch, 0), bytes32("MAX_VIDEOS"));
        assertEq(vault.videoOwner(VID2), address(0));
    }

    function test_ApplyBind_VideoLimitRevertsAtRequestTime() public {
        CampaignVault.Params memory p = _params();
        p.maxVideosPerCreator = 2;
        vault = _newVault(p);
        _fund(300e6);
        _bind(alice, VID, 0);
        _bind(alice, VID2, 0);
        vm.prank(alice);
        vm.expectRevert(CampaignVault.VideoLimit.selector);
        vault.requestBinding(_vid(9));
    }

    // ------------------------------------------------------------ nonce preservation

    function _expectedChallenge(address w, bytes32 vid, uint32 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(address(vault), w, vid, nonce, block.chainid));
    }

    function test_ApplyBind_PreservesNonceSoChallengesNeverRepeat() public {
        _fund(300e6);
        bytes32 vx = _vid(3);
        bytes32 vz = _vid(5);
        bytes32 chX = _request(alice, vx); // nonce 0
        bytes32 chY = _request(alice, VID); // nonce 1 (overwrites X)
        assertEq(chX, _expectedChallenge(alice, vx, 0));
        assertEq(chY, _expectedChallenge(alice, VID, 1));
        assertEq(_applyBind(alice, VID, chY, 0), bytes32(0));

        (bytes32 pv, bytes32 pc, uint64 at, uint32 nonce, uint64 ls) = vault.pendingBinding(alice);
        assertEq(pv, bytes32(0));
        assertEq(pc, bytes32(0));
        assertEq(at, 0);
        assertEq(ls, 0);
        assertEq(nonce, 2, "two requestBinding calls so far");

        bytes32 chZ = _request(alice, vz); // must use nonce 2
        assertEq(chZ, _expectedChallenge(alice, vz, 2));
        assertTrue(chZ != chX && chZ != chY);
        (,,, nonce,) = vault.pendingBinding(alice);
        assertEq(nonce, 3);

        // Re-requesting the already-requested (wallet, video) pair X after the bind yields a fresh challenge.
        bytes32 chX2 = _request(alice, vx); // nonce 3
        assertEq(chX2, _expectedChallenge(alice, vx, 3));
        assertTrue(chX2 != chX, "earlier challenge for the same pair is never reproduced");
        // The old X challenge no longer binds.
        assertEq(_applyBind(alice, vx, chX, 0), bytes32("NO_MATCH"));
        // A bound video can never be re-requested.
        vm.prank(alice);
        vm.expectRevert(CampaignVault.VideoAlreadyOwned.selector);
        vault.requestBinding(VID);
    }

    function testFuzz_ApplyBind_NonceEqualsRequestCount(uint8 before_, uint8 after_) public {
        uint256 b = bound(before_, 1, 20);
        uint256 a = bound(after_, 0, 20);
        _fund(300e6);
        bytes32 ch;
        for (uint256 i; i < b; ++i) {
            ch = _request(alice, _vid(100 + i));
        }
        bytes32 vid = _vid(100 + b - 1);
        assertEq(_applyBind(alice, vid, ch, 0), bytes32(0));
        (,,, uint32 nonce,) = vault.pendingBinding(alice);
        assertEq(nonce, b);
        for (uint256 i; i < a; ++i) {
            bytes32 v2 = _vid(500 + i);
            bytes32 c2 = _request(alice, v2);
            assertEq(c2, _expectedChallenge(alice, v2, uint32(b + i)));
        }
        (,,, nonce,) = vault.pendingBinding(alice);
        assertEq(nonce, b + a);
    }

    // ------------------------------------------------------------ onlyReceiver

    function test_ApplyFunctions_OnlyReceiver() public {
        address[] memory callers = new address[](4);
        callers[0] = stranger;
        callers[1] = brand;
        callers[2] = address(factory);
        callers[3] = address(fwd); // the forwarder must go through the receiver
        bytes32[] memory ids = _ids(VID);
        uint64[] memory vs = _vals(1);
        for (uint256 i; i < callers.length; ++i) {
            vm.startPrank(callers[i]);
            vm.expectRevert(CampaignVault.NotReceiver.selector);
            vault.applyBind(alice, VID, bytes32(uint256(1)), 0);
            vm.expectRevert(CampaignVault.NotReceiver.selector);
            vault.applySnapshot(ids, vs, 1);
            vm.expectRevert(CampaignVault.NotReceiver.selector);
            vault.applyFinal(ids, vs, 1);
            vm.expectRevert(CampaignVault.NotReceiver.selector);
            vault.applyPayout(_wallets(alice));
            vm.stopPrank();
        }
    }
}
