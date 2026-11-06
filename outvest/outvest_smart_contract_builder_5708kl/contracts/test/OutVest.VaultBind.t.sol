// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";
import {ScheduleLib} from "../ScheduleLib.sol";

/// @dev Constructor, funding, requestBinding and submitForVerification.
contract VaultBindTest is OutVestBase {
    // ------------------------------------------------------------ constructor

    function _ctorBad(CampaignVault.Params memory p) internal {
        vm.expectRevert(CampaignVault.InvalidParams.selector);
        new CampaignVault(p, receiver, address(factory), bytes32(uint256(1)));
    }

    function test_Constructor_StoresConfig() public {
        CampaignVault.Params memory p = _params();
        p.bucketLen = 3600;
        CampaignVault v = new CampaignVault(p, receiver, address(factory), bytes32(uint256(7)));
        assertEq(v.brand(), brand);
        assertEq(address(v.usdc()), address(usdc));
        assertEq(v.receiver(), receiver);
        assertEq(v.factory(), address(factory));
        assertEq(v.rulesHash(), bytes32(uint256(7)));
        assertEq(v.ratePerThousand(), 2e6);
        assertEq(v.capPerCreator(), 300e6);
        assertEq(v.bucketLen(), 3600);
        assertEq(v.scheduleLength(), 90 days);
        assertEq(v.lastSnapshotTs(), uint64(block.timestamp));
        assertEq(v.schedule().length, 5);
        assertEq(vault.bucketLen(), 1 days);
        assertEq(v.MAX_BATCH(), 25);
        assertEq(v.MAX_ALLOWANCE_WINDOW(), 14 days);
        assertEq(v.VERIFY_COOLDOWN(), 10 minutes);
        assertFalse(v.finalized());
        assertEq(v.finalizedAt(), 0);
    }

    function test_Constructor_AcceptsBucketLenBounds() public {
        CampaignVault.Params memory p = _params();
        p.bucketLen = 1 hours;
        new CampaignVault(p, receiver, address(factory), bytes32(0));
        p.bucketLen = 7 days;
        new CampaignVault(p, receiver, address(factory), bytes32(0));
    }

    function test_Constructor_RejectsInvalidParams() public {
        CampaignVault.Params memory p = _params();
        p.brand = address(0);
        _ctorBad(p);
        p = _params();
        p.usdc = stranger; // no code
        _ctorBad(p);
        p = _params();
        p.bindDeadline = uint64(block.timestamp);
        _ctorBad(p);
        p = _params();
        p.ratePerThousand = 0;
        _ctorBad(p);
        p = _params();
        p.ratePerThousand = uint256(type(uint128).max) + 1;
        _ctorBad(p);
        p = _params();
        p.capPerCreator = 0;
        _ctorBad(p);
        p = _params();
        p.capPerCreator = uint256(type(uint128).max) + 1;
        _ctorBad(p);
        p = _params();
        p.maxCreators = 0;
        _ctorBad(p);
        p = _params();
        p.maxVideosPerCreator = 0;
        _ctorBad(p);
        p = _params();
        p.maxVideosPerCreator = 11;
        _ctorBad(p);
        p = _params();
        p.staleAfter = 1 days - 1;
        _ctorBad(p);
        p = _params();
        p.deadmanTimeout = 0;
        _ctorBad(p);
    }

    function test_Constructor_RejectsBucketLenOutOfRange() public {
        CampaignVault.Params memory p = _params();
        p.bucketLen = 0;
        _ctorBad(p);
        p.bucketLen = 3599;
        _ctorBad(p);
        p.bucketLen = uint32(7 days + 1);
        _ctorBad(p);
    }

    function test_Constructor_RejectsZeroReceiverFactoryAndBadSchedule() public {
        CampaignVault.Params memory p = _params();
        vm.expectRevert(CampaignVault.InvalidParams.selector);
        new CampaignVault(p, address(0), address(factory), bytes32(0));
        vm.expectRevert(CampaignVault.InvalidParams.selector);
        new CampaignVault(p, receiver, address(0), bytes32(0));
        p.schedule = new ScheduleLib.Segment[](0);
        vm.expectRevert(ScheduleLib.InvalidSchedule.selector);
        new CampaignVault(p, receiver, address(factory), bytes32(0));
    }

    // ------------------------------------------------------------ fund

    function test_Fund_AccumulatesAndEmits() public {
        usdc.mint(brand, 500e6);
        vm.startPrank(brand);
        usdc.approve(address(vault), 500e6);
        vm.expectEmit(true, false, false, true, address(vault));
        emit CampaignVault.Funded(brand, 200e6);
        vault.fund(200e6);
        vault.fund(300e6);
        vm.stopPrank();
        assertEq(vault.totalFunded(), 500e6);
        assertEq(usdc.balanceOf(address(vault)), 500e6);
    }

    function test_Fund_AnyoneCanFund() public {
        usdc.mint(stranger, 10e6);
        vm.startPrank(stranger);
        usdc.approve(address(vault), 10e6);
        vault.fund(10e6);
        vm.stopPrank();
        assertEq(vault.totalFunded(), 10e6);
    }

    function test_Fund_RevertsOnFeeOnTransferToken() public {
        usdc.setFeeBps(100);
        usdc.mint(brand, 100e6);
        vm.startPrank(brand);
        usdc.approve(address(vault), 100e6);
        vm.expectRevert(CampaignVault.UnsupportedToken.selector);
        vault.fund(100e6);
        vm.stopPrank();
    }

    function test_Fund_RevertsAfterFinalized() public {
        _finalizeByDeadman();
        usdc.mint(brand, 1e6);
        vm.startPrank(brand);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(CampaignVault.CampaignFinalized.selector);
        vault.fund(1e6);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ requestBinding

    function _pending(address w)
        internal
        view
        returns (bytes32 vid, bytes32 ch, uint64 requestedAt, uint32 nonce, uint64 lastSubmitTs)
    {
        return vault.pendingBinding(w);
    }

    function test_RequestBinding_StoresPendingAndEmits() public {
        bytes32 expected = keccak256(abi.encode(address(vault), alice, VID, uint256(0), block.chainid));
        vm.expectEmit(true, true, false, true, address(vault));
        emit CampaignVault.BindingRequested(alice, VID, expected);
        bytes32 ch = _request(alice, VID);
        assertEq(ch, expected);
        (bytes32 pv, bytes32 pc, uint64 at, uint32 nonce, uint64 ls) = _pending(alice);
        assertEq(pv, VID);
        assertEq(pc, expected);
        assertEq(at, uint64(block.timestamp));
        assertEq(nonce, 1);
        assertEq(ls, 0);
    }

    function test_RequestBinding_AcceptsAllValidCharsets() public {
        _request(alice, bytes32("a-b_C9zZ0yA"));
    }

    function test_RequestBinding_RejectsInvalidVideoIds() public {
        bytes4 sel = CampaignVault.InvalidVideoId.selector;
        bytes32[7] memory bad = [
            bytes32(0), // empty
            bytes32("abcdefghij"), // 10 chars
            bytes32("abcdefghijkl"), // 12 chars
            bytes32("abcde.ghijk"), // bad char
            bytes32("abcde ghijk"), // space
            bytes32(uint256(0x6162636465666768696a6b)), // right-aligned
            bytes32("abcdefghij\x00") // trailing NUL inside the 11 chars
        ];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(alice);
            vm.expectRevert(sel);
            vault.requestBinding(bad[i]);
        }
    }

    /// A new request overwrites the pending one (no PendingExists revert) and bumps the nonce.
    function test_RequestBinding_OverwritesPendingAndIncrementsNonce() public {
        bytes32 ch1 = _request(alice, VID);
        vm.warp(block.timestamp + 1 hours);
        bytes32 ch2 = _request(alice, VID2);
        bytes32 expected2 = keccak256(abi.encode(address(vault), alice, VID2, uint256(1), block.chainid));
        assertEq(ch2, expected2);
        assertNotEq(ch1, ch2);
        (bytes32 pv, bytes32 pc, uint64 at, uint32 nonce,) = _pending(alice);
        assertEq(pv, VID2);
        assertEq(pc, ch2);
        assertEq(at, uint64(block.timestamp));
        assertEq(nonce, 2);
        // same video again still yields a fresh challenge
        bytes32 ch3 = _request(alice, VID2);
        assertNotEq(ch3, ch2);
        (,,, nonce,) = _pending(alice);
        assertEq(nonce, 3);
    }

    function test_RequestBinding_OverwriteInvalidatesOldChallenge() public {
        _fund(300e6);
        bytes32 ch1 = _request(alice, VID);
        bytes32 ch2 = _request(alice, VID2);
        assertEq(_applyBind(alice, VID, ch1, 0), bytes32("NO_MATCH"));
        assertEq(_applyBind(alice, VID2, ch1, 0), bytes32("NO_MATCH"));
        assertEq(_applyBind(alice, VID2, ch2, 0), bytes32(0));
    }

    function test_RequestBinding_RevertsWhenVideoOwned() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        vm.prank(bob);
        vm.expectRevert(CampaignVault.VideoAlreadyOwned.selector);
        vault.requestBinding(VID);
    }

    function test_RequestBinding_VideoLimit() public {
        CampaignVault.Params memory p = _params();
        p.maxVideosPerCreator = 1;
        vault = _newVault(p);
        _fund(300e6);
        _bind(alice, VID, 0);
        vm.prank(alice);
        vm.expectRevert(CampaignVault.VideoLimit.selector);
        vault.requestBinding(VID2);
    }

    function test_RequestBinding_ClosedAtDeadline() public {
        vm.warp(vault.bindDeadline() - 1);
        _request(alice, VID);
        vm.warp(vault.bindDeadline());
        vm.prank(bob);
        vm.expectRevert(CampaignVault.BindingClosed.selector);
        vault.requestBinding(VID2);
    }

    function test_RequestBinding_ClosedWhenFinalized() public {
        _finalizeByDeadman();
        vm.prank(alice);
        vm.expectRevert(CampaignVault.BindingClosed.selector);
        vault.requestBinding(VID);
    }

    // ------------------------------------------------------------ submitForVerification

    function test_Submit_RevertsWithoutPending() public {
        vm.prank(alice);
        vm.expectRevert(CampaignVault.NoPendingBinding.selector);
        vault.submitForVerification();
    }

    function test_Submit_EmitsViaFactoryAndRecords() public {
        bytes32 ch = _request(alice, VID);
        vm.expectEmit(true, true, true, true, address(factory));
        emit CampaignFactory.VerifyRequested(address(vault), alice, VID, ch);
        vm.prank(alice);
        vault.submitForVerification();
        (,,,, uint64 ls) = _pending(alice);
        assertEq(ls, uint64(block.timestamp));
    }

    function test_Submit_CooldownTenMinutes() public {
        _request(alice, VID);
        vm.startPrank(alice);
        vault.submitForVerification();
        vm.expectRevert(CampaignVault.Cooldown.selector);
        vault.submitForVerification();
        skip(10 minutes - 1);
        vm.expectRevert(CampaignVault.Cooldown.selector);
        vault.submitForVerification();
        skip(1);
        vault.submitForVerification();
        vm.stopPrank();
    }

    /// Re-requesting must not reset the verify cooldown (lastSubmitTs survives the overwrite).
    function test_Submit_CooldownCannotBeBypassedByReRequesting() public {
        _request(alice, VID);
        vm.prank(alice);
        vault.submitForVerification();
        (,,,, uint64 ls) = _pending(alice);

        skip(1 minutes);
        bytes32 ch2 = _request(alice, VID2);
        (,,,, uint64 ls2) = _pending(alice);
        assertEq(ls2, ls, "lastSubmitTs preserved across overwrite");
        vm.prank(alice);
        vm.expectRevert(CampaignVault.Cooldown.selector);
        vault.submitForVerification();

        skip(10 minutes - 1 minutes - 1);
        vm.prank(alice);
        vm.expectRevert(CampaignVault.Cooldown.selector);
        vault.submitForVerification();

        skip(1);
        vm.expectEmit(true, true, true, true, address(factory));
        emit CampaignFactory.VerifyRequested(address(vault), alice, VID2, ch2);
        vm.prank(alice);
        vault.submitForVerification();
    }

    function test_Submit_ClosedAfterDeadline() public {
        _request(alice, VID);
        vm.warp(vault.bindDeadline());
        vm.prank(alice);
        vm.expectRevert(CampaignVault.BindingClosed.selector);
        vault.submitForVerification();
    }

    function test_Submit_ClosedWhenFinalized() public {
        _request(alice, VID);
        _finalizeByDeadman();
        vm.prank(alice);
        vm.expectRevert(CampaignVault.BindingClosed.selector);
        vault.submitForVerification();
    }
}
