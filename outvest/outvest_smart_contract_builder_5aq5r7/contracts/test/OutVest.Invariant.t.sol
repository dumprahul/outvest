// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ReportReceiver} from "../ReportReceiver.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {MockForwarder} from "./MockForwarder.sol";

/// @dev Drives the vault only through its real entry points (public functions + receiver reports via the forwarder).
contract OutVestHandler is Test {
    CampaignVault public immutable vault;
    MockUSDC public immutable usdc;
    MockForwarder public immutable fwd;
    address public immutable receiver;
    address public immutable brand;

    address[] internal _actors;
    bytes32[] internal _vids;
    mapping(uint8 => uint64) internal _seq;
    mapping(address => uint256) internal _lastPaid;

    bool public paidDecreased;
    bool public paidAboveCap;
    bool public finalizedReverted;
    bool public ghostFinalized;
    uint256 public lastTotalPaid;
    uint256 public calls;
    uint256 public ghostDonated;

    /// @dev Every report byte-string the receiver consumed (accepted or soft-rejected), in submission order.
    bytes[] internal _reports;
    /// @dev Direct apply* calls made from non-receiver callers, and how many of them did NOT revert / reverted wrongly.
    uint256 public ghostDirectApplyAttempts;
    uint256 public ghostDirectApplySuccess;
    uint256 public ghostDirectApplyWrongRevert;
    /// @dev Byte-for-byte resubmissions, and how many were NOT rejected with ReportReceiver.Replay.
    uint256 public ghostReplayAttempts;
    uint256 public ghostReplayNotRejected;
    /// @dev Upfront ghosts: number of first binds observed, and whether any bind paid something other than the upfront.
    uint256 public ghostFirstBinds;
    bool public ghostUpfrontBindWrong;

    constructor(CampaignVault v, MockUSDC u, MockForwarder f, address r, address b) {
        vault = v;
        usdc = u;
        fwd = f;
        receiver = r;
        brand = b;
        for (uint256 i; i < 6; ++i) {
            _actors.push(address(uint160(0xA000 + i)));
        }
        for (uint256 i; i < 8; ++i) {
            bytes memory x = new bytes(11);
            for (uint256 j; j < 11; ++j) {
                x[j] = bytes1(uint8(97 + ((i + j) % 26)));
            }
            _vids.push(bytes32(x));
        }
    }

    function actors() external view returns (address[] memory) {
        return _actors;
    }

    function actorCount() external view returns (uint256) {
        return _actors.length;
    }

    // ---------------------------------------------------------------- helpers

    function _send(uint8 t, bytes memory payload) internal {
        bytes memory rep = abi.encode(t, address(vault), ++_seq[t], uint64(block.timestamp), payload);
        fwd.forward(receiver, "", rep);
        // Only reached when the receiver consumed the report (accepted or soft-rejected); a hard revert undoes this.
        _reports.push(rep);
    }

    function _post() internal {
        ++calls;
        uint256 tp = vault.totalPaid();
        if (tp < lastTotalPaid) paidDecreased = true;
        lastTotalPaid = tp;
        uint256 cap = vault.capPerCreator();
        for (uint256 i; i < _actors.length; ++i) {
            uint256 p = vault.creatorInfo(_actors[i]).paid;
            if (p < _lastPaid[_actors[i]]) paidDecreased = true;
            if (p > cap) paidAboveCap = true;
            _lastPaid[_actors[i]] = p;
        }
        if (ghostFinalized && !vault.finalized()) finalizedReverted = true;
        if (vault.finalized()) ghostFinalized = true;
    }

    // ---------------------------------------------------------------- actions

    function warp(uint256 dt) external {
        dt = bound(dt, 1 hours, 4 days);
        vm.warp(block.timestamp + dt);
        _post();
    }

    /// @dev Jump past the final-report window (optionally also past the deadman timeout) so finalize/settle are reachable.
    function warpToEnd(bool pastDeadman) external {
        uint256 t = uint256(vault.bindDeadline()) + vault.scheduleLength() + (pastDeadman ? vault.deadmanTimeout() : 0);
        if (t > block.timestamp) vm.warp(t);
        _post();
    }

    function fund(uint256 amount) external {
        amount = bound(amount, 0, 1500e6);
        // fund() reverts once finalized; bail out first so the brand prank below is never left dangling.
        if (vault.finalized()) return;
        usdc.mint(brand, amount);
        vm.startPrank(brand);
        usdc.approve(address(vault), amount);
        vault.fund(amount);
        vm.stopPrank();
        _post();
    }

    /// @dev Direct token transfer to the vault, bypassing fund().
    function donate(uint256 amount) external {
        amount = bound(amount, 0, 200e6);
        usdc.mint(address(this), amount);
        usdc.transfer(address(vault), amount);
        ghostDonated += amount;
        _post();
    }

    /// @dev Overwrites any pending request of the actor (no bind report is sent).
    function reRequest(uint256 a, uint256 v) external {
        vm.prank(_actors[a % _actors.length]);
        vault.requestBinding(_vids[v % _vids.length]);
        _post();
    }

    function bind(uint256 a, uint256 v, uint256 baseline) external {
        _doBind(a, v, baseline);
        _post();
    }

    /// @dev Upfront-aware: the actor's wallet rejects transfers (revert or `false` mode) while the bind report lands,
    ///      so the instant payout fails and must be fully restored.
    function bindBlocked(uint256 a, uint256 v, uint256 baseline, bool returnFalse) external {
        usdc.setBlocked(_actors[a % _actors.length], true);
        usdc.setReturnFalse(returnFalse);
        _doBind(a, v, baseline);
        _post();
    }

    function unblock(uint256 a) external {
        usdc.setBlocked(_actors[a % _actors.length], false);
        usdc.setReturnFalse(false);
        _post();
    }

    function _doBind(uint256 a, uint256 v, uint256 baseline) internal {
        address w = _actors[a % _actors.length];
        bytes32 vid = _vids[v % _vids.length];
        vm.prank(w);
        bytes32 ch = vault.requestBinding(vid);
        CampaignVault.Creator memory pre = vault.creatorInfo(w);
        bool wasBlocked = usdc.blocked(w);
        _send(1, abi.encode(w, vid, ch, uint64(bound(baseline, 0, 1000))));
        CampaignVault.Creator memory post = vault.creatorInfo(w);
        if (!pre.bound && post.bound) {
            // First bind: upfront is the floored share of the cap, paid at once unless the wallet is blocked.
            ++ghostFirstBinds;
            if (post.upfront != vault.capPerCreator() * vault.upfrontPpm() / 1_000_000) ghostUpfrontBindWrong = true;
            if (post.paid != (wasBlocked ? 0 : post.upfront)) ghostUpfrontBindWrong = true;
            if (post.remaining != vault.capPerCreator() - post.paid) ghostUpfrontBindWrong = true;
        } else if (pre.bound && post.videoCount > pre.videoCount && post.paid != pre.paid) {
            // Later videos never trigger a payment.
            ghostUpfrontBindWrong = true;
        }
    }

    function snapshot(uint256 v1, uint256 v2, uint256 x1, uint256 x2) external {
        bytes32[] memory ids = new bytes32[](2);
        uint64[] memory vs = new uint64[](2);
        ids[0] = _vids[v1 % _vids.length];
        ids[1] = _vids[v2 % _vids.length];
        vs[0] = uint64(bound(x1, 0, 5_000_000));
        vs[1] = uint64(bound(x2, 0, 5_000_000));
        _send(2, abi.encode(ids, vs));
        _post();
    }

    function finalReport(uint256 v1, uint256 x1) external {
        bytes32[] memory ids = new bytes32[](1);
        uint64[] memory vs = new uint64[](1);
        ids[0] = _vids[v1 % _vids.length];
        vs[0] = uint64(bound(x1, 0, 5_000_000));
        _send(3, abi.encode(ids, vs));
        _post();
    }

    function payout(uint256 seed, uint256 n) external {
        n = bound(n, 0, _actors.length);
        address[] memory w = new address[](n);
        for (uint256 i; i < n; ++i) {
            w[i] = _actors[(seed + i) % _actors.length];
        }
        _send(4, abi.encode(w));
        _post();
    }

    function claim(uint256 a, address caller) external {
        vm.prank(caller);
        vault.claim(_actors[a % _actors.length]);
        _post();
    }

    function settle(uint256 a) external {
        vault.settle(_actors[a % _actors.length]);
        _post();
    }

    function sweep() external {
        vault.sweep();
        _post();
    }

    function deadman() external {
        vault.finalizeFromLastSnapshot();
        _post();
    }

    function toggleBlock(uint256 a, bool blocked_, bool returnFalse) external {
        usdc.setBlocked(_actors[a % _actors.length], blocked_);
        usdc.setReturnFalse(returnFalse);
        _post();
    }

    function reportCount() external view returns (uint256) {
        return _reports.length;
    }

    /// @dev Re-submits a previously consumed report byte-for-byte through the forwarder; it must hit Replay.
    function replay(uint256 i) external {
        if (_reports.length == 0) return;
        bytes memory rep = _reports[i % _reports.length];
        ++ghostReplayAttempts;
        try fwd.forward(receiver, "", rep) {
            ++ghostReplayNotRejected;
        } catch (bytes memory err) {
            if (err.length != 4 || bytes4(err) != ReportReceiver.Replay.selector) ++ghostReplayNotRejected;
        }
        _post();
    }

    function _directCaller(uint256 sel, uint256 a, address rnd) internal view returns (address) {
        sel %= 7;
        if (sel == 0) return address(0x57A9); // stranger
        if (sel == 1) return brand;
        if (sel == 2) return vault.factory();
        if (sel == 3) return address(fwd);
        if (sel == 4) {
            // a bound creator (falls back to the first actor if nobody is bound yet)
            uint256 start = a % _actors.length;
            for (uint256 i; i < _actors.length; ++i) {
                address c = _actors[(start + i) % _actors.length];
                if (vault.creatorInfo(c).bound) return c;
            }
            return _actors[a % _actors.length];
        }
        if (sel == 5) return address(this);
        return rnd == receiver ? address(0x57A9) : rnd;
    }

    /// @dev Calls applyBind/applySnapshot/applyFinal/applyPayout directly from a non-receiver; each must revert NotReceiver.
    function directApply(uint8 which, uint256 sel, uint256 a, address rnd) external {
        address caller = _directCaller(sel, a, rnd);
        bytes32[] memory ids = new bytes32[](1);
        uint64[] memory vs = new uint64[](1);
        ids[0] = _vids[a % _vids.length];
        vs[0] = 1000;
        address[] memory w = new address[](1);
        w[0] = _actors[a % _actors.length];
        bytes32 ch = keccak256(abi.encode(a));
        uint64 ts = uint64(block.timestamp);
        ++ghostDirectApplyAttempts;
        which %= 4;
        // startPrank (not prank): tolerates a prank left dangling by an earlier reverted handler call (e.g. fund()).
        vm.startPrank(caller);
        if (which == 0) {
            try vault.applyBind(w[0], ids[0], ch, 0) returns (bytes32) {
                ++ghostDirectApplySuccess;
            } catch (bytes memory err) {
                _expectNotReceiver(err);
            }
        } else if (which == 1) {
            try vault.applySnapshot(ids, vs, ts) returns (bytes32) {
                ++ghostDirectApplySuccess;
            } catch (bytes memory err) {
                _expectNotReceiver(err);
            }
        } else if (which == 2) {
            try vault.applyFinal(ids, vs, ts) returns (bytes32) {
                ++ghostDirectApplySuccess;
            } catch (bytes memory err) {
                _expectNotReceiver(err);
            }
        } else {
            try vault.applyPayout(w) returns (bytes32) {
                ++ghostDirectApplySuccess;
            } catch (bytes memory err) {
                _expectNotReceiver(err);
            }
        }
        vm.stopPrank();
        _post();
    }

    function _expectNotReceiver(bytes memory err) internal {
        if (err.length != 4 || bytes4(err) != CampaignVault.NotReceiver.selector) ++ghostDirectApplyWrongRevert;
    }
}

