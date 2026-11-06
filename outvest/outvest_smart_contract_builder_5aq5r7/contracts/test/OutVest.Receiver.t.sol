// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";
import {IReceiver} from "../interfaces/IReceiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev Production ReportReceiver (no etch) with real packed metadata.
contract ReceiverProdTest is OutVestBase {
    function _useTestReceiver() internal pure override returns (bool) {
        return false;
    }

    function _pin(uint8 t) internal pure returns (bytes32) {
        return t == 1 ? WF_BIND : t == 2 ? WF_SNAP : t == 3 ? WF_FINAL : WF_PAY;
    }

    function _payloadFor(uint8 t) internal view returns (bytes memory) {
        if (t == 1) return _bindPayload(alice, VID, bytes32(uint256(1)), 0);
        if (t == 4) return abi.encode(_wallets(alice));
        return _snapPayload(VID, 10);
    }

    function _rep(uint8 t, uint64 seq) internal view returns (bytes memory) {
        return _envelope(t, address(vault), seq, uint64(block.timestamp), _payloadFor(t));
    }

    function test_Constructor_RejectsZeroAddresses() public {
        vm.expectRevert(ReportReceiver.InvalidAddress.selector);
        new ReportReceiver(address(0), address(factory));
        vm.expectRevert(ReportReceiver.InvalidAddress.selector);
        new ReportReceiver(address(fwd), address(0));
    }

    function test_OnlyForwarderMayCall() public {
        bytes memory report = _rep(2, 1);
        vm.prank(stranger);
        vm.expectRevert(ReportReceiver.NotForwarder.selector);
        IReceiver(receiver).onReport(abi.encodePacked(WF_SNAP, WF_NAME, wfOwner), report);
        vm.prank(wfOwner); // even the pinned workflow owner cannot call directly
        vm.expectRevert(ReportReceiver.NotForwarder.selector);
        IReceiver(receiver).onReport(abi.encodePacked(WF_SNAP, WF_NAME, wfOwner), report);
    }

    function test_UnknownReportTypeReverts() public {
        bytes memory meta = abi.encodePacked(WF_SNAP, WF_NAME, wfOwner);
        vm.expectRevert(ReportReceiver.UnknownReportType.selector);
        fwd.forward(receiver, meta, _envelope(0, address(vault), 1, uint64(block.timestamp), ""));
        vm.expectRevert(ReportReceiver.UnknownReportType.selector);
        fwd.forward(receiver, meta, _envelope(5, address(vault), 1, uint64(block.timestamp), ""));
    }

    function test_MetadataWrongLengthReverts() public {
        bytes memory report = _rep(2, 1);
        vm.expectRevert(ReportReceiver.InvalidMetadata.selector);
        fwd.forward(receiver, "", report);
        vm.expectRevert(ReportReceiver.InvalidMetadata.selector);
        fwd.forward(receiver, abi.encodePacked(WF_SNAP, WF_NAME, bytes19(0)), report);
    }

    /// Real forwarders append a 2-byte reportId; trailing bytes must be accepted.
    function test_MetadataWithTrailingReportIdAccepted() public {
        bytes memory report = _rep(2, 1);
        fwd.forward(receiver, abi.encodePacked(WF_SNAP, WF_NAME, wfOwner, bytes2(0x0001)), report);
        assertEq(ReportReceiver(receiver).lastSeq(address(vault), 2), 1);
    }

    function test_WorkflowIdPinnedPerReportType() public {
        for (uint8 t = 1; t <= 4; ++t) {
            bytes memory report = _rep(t, 1);
            for (uint8 other = 1; other <= 4; ++other) {
                if (other == t) continue;
                vm.expectRevert(ReportReceiver.WrongWorkflow.selector);
                fwd.forwardPacked(receiver, _pin(other), WF_NAME, wfOwner, report);
            }
            vm.expectRevert(ReportReceiver.WrongWorkflow.selector);
            fwd.forwardPacked(receiver, keccak256("random"), WF_NAME, wfOwner, report);
            vm.expectRevert(ReportReceiver.WrongWorkflow.selector);
            fwd.forwardPacked(receiver, bytes32(0), WF_NAME, wfOwner, report);
        }
    }

    function test_ClaimReportFromSnapshotWorkflowRejected() public {
        // payout (claim) report signed by the snapshot workflow must be rejected and must not be consumed
        bytes memory pay = _rep(4, 1);
        vm.expectRevert(ReportReceiver.WrongWorkflow.selector);
        fwd.forwardPacked(receiver, WF_SNAP, WF_NAME, wfOwner, pay);
        assertFalse(ReportReceiver(receiver).seenReport(keccak256(pay)));
        assertEq(ReportReceiver(receiver).lastSeq(address(vault), 4), 0);
        // and the reverse: a snapshot report from the payout workflow
        vm.expectRevert(ReportReceiver.WrongWorkflow.selector);
        fwd.forwardPacked(receiver, WF_PAY, WF_NAME, wfOwner, _rep(2, 1));
    }

    function test_WorkflowOwnerPinned() public {
        bytes memory report = _rep(2, 1);
        vm.expectRevert(ReportReceiver.WrongOwner.selector);
        fwd.forwardPacked(receiver, WF_SNAP, WF_NAME, stranger, report);
        vm.expectRevert(ReportReceiver.WrongOwner.selector);
        fwd.forwardPacked(receiver, WF_SNAP, WF_NAME, address(0), report);
    }

    function test_WrongOwnerCheckedBeforeEnvelopeDecoding() public {
        // an undecodable report with the wrong owner still reports WrongOwner (owner authenticated first)
        vm.expectRevert(ReportReceiver.WrongOwner.selector);
        fwd.forwardPacked(receiver, WF_SNAP, WF_NAME, stranger, hex"deadbeef");
    }

    function test_WorkflowNameIsNotPinned() public {
        fwd.forwardPacked(receiver, WF_SNAP, bytes10("anything"), wfOwner, _rep(2, 1));
        assertEq(ReportReceiver(receiver).lastSeq(address(vault), 2), 1);
    }

    function test_UnknownVaultReverts() public {
        vm.expectRevert(ReportReceiver.UnknownVault.selector);
        fwd.forwardPacked(
            receiver, WF_SNAP, WF_NAME, wfOwner, _envelope(2, stranger, 1, uint64(block.timestamp), _snapPayload(VID, 1))
        );
    }

    function test_CorrectMetadataAcceptedForEachType() public {
        // type 1: full bind flow
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        bytes memory bindReport =
            _envelope(1, address(vault), 1, uint64(block.timestamp), _bindPayload(alice, VID, ch, 7));
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportAccepted(address(vault), 1, 1);
        fwd.forwardPacked(receiver, WF_BIND, WF_NAME, wfOwner, bindReport);
        assertTrue(vault.creatorInfo(alice).bound);
        assertEq(vault.videoOwner(VID), alice);

        // type 2
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportAccepted(address(vault), 2, 1);
        fwd.forwardPacked(receiver, WF_SNAP, WF_NAME, wfOwner, _rep(2, 1));

        // type 3 passes auth; business layer rejects because it's too early
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), 3, bytes32("FINAL_TOO_EARLY"));
        fwd.forwardPacked(receiver, WF_FINAL, WF_NAME, wfOwner, _rep(3, 1));

        // type 4
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportAccepted(address(vault), 4, 1);
        fwd.forwardPacked(receiver, WF_PAY, WF_NAME, wfOwner, _rep(4, 1));
    }

    function test_MalformedReportBytesRevert() public {
        bytes memory meta = abi.encodePacked(WF_SNAP, WF_NAME, wfOwner);
        vm.expectRevert();
        fwd.forward(receiver, meta, hex"deadbeef");
        vm.expectRevert();
        fwd.forward(receiver, meta, "");
        // report type word wider than uint8 does not decode
        vm.expectRevert();
        fwd.forward(receiver, meta, abi.encode(uint256(258), address(vault), uint64(1), uint64(1), bytes("")));
    }

    function test_SupportsInterface() public view {
        ReportReceiver r = ReportReceiver(receiver);
        assertTrue(r.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(r.supportsInterface(type(IERC165).interfaceId));
        assertFalse(r.supportsInterface(0xdeadbeef));
        assertFalse(r.supportsInterface(0xffffffff));
    }
}

