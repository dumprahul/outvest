// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReportReceiver} from "../ReportReceiver.sol";

/// @notice TEST ONLY. NEVER DEPLOY. Skips metadata authentication for metadata-free mock forwarders.
/// @dev Forwarder authentication, registration, replay, freshness and vault authorization remain enabled.
contract TestReportReceiver is ReportReceiver {
    constructor(address mockForwarder, address factory_) ReportReceiver(mockForwarder, factory_) {}

    function _checkMetadata(bytes calldata, uint8) internal pure override {}
}
