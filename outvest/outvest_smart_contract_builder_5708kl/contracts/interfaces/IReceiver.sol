// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Stable business-rejection codes shared by the receiver and vault.
library ReportReasons {
    bytes32 internal constant DEADLINE = "DEADLINE";
    bytes32 internal constant NO_MATCH = "NO_MATCH";
    bytes32 internal constant VIDEO_TAKEN = "VIDEO_TAKEN";
    bytes32 internal constant FULL = "FULL";
    bytes32 internal constant BUDGET = "BUDGET";
    bytes32 internal constant MAX_VIDEOS = "MAX_VIDEOS";
    bytes32 internal constant STALE_SEQ = "STALE_SEQ";
    bytes32 internal constant STALE_TS = "STALE_TS";
    bytes32 internal constant FUTURE_TS = "FUTURE_TS";
    bytes32 internal constant UNKNOWN_VIDEO = "UNKNOWN_VIDEO";
    bytes32 internal constant FINALIZED = "FINALIZED";
    bytes32 internal constant FINAL_TOO_EARLY = "FINAL_TOO_EARLY";
    bytes32 internal constant BATCH_TOO_LARGE = "BATCH_TOO_LARGE";
    bytes32 internal constant LENGTH_MISMATCH = "LENGTH_MISMATCH";
    bytes32 internal constant MALFORMED_PAYLOAD = "MALFORMED_PAYLOAD";
}

interface IReceiver is IERC165 {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
