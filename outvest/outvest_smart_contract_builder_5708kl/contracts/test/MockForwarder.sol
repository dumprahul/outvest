// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReceiver} from "../interfaces/IReceiver.sol";

/// @notice TEST ONLY. Stand-in for the CRE KeystoneForwarder. Reverts from the receiver bubble up unchanged.
contract MockForwarder {
    /// @dev Raw variant: caller supplies arbitrary metadata bytes (use "" against TestReportReceiver).
    function forward(address receiver, bytes calldata metadata, bytes calldata report) external {
        IReceiver(receiver).onReport(metadata, report);
    }

    /// @dev Real-metadata variant: packs bytes32 workflowId | bytes10 name | address owner (62 bytes).
    function forwardPacked(address receiver, bytes32 workflowId, bytes10 name, address owner, bytes calldata report)
        external
    {
        IReceiver(receiver).onReport(abi.encodePacked(workflowId, name, owner), report);
    }
}
