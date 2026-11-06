// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Monotone, piecewise-linear release schedule. All divisions round down.
library ScheduleLib {
    uint256 internal constant PPM = 1_000_000;
    uint256 internal constant MAX_DRIP_PPM = 250_000;
    uint256 internal constant MAX_SEGMENTS = 8;
    uint256 internal constant MAX_LENGTH = 365 days;

    struct Segment {
        uint32 start;
        uint32 startPpm;
        uint32 endPpm;
    }

    error InvalidSchedule();

    function validate(Segment[] memory segments) internal pure {
        uint256 n = segments.length;
        if (n == 0 || n > MAX_SEGMENTS || segments[0].start != 0) revert InvalidSchedule();
        bool jumped;
        for (uint256 i; i < MAX_SEGMENTS; ++i) {
            if (i == n) break;
            Segment memory s = segments[i];
            if (s.startPpm > s.endPpm || s.endPpm > PPM) revert InvalidSchedule();
            if (i != 0) {
                Segment memory previous = segments[i - 1];
                if (s.start <= previous.start || previous.endPpm > s.startPpm) revert InvalidSchedule();
                if (s.startPpm > previous.endPpm) jumped = true;
            } else if (s.startPpm != 0) {
                jumped = true;
            }
            if (!jumped && s.endPpm > MAX_DRIP_PPM) revert InvalidSchedule();
        }
        Segment memory last = segments[n - 1];
        if (last.start > MAX_LENGTH || last.startPpm != PPM || last.endPpm != PPM) {
            revert InvalidSchedule();
        }
    }

    function fractionPpm(Segment[] memory segments, uint256 elapsed) internal pure returns (uint256) {
        uint256 n = segments.length;
        uint256 index;
        for (uint256 i = 1; i < MAX_SEGMENTS; ++i) {
            if (i == n || segments[i].start > elapsed) break;
            index = i;
        }
        Segment memory s = segments[index];
        if (index == n - 1) return s.startPpm;
        return uint256(s.startPpm) + uint256(s.endPpm - s.startPpm) * (elapsed - s.start)
            / (segments[index + 1].start - s.start);
    }

    function defaultSchedule() internal pure returns (Segment[] memory segments) {
        segments = new Segment[](5);
        segments[0] = Segment(0, 0, 0);
        segments[1] = Segment(7 days, 0, 200_000);
        segments[2] = Segment(30 days, 500_000, 500_000);
        segments[3] = Segment(60 days, 800_000, 800_000);
        segments[4] = Segment(90 days, 1_000_000, 1_000_000);
    }
}
