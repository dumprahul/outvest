// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ICampaignFactory} from "../interfaces/ICampaignFactory.sol";

/// @notice Sends a creator's onchain earnings as a CCIP message to another chain.
/// @dev Permissionless and trust-free: the message is built from the vault's own state (never from the caller),
/// the vault must come from the locked factory, and the sender holds no funds and has no owner. Anyone may send
/// a receipt for any wallet and pays the CCIP fee in the native token.
contract EarningsReceiptSender {
    IRouterClient public immutable router;
    ICampaignFactory public immutable factory;
    uint256 public constant DST_GAS_LIMIT = 200_000;

    event ReceiptSent(
        bytes32 indexed messageId, uint64 indexed dstSelector, address indexed wallet, address vault, uint256 paid
    );

    error UnknownVault();
    error NotBound();
    error NoFeeSent(uint256 required);
    error RefundFailed();

    constructor(address router_, address factory_) {
        require(router_ != address(0) && factory_ != address(0), "zero address");
        router = IRouterClient(router_);
        factory = ICampaignFactory(factory_);
    }

    /// @notice Native-token fee for sending this receipt.
    function quote(uint64 dstSelector, address dstReceiver, address vault, address wallet) external view returns (uint256) {
        (Client.EVM2AnyMessage memory m,) = _build(dstReceiver, vault, wallet);
        return router.getFee(dstSelector, m);
    }

    function sendReceipt(uint64 dstSelector, address dstReceiver, address vault, address wallet)
        external
        payable
        returns (bytes32 messageId)
    {
        (Client.EVM2AnyMessage memory m, uint256 paid) = _build(dstReceiver, vault, wallet);
        uint256 fee = router.getFee(dstSelector, m);
        if (msg.value < fee) revert NoFeeSent(fee);
        messageId = router.ccipSend{value: fee}(dstSelector, m);
        emit ReceiptSent(messageId, dstSelector, wallet, vault, paid);
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            if (!ok) revert RefundFailed();
        }
    }

    function _build(address dstReceiver, address vault, address wallet)
        internal
        view
        returns (Client.EVM2AnyMessage memory m, uint256 paid)
    {
        if (!factory.isVault(vault)) revert UnknownVault();
        CampaignVault.Creator memory c = CampaignVault(vault).creatorInfo(wallet);
        if (!c.bound) revert NotBound();
        paid = c.paid;
        m = Client.EVM2AnyMessage({
            receiver: abi.encode(dstReceiver),
            data: abi.encode(vault, wallet, paid, uint64(block.timestamp), uint64(block.number)),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: DST_GAS_LIMIT, allowOutOfOrderExecution: true})
            )
        });
    }
}
