// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScheduleLib} from "../ScheduleLib.sol";

contract ScheduleHarness {
    function validate(ScheduleLib.Segment[] memory s) external pure {
        ScheduleLib.validate(s);
    }

    function fraction(ScheduleLib.Segment[] memory s, uint256 e) external pure returns (uint256) {
        return ScheduleLib.fractionPpm(s, e);
    }
}

contract ScheduleLibTest is Test {
    ScheduleHarness internal h;
    uint32 internal constant D = 1 days;
    uint32 internal constant FULL = 1_000_000;

    function setUp() public {
        h = new ScheduleHarness();
    }

    function _seg(uint32 s, uint32 a, uint32 b) internal pure returns (ScheduleLib.Segment memory) {
        return ScheduleLib.Segment(s, a, b);
    }

    function _two(ScheduleLib.Segment memory a, ScheduleLib.Segment memory b)
        internal
        pure
        returns (ScheduleLib.Segment[] memory r)
    {
        r = new ScheduleLib.Segment[](2);
        r[0] = a;
        r[1] = b;
    }

    function _three(ScheduleLib.Segment memory a, ScheduleLib.Segment memory b, ScheduleLib.Segment memory c)
        internal
        pure
        returns (ScheduleLib.Segment[] memory r)
    {
        r = new ScheduleLib.Segment[](3);
        r[0] = a;
        r[1] = b;
        r[2] = c;
    }

    function _bad(ScheduleLib.Segment[] memory s) internal {
        vm.expectRevert(ScheduleLib.InvalidSchedule.selector);
        h.validate(s);
    }

    // ------------------------------------------------------------ accept

    function test_Accepts_DefaultSchedule() public view {
        h.validate(ScheduleLib.defaultSchedule());
    }

    function test_Accepts_InstantRelease() public view {
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](1);
        s[0] = _seg(0, FULL, FULL);
        h.validate(s);
    }

    function test_Accepts_EightSegments() public view {
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](8);
        s[0] = _seg(0, 0, 0);
        for (uint32 i = 1; i < 7; ++i) s[i] = _seg(i * 10 * D, 0, 0);
        s[7] = _seg(70 * D, FULL, FULL);
        h.validate(s);
    }

    function test_Accepts_EarlyRampExactly250k() public view {
        h.validate(_three(_seg(0, 0, 0), _seg(7 * D, 0, 250_000), _seg(30 * D, FULL, FULL)));
    }

    function test_Accepts_LargeEndPpmAfterJump() public view {
        h.validate(_three(_seg(0, 0, 0), _seg(7 * D, 500_000, 900_000), _seg(30 * D, FULL, FULL)));
    }

    function test_Accepts_LastStartExactly365Days() public view {
        h.validate(_two(_seg(0, 0, 0), _seg(365 * D, FULL, FULL)));
    }

    // ------------------------------------------------------------ reject

    function test_Rejects_Empty() public {
        _bad(new ScheduleLib.Segment[](0));
    }

    function test_Rejects_MoreThanEightSegments() public {
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](9);
        s[0] = _seg(0, 0, 0);
        for (uint32 i = 1; i < 8; ++i) s[i] = _seg(i * 10 * D, 0, 0);
        s[8] = _seg(80 * D, FULL, FULL);
        _bad(s);
    }

    function test_Rejects_FirstStartNonZero() public {
        _bad(_two(_seg(1, 0, 0), _seg(10 * D, FULL, FULL)));
    }

    function test_Rejects_EqualStarts() public {
        _bad(_three(_seg(0, 0, 0), _seg(10 * D, 0, 0), _seg(10 * D, FULL, FULL)));
    }

    function test_Rejects_DecreasingStarts() public {
        _bad(_three(_seg(0, 0, 0), _seg(10 * D, 0, 0), _seg(5 * D, FULL, FULL)));
    }

    function test_Rejects_StartPpmAboveEndPpm() public {
        _bad(_three(_seg(0, 0, 0), _seg(10 * D, 100, 50), _seg(20 * D, FULL, FULL)));
    }

    function test_Rejects_PpmAboveMillion() public {
        _bad(_three(_seg(0, 0, 0), _seg(10 * D, 0, 100), _seg(20 * D, FULL, FULL + 1)));
        _bad(_two(_seg(0, 0, 0), _seg(10 * D, FULL + 1, FULL + 1)));
    }

    function test_Rejects_EndPpmAboveNextStartPpm() public {
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](4);
        s[0] = _seg(0, 0, 0);
        s[1] = _seg(10 * D, 0, 200_000);
        s[2] = _seg(20 * D, 100_000, 100_000);
        s[3] = _seg(30 * D, FULL, FULL);
        _bad(s);
    }

    function test_Rejects_LastNotFullStartPpm() public {
        _bad(_two(_seg(0, 0, 0), _seg(10 * D, 500_000, 500_000)));
        _bad(_two(_seg(0, 0, 0), _seg(10 * D, 999_999, FULL)));
    }

    function test_Rejects_LastNotFullEndPpm() public {
        // startPpm == 1e6 forces endPpm == 1e6 (start<=end<=1e6), so only the single-segment 0/0 case remains
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](1);
        s[0] = _seg(0, 0, 0);
        _bad(s);
    }

    function test_Rejects_EarlyJumpAbove250k() public {
        _bad(_three(_seg(0, 0, 0), _seg(7 * D, 0, 250_001), _seg(30 * D, FULL, FULL)));
        _bad(_two(_seg(0, 0, 300_000), _seg(30 * D, FULL, FULL)));
    }

    function test_Rejects_StartBeyond365Days() public {
        _bad(_two(_seg(0, 0, 0), _seg(365 * D + 1, FULL, FULL)));
    }

    // ------------------------------------------------------------ fractionPpm

    function _f(uint256 e) internal view returns (uint256) {
        return h.fraction(ScheduleLib.defaultSchedule(), e);
    }

    function test_Fraction_DefaultKnownPoints() public view {
        assertEq(_f(0), 0);
        assertEq(_f(3 days + 12 hours), 0);
        assertEq(_f(7 days), 0);
        assertEq(_f(18 days + 12 hours), 100_000); // midpoint of the 7d..30d ramp
        assertEq(_f(20 days), 113_043); // floor(13/23 * 200000)
        assertEq(_f(30 days - 1), 199_999); // just before the step to 500k (floor)
        assertEq(_f(30 days), 500_000);
        assertEq(_f(45 days), 500_000);
        assertEq(_f(60 days), 800_000);
        assertEq(_f(75 days), 800_000);
        assertEq(_f(90 days), FULL);
        assertEq(_f(1000 days), FULL);
    }

    /// The documented default-schedule table.
    function test_Fraction_SpecTable() public view {
        assertEq(_f(3 days), 0);
        assertEq(_f(7 days), 0);
        assertEq(_f(18 days + 12 hours), 100_000);
        assertEq(_f(20 days), 113_043);
        assertEq(_f(30 days), 500_000);
        assertEq(_f(45 days), 500_000);
        assertEq(_f(60 days), 800_000);
        assertEq(_f(90 days), 1_000_000);
    }

    function test_Accepts_FirstSegmentStartingWithJump() public view {
        h.validate(_two(_seg(0, 300_000, 300_000), _seg(30 * D, FULL, FULL)));
    }

    function test_Rejects_NonZeroStartWithSingleSegmentNotFull() public {
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](1);
        s[0] = _seg(5, FULL, FULL); // first start must be 0
        _bad(s);
    }

    function test_Rejects_SecondRampAbove250kBeforeAnyJump() public {
        // continuous ramps (no jump yet) may never exceed 25% of the total
        _bad(_three(_seg(0, 0, 100_000), _seg(10 * D, 100_000, 300_000), _seg(30 * D, FULL, FULL)));
    }

    function test_Fraction_InterpolatesLinearlyOnRamp() public {
        ScheduleLib.Segment[] memory s = _two(_seg(0, 0, 0), _seg(100, FULL, FULL));
        assertEq(h.fraction(s, 99), 0);
        s = _three(_seg(0, 0, 400_000), _seg(100, 400_000, 800_000), _seg(200, FULL, FULL));
        assertEq(h.fraction(s, 0), 0);
        assertEq(h.fraction(s, 50), 200_000);
        assertEq(h.fraction(s, 100), 400_000);
        assertEq(h.fraction(s, 150), 600_000);
        assertEq(h.fraction(s, 199), 796_000);
        assertEq(h.fraction(s, 200), FULL);
    }

    function testFuzz_Fraction_NonDecreasingDefault(uint256 e1, uint256 e2) public view {
        e1 = bound(e1, 0, 400 days);
        e2 = bound(e2, 0, 400 days);
        (uint256 lo, uint256 hi) = e1 <= e2 ? (e1, e2) : (e2, e1);
        uint256 a = _f(lo);
        uint256 b = _f(hi);
        assertLe(a, b);
        assertLe(b, FULL);
    }

    function testFuzz_Fraction_NonDecreasingRandomValidSchedule(uint256 seed, uint256 e1, uint256 e2) public view {
        uint256 n = 2 + seed % 7; // 2..8
        ScheduleLib.Segment[] memory s = new ScheduleLib.Segment[](n);
        uint32 prevEnd = 0;
        for (uint256 i; i < n - 1; ++i) {
            uint32 end = i == 0 ? 0 : uint32(prevEnd + uint256(keccak256(abi.encode(seed, i))) % 100_000);
            if (end > 250_000) end = 250_000;
            uint32 start = i == 0 ? 0 : prevEnd;
            s[i] = _seg(uint32(i * 10 * D), start, end);
            prevEnd = end;
        }
        s[n - 1] = _seg(uint32((n - 1) * 10 * D), FULL, FULL);
        h.validate(s); // generator sanity: must be a valid schedule

        e1 = bound(e1, 0, 120 days);
        e2 = bound(e2, 0, 120 days);
        (uint256 lo, uint256 hi) = e1 <= e2 ? (e1, e2) : (e2, e1);
        assertLe(h.fraction(s, lo), h.fraction(s, hi));
        assertLe(h.fraction(s, hi), FULL);
    }
}
