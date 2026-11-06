// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";
import {ReportReceiver} from "../ReportReceiver.sol";
import {ScheduleLib} from "../ScheduleLib.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {MockForwarder} from "./MockForwarder.sol";
import {TestReportReceiver} from "./TestReportReceiver.sol";

/// @dev Shared fixtures. By default the production receiver bytecode at `factory.receiver()` is replaced by the
///      TestReportReceiver runtime (skips metadata auth only) so functional tests can use a metadata-free forwarder.
abstract contract OutVestBase is Test {
    uint256 internal constant T0 = 1_728_000_000; // multiple of 86400 -> bucket aligned
    bytes32 internal constant WF_BIND = keccak256("wf.bind");
    bytes32 internal constant WF_SNAP = keccak256("wf.snapshot");
    bytes32 internal constant WF_FINAL = keccak256("wf.final");
    bytes32 internal constant WF_PAY = keccak256("wf.payout");
    bytes32 internal constant VID = bytes32("dQw4w9WgXcQ");
    bytes32 internal constant VID2 = bytes32("abcdefghijk");
    bytes10 internal constant WF_NAME = bytes10("outvest");

    MockUSDC internal usdc;
    MockForwarder internal fwd;
    CampaignFactory internal factory;
    CampaignVault internal vault;
    address internal receiver;

    address internal wfOwner = makeAddr("wfOwner");
    address internal brand = makeAddr("brand");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal stranger = makeAddr("stranger");

    mapping(address => mapping(uint8 => uint64)) internal seqOf;

    function _useTestReceiver() internal pure virtual returns (bool) {
        return true;
    }

    function setUp() public virtual {
        vm.warp(T0);
        usdc = new MockUSDC();
        fwd = new MockForwarder();
        factory = new CampaignFactory(address(fwd));
        factory.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        receiver = factory.receiver();
        if (_useTestReceiver()) {
            TestReportReceiver t = new TestReportReceiver(address(fwd), address(factory));
            vm.etch(receiver, address(t).code);
        }
        vault = CampaignVault(factory.createCampaign(_params()));
    }

    // ---------------------------------------------------------------- params

    function _params() internal view returns (CampaignVault.Params memory p) {
        p.brand = brand;
        p.usdc = address(usdc);
        p.bindDeadline = uint64(block.timestamp + 7 days);
        p.ratePerThousand = 2e6;
        p.capPerCreator = 300e6;
        p.maxCreators = 10;
        p.maxVideosPerCreator = 3;
        p.bucketLen = 1 days;
        p.maxGrowthPerDay = 1e12;
        p.staleAfter = 7 days;
        p.deadmanTimeout = 30 days;
        p.minPayout = 0;
        p.schedule = ScheduleLib.defaultSchedule();
    }

    function _newVault(CampaignVault.Params memory p) internal returns (CampaignVault) {
        return CampaignVault(factory.createCampaign(p));
    }

    // ---------------------------------------------------------------- reports

    function _nextSeq(address v, uint8 t) internal returns (uint64) {
        return ++seqOf[v][t];
    }

    function _envelope(uint8 t, address v, uint64 seq, uint64 ts, bytes memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(t, v, seq, ts, payload);
    }

    function _send(bytes memory report) internal {
        fwd.forward(receiver, "", report);
    }

    function _sendTo(CampaignVault v, uint8 t, bytes memory payload) internal returns (bytes memory r) {
        r = _envelope(t, address(v), _nextSeq(address(v), t), uint64(block.timestamp), payload);
        _send(r);
    }

    function _sendT(uint8 t, bytes memory payload) internal returns (bytes memory) {
        return _sendTo(vault, t, payload);
    }

    function _bindPayload(address w, bytes32 vid, bytes32 ch, uint64 base) internal pure returns (bytes memory) {
        return abi.encode(w, vid, ch, base);
    }

    function _ids(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _vals(uint64 a) internal pure returns (uint64[] memory r) {
        r = new uint64[](1);
        r[0] = a;
    }

    function _snapPayload(bytes32 vid, uint64 views_) internal pure returns (bytes memory) {
        return abi.encode(_ids(vid), _vals(views_));
    }

    function _wallets(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    // ---------------------------------------------------------------- actions

    function _fundVault(CampaignVault v, uint256 amount) internal {
        usdc.mint(brand, amount);
        vm.startPrank(brand);
        usdc.approve(address(v), amount);
        v.fund(amount);
        vm.stopPrank();
    }

    function _fund(uint256 amount) internal {
        _fundVault(vault, amount);
    }

    function _request(address w, bytes32 vid) internal returns (bytes32 ch) {
        vm.prank(w);
        ch = vault.requestBinding(vid);
    }

    /// @dev request + bind report (accepted path). Returns the challenge.
    function _bind(address w, bytes32 vid, uint64 baseline) internal returns (bytes32 ch) {
        ch = _request(w, vid);
        _sendT(1, _bindPayload(w, vid, ch, baseline));
    }

    function _snap(bytes32 vid, uint64 views_) internal {
        _sendT(2, _snapPayload(vid, views_));
    }

    function _final(bytes32 vid, uint64 views_) internal {
        _sendT(3, _snapPayload(vid, views_));
    }

    function _payout(address w) internal {
        _sendT(4, abi.encode(_wallets(w)));
    }

    /// @dev Direct call of applyBind as the receiver (bypasses report envelope checks).
    function _applyBind(address w, bytes32 vid, bytes32 ch, uint64 base) internal returns (bytes32) {
        vm.prank(receiver);
        return vault.applyBind(w, vid, ch, base);
    }

    /// @dev Direct applySnapshot of a single video as the receiver.
    function _direct(bytes32 vid, uint64 views_, uint64 ts) internal returns (bytes32) {
        vm.prank(receiver);
        return vault.applySnapshot(_ids(vid), _vals(views_), ts);
    }

    function _finalizeByDeadman() internal {
        vm.warp(uint256(vault.bindDeadline()) + vault.scheduleLength() + vault.deadmanTimeout());
        vault.finalizeFromLastSnapshot();
    }

    function _finalTime() internal view returns (uint256) {
        return uint256(vault.bindDeadline()) + vault.scheduleLength();
    }

    function _asReceiver() internal {
        vm.prank(receiver);
    }

    /// @dev Warp to `T0 + d days`.
    function _day(uint256 d) internal {
        vm.warp(T0 + d * 1 days);
    }

    /// @dev Distinct valid 11-char left-aligned video id for index i.
    function _vid(uint256 i) internal pure returns (bytes32) {
        bytes memory b = new bytes(11);
        uint256 x = i;
        for (uint256 j; j < 11; ++j) {
            b[j] = bytes1(uint8(97 + (x % 26)));
            x /= 26;
        }
        return bytes32(b);
    }
}
