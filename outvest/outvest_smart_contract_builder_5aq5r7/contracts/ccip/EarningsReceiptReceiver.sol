// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/// @notice Stores creators' OutVest earnings receipts on a destination chain.
/// @dev Accepts messages only from the one pinned source chain and EarningsReceiptSender (set at deploy, no owner).
/// A receipt can only ratchet upward, so a late or replayed older message cannot lower a record.
contract EarningsReceiptReceiver is CCIPReceiver {
    struct Receipt {
        uint256 paid; // USDC base units (6 decimals) paid to the creator by the vault, as of the source block
        uint64 sourceTimestamp;
        uint64 sourceBlock;
        uint64 receivedAt;
    }

    uint64 public immutable sourceSelector;
    address public immutable sourceSender;

    mapping(address wallet => mapping(address vault => Receipt)) public receipts;
    mapping(address wallet => address[]) private _vaultsOf;

    event ReceiptStored(address indexed wallet, address indexed vault, uint256 paid, bytes32 indexed messageId);

    error WrongSource(uint64 selector, address sender);

    constructor(address router_, uint64 sourceSelector_, address sourceSender_) CCIPReceiver(router_) {
        require(sourceSender_ != address(0), "zero sender");
        sourceSelector = sourceSelector_;
        sourceSender = sourceSender_;
    }

    function vaultsOf(address wallet) external view returns (address[] memory) {
        return _vaultsOf[wallet];
    }

    /// @notice Total USDC (6 decimals) the wallet has been paid across every receipted campaign.
    function totalEarned(address wallet) external view returns (uint256 total) {
        address[] storage vs = _vaultsOf[wallet];
        for (uint256 i; i < vs.length; ++i) total += receipts[wallet][vs[i]].paid;
    }

    function _ccipReceive(Client.Any2EVMMessage memory m) internal override {
        address sender = abi.decode(m.sender, (address));
        if (m.sourceChainSelector != sourceSelector || sender != sourceSender) {
            revert WrongSource(m.sourceChainSelector, sender);
        }
        (address vault, address wallet, uint256 paid, uint64 ts, uint64 blk) =
            abi.decode(m.data, (address, address, uint256, uint64, uint64));
        Receipt storage r = receipts[wallet][vault];
        if (r.receivedAt == 0) _vaultsOf[wallet].push(vault);
        if (paid >= r.paid) {
            r.paid = paid;
            r.sourceTimestamp = ts;
            r.sourceBlock = blk;
            r.receivedAt = uint64(block.timestamp);
            emit ReceiptStored(wallet, vault, paid, m.messageId);
        }
    }
}
