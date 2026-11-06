// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal local interface, avoiding circular suite imports.
interface ICampaignFactory {
    function workflowOwner() external view returns (address);
    function wfBind() external view returns (bytes32);
    function wfSnapshot() external view returns (bytes32);
    function wfFinal() external view returns (bytes32);
    function wfPayout() external view returns (bytes32);
    function isVault(address vault) external view returns (bool);
    function emitVerifyRequest(address wallet, bytes32 videoId, bytes32 challenge) external;
}
