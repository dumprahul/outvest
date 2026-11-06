// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IReceiver, ReportReasons} from "./interfaces/IReceiver.sol";
import {ICampaignFactory} from "./interfaces/ICampaignFactory.sol";
import {CampaignVault} from "./CampaignVault.sol";

/// @notice Authenticated workflow ingress; rejected business reports are consumed, not retryable.
contract ReportReceiver is IReceiver, ERC165, ReentrancyGuard {
    uint256 public constant MAX_SNAPSHOT_ENTRIES = 50;
    uint256 public constant MAX_BATCH = 25;
    uint256 public constant MAX_SKEW = 15 minutes;
    uint256 public constant MAX_AGE = 3 days;
    address public immutable forwarder;
    ICampaignFactory public immutable factory;
    mapping(address => mapping(uint8 => uint64)) public lastSeq;
    mapping(address => mapping(uint8 => uint64)) public lastTs;
    mapping(bytes32 => bool) public seenReport;

    struct Envelope {
        uint8 rtype;
        address vault;
        uint64 seq;
        uint64 ts;
        bytes payload;
    }

    error InvalidAddress();
    error NotForwarder();
    error InvalidMetadata();
    error WrongOwner();
    error WrongWorkflow();
    error UnknownReportType();
    error UnknownVault();
    error Replay();

    event ReportAccepted(address indexed vault, uint8 indexed rtype, uint64 seq);
    event ReportRejected(address indexed vault, uint8 indexed rtype, bytes32 reason);

    constructor(address forwarder_, address factory_) {
        if (forwarder_ == address(0) || factory_ == address(0)) revert InvalidAddress();
        forwarder = forwarder_;
        factory = ICampaignFactory(factory_);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function onReport(bytes calldata metadata, bytes calldata report) external override nonReentrant {
        if (msg.sender != forwarder) revert NotForwarder();
        // Phase zero authenticates the owner before decoding the envelope.
        _checkMetadata(metadata, 0);
        Envelope memory e;
        (e.rtype, e.vault, e.seq, e.ts, e.payload) = abi.decode(report, (uint8, address, uint64, uint64, bytes));
        if (e.rtype < 1 || e.rtype > 4) revert UnknownReportType();
        _checkMetadata(metadata, e.rtype);
        if (!factory.isVault(e.vault)) revert UnknownVault();
        bytes32 reportHash = keccak256(report);
        if (seenReport[reportHash]) revert Replay();
        seenReport[reportHash] = true;
        bytes32 reason;
        if (e.seq <= lastSeq[e.vault][e.rtype]) reason = ReportReasons.STALE_SEQ;
        else if (uint256(e.ts) > block.timestamp + MAX_SKEW) reason = ReportReasons.FUTURE_TS;
        else if (uint256(e.ts) + MAX_AGE < block.timestamp || e.ts < lastTs[e.vault][e.rtype]) {
            reason = ReportReasons.STALE_TS;
        }
        if (reason != bytes32(0)) {
            emit ReportRejected(e.vault, e.rtype, reason);
            return;
        }
        lastSeq[e.vault][e.rtype] = e.seq;
        lastTs[e.vault][e.rtype] = e.ts;
        reason = _route(e);
        if (reason != bytes32(0)) emit ReportRejected(e.vault, e.rtype, reason);
        else emit ReportAccepted(e.vault, e.rtype, e.seq);
    }

    /// @dev Only this hook is bypassed by the explicitly test-only receiver subclass.
    /// rtype zero performs the pre-decode owner check; types 1..4 also authenticate the workflow.
    function _checkMetadata(bytes calldata metadata, uint8 rtype) internal view virtual {
        // Forwarders may append trailing fields; only the first 62 bytes are used.
        if (metadata.length < 62) revert InvalidMetadata();
        bytes32 workflowId = bytes32(metadata[0:32]);
        address owner = address(bytes20(metadata[42:62]));
        if (owner == address(0) || owner != factory.workflowOwner()) revert WrongOwner();
        if (rtype == 0) return;
        bytes32 pinned = rtype == 1 ? factory.wfBind() : rtype == 2 ? factory.wfSnapshot()
            : rtype == 3 ? factory.wfFinal() : factory.wfPayout();
        if (pinned == bytes32(0) || workflowId != pinned) revert WrongWorkflow();
    }

    function _route(Envelope memory e) private returns (bytes32) {
        bytes32 reason = _validatePayload(e.rtype, e.payload);
        if (reason != bytes32(0)) return reason;
        CampaignVault vault = CampaignVault(e.vault);
        if (e.rtype == 1) {
            (address wallet, bytes32 videoId, bytes32 challenge, uint64 baseline) =
                abi.decode(e.payload, (address, bytes32, bytes32, uint64));
            return vault.applyBind(wallet, videoId, challenge, baseline);
        }
        if (e.rtype == 4) return vault.applyPayout(abi.decode(e.payload, (address[])));
        (bytes32[] memory ids, uint64[] memory views_) = abi.decode(e.payload, (bytes32[], uint64[]));
        if (e.rtype == 2) return vault.applySnapshot(ids, views_, e.ts);
        return vault.applyFinal(ids, views_, e.ts);
    }

    /// @dev Accept canonical ABI only; reject malformed/unbounded payloads before array allocation.
    function _validatePayload(uint8 rtype, bytes memory p) private pure returns (bytes32) {
        if (rtype == 1) {
            if (p.length != 128 || _word(p, 0) > type(uint160).max || _word(p, 96) > type(uint64).max) {
                return ReportReasons.MALFORMED_PAYLOAD;
            }
            return bytes32(0);
        }
        if (rtype == 4) {
            if (p.length < 64 || _word(p, 0) != 32) return ReportReasons.MALFORMED_PAYLOAD;
            uint256 n = _word(p, 32);
            if (n > MAX_BATCH) return ReportReasons.BATCH_TOO_LARGE;
            if (p.length != 64 + n * 32) return ReportReasons.MALFORMED_PAYLOAD;
            for (uint256 i; i < MAX_BATCH; ++i) {
                if (i == n) break;
                if (_word(p, 64 + i * 32) > type(uint160).max) return ReportReasons.MALFORMED_PAYLOAD;
            }
            return bytes32(0);
        }
        if (p.length < 128 || _word(p, 0) != 64) return ReportReasons.MALFORMED_PAYLOAD;
        uint256 count = _word(p, 64);
        if (count > MAX_SNAPSHOT_ENTRIES) return ReportReasons.BATCH_TOO_LARGE;
        uint256 offset = 96 + count * 32;
        if (_word(p, 32) != offset || p.length < offset + 32) return ReportReasons.MALFORMED_PAYLOAD;
        uint256 otherCount = _word(p, offset);
        if (otherCount > MAX_SNAPSHOT_ENTRIES) return ReportReasons.BATCH_TOO_LARGE;
        if (count != otherCount) return ReportReasons.LENGTH_MISMATCH;
        if (p.length != offset + 32 + count * 32) return ReportReasons.MALFORMED_PAYLOAD;
        for (uint256 i; i < MAX_SNAPSHOT_ENTRIES; ++i) {
            if (i == count) break;
            if (_word(p, offset + 32 + i * 32) > type(uint64).max) return ReportReasons.MALFORMED_PAYLOAD;
        }
        return bytes32(0);
    }

    function _word(bytes memory data, uint256 offset) private pure returns (uint256 value) {
        // Callers validate that the complete word exists before reading it.
        for (uint256 i; i < 32; ++i) {
            value = (value << 8) | uint8(data[offset + i]);
        }
    }
}