/// @dev Receiver business logic with the TestReportReceiver (metadata check skipped, everything else live).
contract ReceiverFlowTest is OutVestBase {
    ReportReceiver internal r;

    function setUp() public override {
        super.setUp();
        r = ReportReceiver(receiver);
    }

    function _snapReport(uint64 seq, uint64 ts, uint64 views_) internal view returns (bytes memory) {
        return _envelope(2, address(vault), seq, ts, _snapPayload(VID, views_));
    }

    function _expectRejectedEv(uint8 t, bytes32 reason) internal {
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportRejected(address(vault), t, reason);
    }

    function test_TestReceiverStillEnforcesForwarder() public {
        vm.prank(stranger);
        vm.expectRevert(ReportReceiver.NotForwarder.selector);
        r.onReport("", _snapReport(1, uint64(block.timestamp), 1));
    }

    function test_DuplicateReportReverts() public {
        bytes memory rep = _snapReport(1, uint64(block.timestamp), 5);
        _send(rep);
        assertTrue(r.seenReport(keccak256(rep)));
        vm.expectRevert(ReportReceiver.Replay.selector);
        _send(rep);
    }

    function test_UnknownVaultReverts() public {
        vm.expectRevert(ReportReceiver.UnknownVault.selector);
        _send(_envelope(2, stranger, 1, uint64(block.timestamp), _snapPayload(VID, 1)));
        vm.expectRevert(ReportReceiver.UnknownVault.selector);
        _send(_envelope(2, address(usdc), 1, uint64(block.timestamp), _snapPayload(VID, 1)));
    }

    function test_MalformedReportBytesRevert() public {
        vm.expectRevert();
        _send(hex"deadbeef");
    }

    // ------------------------------------------------------------ sequence (soft)

    function test_StaleSeq_SoftRejectedAndLastSeqUntouched() public {
        _send(_snapReport(5, uint64(block.timestamp), 1));
        assertEq(r.lastSeq(address(vault), 2), 5);
        uint64 ts5 = r.lastTs(address(vault), 2);

        bytes memory same = _snapReport(5, uint64(block.timestamp), 2); // same seq, different content
        _expectRejectedEv(2, bytes32("STALE_SEQ"));
        _send(same); // does not revert
        bytes memory lower = _snapReport(4, uint64(block.timestamp), 3);
        _expectRejectedEv(2, bytes32("STALE_SEQ"));
        _send(lower);
        assertEq(r.lastSeq(address(vault), 2), 5, "lastSeq untouched");
        assertEq(r.lastTs(address(vault), 2), ts5, "lastTs untouched");
        assertTrue(r.seenReport(keccak256(same)), "rejected report hash consumed");
        assertTrue(r.seenReport(keccak256(lower)));
        vm.expectRevert(ReportReceiver.Replay.selector);
        _send(same);
    }

    function test_StaleSeq_NoStateAppliedToVault() public {
        _fund(300e6);
        _bind(alice, VID, 0);
        _day(8);
        _send(_snapReport(5, uint64(block.timestamp), 1000));
        assertEq(vault.creatorInfo(alice).creditedViews, 1000);
        _day(9);
        _send(_snapReport(5, uint64(block.timestamp), 900)); // soft-rejected: must not touch the vault
        assertEq(vault.creatorInfo(alice).creditedViews, 1000);
        assertEq(vault.lastSnapshotTs(), uint64(T0 + 8 days));
    }

    function test_SeqGapsAllowed() public {
        _send(_snapReport(1, uint64(block.timestamp), 1));
        _send(_snapReport(9, uint64(block.timestamp), 2));
        assertEq(r.lastSeq(address(vault), 2), 9);
        _send(_snapReport(1000, uint64(block.timestamp), 3));
        assertEq(r.lastSeq(address(vault), 2), 1000);
    }

    function test_SeqZeroIsStale() public {
        _expectRejectedEv(2, bytes32("STALE_SEQ"));
        _send(_snapReport(0, uint64(block.timestamp), 1));
        assertEq(r.lastSeq(address(vault), 2), 0);
    }

    function test_SeqIsPerVaultAndPerType() public {
        _send(_snapReport(3, uint64(block.timestamp), 1));
        // other type, same seq: ok
        _send(_envelope(3, address(vault), 1, uint64(block.timestamp), _snapPayload(VID, 1)));
        assertEq(r.lastSeq(address(vault), 3), 1);
        // other vault, same type, seq 1: ok
        CampaignVault v2 = _newVault(_params());
        _send(_envelope(2, address(v2), 1, uint64(block.timestamp), _snapPayload(VID, 1)));
        assertEq(r.lastSeq(address(v2), 2), 1);
    }

    // ------------------------------------------------------------ timestamps (soft)

    function test_FutureTs_SoftRejected() public {
        _expectRejectedEv(2, bytes32("FUTURE_TS"));
        _send(_snapReport(1, uint64(block.timestamp + 15 minutes + 1), 1));
        assertEq(r.lastSeq(address(vault), 2), 0, "seq not consumed");
        assertEq(r.lastTs(address(vault), 2), 0);
        // boundary is accepted; the same seq may be reused because the rejected report did not advance it
        _send(_snapReport(1, uint64(block.timestamp + 15 minutes), 1));
        assertEq(r.lastSeq(address(vault), 2), 1);
        assertEq(r.lastTs(address(vault), 2), uint64(block.timestamp + 15 minutes));
    }

    function test_TooOldTs_SoftRejected() public {
        vm.warp(T0 + 10 days);
        _expectRejectedEv(2, bytes32("STALE_TS"));
        _send(_snapReport(1, uint64(block.timestamp - 3 days - 1), 1));
        assertEq(r.lastSeq(address(vault), 2), 0);
        _send(_snapReport(1, uint64(block.timestamp - 3 days), 1)); // boundary ok
        assertEq(r.lastSeq(address(vault), 2), 1);
    }

    function test_TsOlderThanLastTs_SoftRejected() public {
        vm.warp(T0 + 1 days);
        _send(_snapReport(1, uint64(block.timestamp), 1));
        _expectRejectedEv(2, bytes32("STALE_TS"));
        _send(_snapReport(2, uint64(block.timestamp - 1), 1));
        assertEq(r.lastSeq(address(vault), 2), 1, "rejected seq not consumed");
        assertEq(r.lastTs(address(vault), 2), uint64(block.timestamp));
        _send(_snapReport(2, uint64(block.timestamp), 2)); // equal ts allowed
        assertEq(r.lastSeq(address(vault), 2), 2);
    }

    function test_SeqCheckedBeforeTimestamps() public {
        _send(_snapReport(5, uint64(block.timestamp), 1));
        _expectRejectedEv(2, bytes32("STALE_SEQ"));
        _send(_snapReport(5, uint64(block.timestamp + 1 days), 1)); // would also be a future ts
    }

    // ------------------------------------------------------------ business layer

    function test_BusinessFailureEmitsRejectedAndConsumesReport() public {
        _request(alice, VID);
        bytes memory rep = _envelope(
            1, address(vault), 1, uint64(block.timestamp), _bindPayload(alice, VID, bytes32(uint256(0xbad)), 0)
        );
        _expectRejectedEv(1, bytes32("NO_MATCH"));
        _send(rep); // does not revert
        assertFalse(vault.creatorInfo(alice).bound);
        assertEq(r.lastSeq(address(vault), 1), 1);
        assertTrue(r.seenReport(keccak256(rep)));
        vm.expectRevert(ReportReceiver.Replay.selector);
        _send(rep);
    }

    function test_AcceptedEmitsReportAccepted() public {
        _fund(300e6);
        bytes32 ch = _request(alice, VID);
        bytes memory rep = _envelope(1, address(vault), 1, uint64(block.timestamp), _bindPayload(alice, VID, ch, 0));
        vm.expectEmit(true, true, false, true, receiver);
        emit ReportReceiver.ReportAccepted(address(vault), 1, 1);
        _send(rep);
        assertTrue(vault.creatorInfo(alice).bound);
    }

    function _expectRejected(uint8 t, bytes memory payload, bytes32 reason) internal {
        _expectRejectedEv(t, reason);
        _sendT(t, payload);
    }

    function test_MalformedPayloadsRejectedNotReverted() public {
        _expectRejected(1, new bytes(96), "MALFORMED_PAYLOAD");
        _expectRejected(1, abi.encode(uint256(1) << 160, VID, bytes32(uint256(1)), uint64(0)), "MALFORMED_PAYLOAD");
        _expectRejected(1, abi.encode(alice, VID, bytes32(uint256(1)), uint256(1) << 64), "MALFORMED_PAYLOAD");
        _expectRejected(2, hex"00", "MALFORMED_PAYLOAD");
        _expectRejected(4, hex"00", "MALFORMED_PAYLOAD");
        _expectRejected(4, abi.encode(uint256(32), uint256(1), uint256(1) << 160), "MALFORMED_PAYLOAD");
    }

    function test_BatchLimitsRejected() public {
        address[] memory w = new address[](26);
        _expectRejected(4, abi.encode(w), "BATCH_TOO_LARGE");
        bytes32[] memory ids = new bytes32[](51);
        uint64[] memory vs = new uint64[](51);
        _expectRejected(2, abi.encode(ids, vs), "BATCH_TOO_LARGE");
    }

    function test_SnapshotLengthMismatchRejected() public {
        bytes32[] memory ids = new bytes32[](1);
        uint64[] memory vs = new uint64[](2);
        _expectRejected(2, abi.encode(ids, vs), "LENGTH_MISMATCH");
    }

    function test_EmptySnapshotAccepted() public {
        bytes32[] memory ids = new bytes32[](0);
        uint64[] memory vs = new uint64[](0);
        bytes memory rep = _sendT(2, abi.encode(ids, vs));
        assertTrue(r.seenReport(keccak256(rep)));
        assertEq(vault.lastSnapshotTs(), uint64(block.timestamp));
    }
}
