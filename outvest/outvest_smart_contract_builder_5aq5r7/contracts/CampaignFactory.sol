// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ScheduleLib} from "./ScheduleLib.sol";
import {CampaignVault} from "./CampaignVault.sol";
import {ReportReceiver} from "./ReportReceiver.sol";

/// @notice Permissionless factory after one irrevocable deployer-only identity bootstrap.
contract CampaignFactory {
    address public immutable forwarder;
    address public immutable receiver;
    address private immutable _deployer;
    address public workflowOwner;
    bytes32 public wfBind;
    bytes32 public wfSnapshot;
    bytes32 public wfFinal;
    bytes32 public wfPayout;
    bool public identityLocked;
    mapping(address => bool) public isVault;
    address[] private _campaigns;

    error InvalidIdentity();
    error InvalidParams();
    error NotDeployer();
    error Unauthorized();
    error IdentityAlreadyLocked();
    error IdentityNotLocked();

    event IdentityLocked(address indexed workflowOwner, bytes32 wfBind, bytes32 wfSnapshot, bytes32 wfFinal, bytes32 wfPayout);
    event CampaignCreated(address indexed vault, address indexed brand, bytes32 rulesHash);
    event VerifyRequested(address indexed vault, address indexed wallet, bytes32 indexed videoId, bytes32 challenge);

    constructor(address forwarder_) {
        if (forwarder_ == address(0)) revert InvalidIdentity();
        forwarder = forwarder_;
        _deployer = msg.sender;
        receiver = address(new ReportReceiver(forwarder_, address(this)));
    }

    function lockIdentity(address owner, bytes32 bindId, bytes32 snapshotId, bytes32 finalId, bytes32 payoutId) external {
        if (msg.sender != _deployer) revert NotDeployer();
        if (identityLocked) revert IdentityAlreadyLocked();
        if (owner == address(0) || bindId == bytes32(0) || snapshotId == bytes32(0)
            || finalId == bytes32(0) || payoutId == bytes32(0)
            || bindId == snapshotId || bindId == finalId || bindId == payoutId
            || snapshotId == finalId || snapshotId == payoutId || finalId == payoutId) revert InvalidIdentity();
        workflowOwner = owner;
        wfBind = bindId;
        wfSnapshot = snapshotId;
        wfFinal = finalId;
        wfPayout = payoutId;
        identityLocked = true;
        emit IdentityLocked(owner, bindId, snapshotId, finalId, payoutId);
    }

    function createCampaign(CampaignVault.Params calldata params) external returns (address vault) {
        if (!identityLocked) revert IdentityNotLocked();
        ScheduleLib.validate(params.schedule);
        if (params.brand == address(0) || params.usdc == address(0) || params.bindDeadline <= block.timestamp
            || params.capPerCreator == 0 || params.capPerCreator > type(uint128).max
            || params.ratePerThousand == 0 || params.ratePerThousand > type(uint128).max
            || params.maxCreators == 0 || params.maxVideosPerCreator == 0 || params.maxVideosPerCreator > 10
            || params.bucketLen < 1 hours || params.bucketLen > 7 days || params.staleAfter < 1 days
            || params.upfrontPpm > 100_000) {
            revert InvalidParams();
        }
        bytes32 hash = keccak256(abi.encode(params, receiver, forwarder, workflowOwner,
            wfBind, wfSnapshot, wfFinal, wfPayout, block.chainid, address(this)));
        vault = address(new CampaignVault(params, receiver, address(this), hash));
        isVault[vault] = true;
        _campaigns.push(vault);
        emit CampaignCreated(vault, params.brand, hash);
    }

    function emitVerifyRequest(address wallet, bytes32 videoId, bytes32 challenge) external {
        if (!isVault[msg.sender]) revert Unauthorized();
        emit VerifyRequested(msg.sender, wallet, videoId, challenge);
    }

    function campaignCount() external view returns (uint256) { return _campaigns.length; }
    function campaignAt(uint256 index) external view returns (address) { return _campaigns[index]; }
}