contract VaultInvariantTest is OutVestBase {
    OutVestHandler internal h;

    function setUp() public virtual override {
        super.setUp();
        // Instant settlement enabled: 10% of the 300e6 cap (30e6) is paid at each creator's first bind.
        CampaignVault.Params memory p = _params();
        p.upfrontPpm = 100_000;
        vault = _newVault(p);
        _fund(900e6);
        h = new OutVestHandler(vault, usdc, fwd, receiver, brand);
        targetContract(address(h));
        bytes4[] memory sels = new bytes4[](18);
        sels[16] = h.bindBlocked.selector;
        sels[17] = h.unblock.selector;
        sels[14] = h.replay.selector;
        sels[15] = h.directApply.selector;
        sels[0] = h.warp.selector;
        sels[1] = h.fund.selector;
        sels[2] = h.bind.selector;
        sels[3] = h.snapshot.selector;
        sels[4] = h.finalReport.selector;
        sels[5] = h.payout.selector;
        sels[6] = h.claim.selector;
        sels[7] = h.settle.selector;
        sels[8] = h.sweep.selector;
        sels[9] = h.toggleBlock.selector;
        sels[10] = h.deadman.selector;
        sels[11] = h.warpToEnd.selector;
        sels[12] = h.donate.selector;
        sels[13] = h.reRequest.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
    }

    /// @dev Sanity: the new handler actions really exercise their paths (so the invariants below are not vacuous).
    function test_Handler_DirectApplyFromEveryCallerReverts() public {
        for (uint8 which; which < 4; ++which) {
            for (uint256 sel; sel < 7; ++sel) {
                h.directApply(which, sel, sel + which, address(uint160(0xC0FFEE + sel)));
            }
        }
        assertEq(h.ghostDirectApplyAttempts(), 28);
        assertEq(h.ghostDirectApplySuccess(), 0);
        assertEq(h.ghostDirectApplyWrongRevert(), 0);
    }

    function test_Handler_DirectApplyFromBoundCreatorReverts() public {
        h.bind(0, 0, 10);
        assertTrue(vault.creatorInfo(h.actors()[0]).bound);
        for (uint8 which; which < 4; ++which) {
            h.directApply(which, 4, 0, address(0));
        }
        assertEq(h.ghostDirectApplyAttempts(), 4);
        assertEq(h.ghostDirectApplySuccess(), 0);
        assertEq(h.ghostDirectApplyWrongRevert(), 0);
    }

    function test_Handler_ReplayOfAcceptedAndRejectedReportsReverts() public {
        h.bind(0, 0, 10);
        h.warp(5 days);
        h.snapshot(0, 1, 100, 200);
        h.payout(0, 2);
        h.warpToEnd(false);
        h.finalReport(0, 100); // accepted, finalizes
        h.snapshot(0, 1, 100, 200); // soft-rejected (FINALIZED) but the report is consumed
        h.payout(1, 1);
        assertEq(h.reportCount(), 6);
        for (uint256 i; i < h.reportCount(); ++i) {
            h.replay(i);
        }
        assertEq(h.ghostReplayAttempts(), 6);
        assertEq(h.ghostReplayNotRejected(), 0);
    }

    function _sumRemaining() internal view returns (uint256 s) {
        address[] memory a = h.actors();
        for (uint256 i; i < a.length; ++i) {
            s += vault.creatorInfo(a[i]).remaining;
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_BalanceCoversLiability() public view {
        assertGe(usdc.balanceOf(address(vault)), vault.liability());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_LiabilityEqualsSumOfRemaining() public view {
        assertEq(vault.liability(), _sumRemaining());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_PaidMonotoneAndBoundedByCap() public view {
        assertFalse(h.paidDecreased(), "paid decreased");
        assertFalse(h.paidAboveCap(), "paid above cap");
        address[] memory a = h.actors();
        uint256 sumPaid;
        for (uint256 i; i < a.length; ++i) {
            CampaignVault.Creator memory c = vault.creatorInfo(a[i]);
            assertLe(c.paid, vault.capPerCreator());
            assertLe(c.paid + c.remaining, vault.capPerCreator());
            sumPaid += c.paid;
        }
        assertEq(sumPaid, vault.totalPaid());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_FinalizedIsTerminal() public view {
        assertFalse(h.finalizedReverted());
        if (h.ghostFinalized()) assertTrue(vault.finalized());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_EveryTransferGoesToBoundWalletOrBrand() public view {
        address[] memory rs = usdc.recipientsOf(address(vault));
        for (uint256 i; i < rs.length; ++i) {
            assertTrue(rs[i] == brand || vault.creatorInfo(rs[i]).bound, "transfer to unbound recipient");
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_FundsConserved() public view {
        uint256 swept = usdc.sentTo(address(vault), brand);
        assertEq(usdc.balanceOf(address(vault)) + vault.totalPaid() + swept, vault.totalFunded() + h.ghostDonated());
        address[] memory a = h.actors();
        for (uint256 i; i < a.length; ++i) {
            assertEq(usdc.sentTo(address(vault), a[i]), vault.creatorInfo(a[i]).paid);
            assertEq(usdc.balanceOf(a[i]), vault.creatorInfo(a[i]).paid);
        }
        assertLe(vault.creatorCount(), vault.maxCreators());
    }

    /// Only the receiver can reach apply*: direct calls from anyone else always revert NotReceiver.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_OnlyReceiverReachesApply() public view {
        assertEq(h.ghostDirectApplySuccess(), 0, "non-receiver reached apply*");
        assertEq(h.ghostDirectApplyWrongRevert(), 0, "direct apply* reverted with something other than NotReceiver");
    }

    /// Sanity: a first bind pays the upfront at once; a blocked bind leaves it unpaid but claimable.
    function test_Handler_UpfrontPaidAtBindAndRestoredWhenBlocked() public {
        h.bind(0, 0, 10);
        address a0 = h.actors()[0];
        assertEq(usdc.balanceOf(a0), 30e6);
        assertEq(vault.creatorInfo(a0).paid, 30e6);
        h.bindBlocked(1, 1, 10, false);
        address a1 = h.actors()[1];
        assertTrue(vault.creatorInfo(a1).bound);
        assertEq(vault.creatorInfo(a1).paid, 0);
        assertEq(vault.creatorInfo(a1).remaining, 300e6);
        h.unblock(1);
        assertEq(vault.claimable(a1), 30e6);
        h.claim(1, address(this));
        assertEq(usdc.balanceOf(a1), 30e6);
        assertEq(h.ghostFirstBinds(), 2);
        assertFalse(h.ghostUpfrontBindWrong());
    }

    /// Upfront accounting: stored upfront is the floored share, entitlement never exceeds the cap, a settled
    /// creator's final entitlement (paid + remaining) is never below the upfront, and binds only ever pay the upfront.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_UpfrontAccounting() public view {
        assertFalse(h.ghostUpfrontBindWrong(), "bind paid something other than the upfront");
        uint256 expectedUp = vault.capPerCreator() * vault.upfrontPpm() / 1_000_000;
        address[] memory a = h.actors();
        for (uint256 i; i < a.length; ++i) {
            CampaignVault.Creator memory c = vault.creatorInfo(a[i]);
            if (!c.bound) {
                assertEq(c.upfront, 0);
                assertEq(vault.claimable(a[i]), 0);
                continue;
            }
            assertEq(c.upfront, expectedUp);
            assertLe(uint256(c.paid) + vault.claimable(a[i]), vault.capPerCreator(), "entitlement above cap");
            assertLe(vault.claimable(a[i]), c.remaining);
            if (c.settled) assertGe(uint256(c.paid) + c.remaining, c.upfront, "settle dropped the upfront");
        }
    }

    /// A report byte-for-byte resubmitted (whether it was accepted or soft-rejected) always reverts Replay.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    function invariant_ReplayedReportsRejected() public view {
        assertEq(h.ghostReplayNotRejected(), 0, "replayed report not rejected with Replay");
    }
}
