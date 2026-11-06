// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {UpfrontBase} from "./OutVest.Upfront.t.sol";
import {EarningsReceiptSender} from "../ccip/EarningsReceiptSender.sol";
import {EarningsReceiptReceiver} from "../ccip/EarningsReceiptReceiver.sol";

/// @dev Stand-in for the CCIP router: fixed fee, records the last message, can deliver it to a receiver.
contract MockCcipRouter {
    uint256 public fee = 0.01 ether;
    uint64 public lastDst;
    bytes public lastReceiver;
    bytes public lastData;
    uint256 public sent;

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) { return fee; }

    function ccipSend(uint64 dst, Client.EVM2AnyMessage memory m) external payable returns (bytes32) {
        require(msg.value >= fee, "fee");
        lastDst = dst;
        lastReceiver = m.receiver;
        lastData = m.data;
        return keccak256(abi.encode(++sent));
    }

    function deliver(address receiverAddr, uint64 srcSelector, address sender, bytes memory data) external {
        Client.Any2EVMMessage memory a = Client.Any2EVMMessage({
            messageId: keccak256(data),
            sourceChainSelector: srcSelector,
            sender: abi.encode(sender),
            data: data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        EarningsReceiptReceiver(receiverAddr).ccipReceive(a);
    }
}

contract CcipReceiptTest is UpfrontBase {
    uint64 internal constant ARC = 3034092155422581607;
    uint64 internal constant DST = 10344971235874465080;
    MockCcipRouter internal routerA;
    MockCcipRouter internal routerB;
    EarningsReceiptSender internal sender;
    EarningsReceiptReceiver internal rcv;
    address internal payer = makeAddr("payer");

    function setUp() public override {
        super.setUp();
        routerA = new MockCcipRouter();
        routerB = new MockCcipRouter();
        sender = new EarningsReceiptSender(address(routerA), address(factory));
        rcv = new EarningsReceiptReceiver(address(routerB), ARC, address(sender));
        vm.deal(payer, 10 ether);
    }

    function _send() internal returns (bytes memory data) {
        vm.prank(payer);
        sender.sendReceipt{value: 0.01 ether}(DST, address(rcv), address(vault), alice);
        data = routerA.lastData();
    }

    function test_ReceiptCarriesVaultStateNotCallerInput() public {
        _bind(alice, VID, 0);
        bytes memory data = _send();
        (address v, address w, uint256 paid,,) = abi.decode(data, (address, address, uint256, uint64, uint64));
        assertEq(v, address(vault));
        assertEq(w, alice);
        assertEq(paid, UP);
        assertEq(routerA.lastDst(), DST);
        assertEq(abi.decode(routerA.lastReceiver(), (address)), address(rcv));
    }

    function test_EndToEndStoresReceipt() public {
        _bind(alice, VID, 0);
        bytes memory data = _send();
        routerB.deliver(address(rcv), ARC, address(sender), data);
        (uint256 paid,,,) = rcv.receipts(alice, address(vault));
        assertEq(paid, UP);
        assertEq(rcv.totalEarned(alice), UP);
        assertEq(rcv.vaultsOf(alice).length, 1);
    }

    function test_RevertsForUnboundCreator() public {
        vm.prank(payer);
        vm.expectRevert(EarningsReceiptSender.NotBound.selector);
        sender.sendReceipt{value: 0.01 ether}(DST, address(rcv), address(vault), alice);
    }

    function test_RevertsForUnknownVault() public {
        vm.prank(payer);
        vm.expectRevert(EarningsReceiptSender.UnknownVault.selector);
        sender.sendReceipt{value: 0.01 ether}(DST, address(rcv), address(0xBEEF), alice);
    }

    function test_RevertsWhenFeeTooLow() public {
        _bind(alice, VID, 0);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EarningsReceiptSender.NoFeeSent.selector, 0.01 ether));
        sender.sendReceipt{value: 0.001 ether}(DST, address(rcv), address(vault), alice);
    }

    function test_RefundsExcessFee() public {
        _bind(alice, VID, 0);
        uint256 before = payer.balance;
        vm.prank(payer);
        sender.sendReceipt{value: 1 ether}(DST, address(rcv), address(vault), alice);
        assertEq(before - payer.balance, 0.01 ether);
        assertEq(address(sender).balance, 0);
    }

    function test_ReceiverRejectsWrongSourceChainOrSender() public {
        _bind(alice, VID, 0);
        bytes memory data = _send();
        vm.expectRevert(abi.encodeWithSelector(EarningsReceiptReceiver.WrongSource.selector, DST, address(sender)));
        routerB.deliver(address(rcv), DST, address(sender), data);
        vm.expectRevert(abi.encodeWithSelector(EarningsReceiptReceiver.WrongSource.selector, ARC, alice));
        routerB.deliver(address(rcv), ARC, alice, data);
    }

    function test_OnlyRouterCanCallReceiver() public {
        bytes memory data = abi.encode(address(vault), alice, UP, uint64(1), uint64(1));
        Client.Any2EVMMessage memory a = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: ARC,
            sender: abi.encode(address(sender)),
            data: data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.expectRevert();
        rcv.ccipReceive(a);
    }

    function test_OlderReceiptCannotLowerRecord() public {
        _bind(alice, VID, 0);
        bytes memory older = _send();
        bytes memory newer = abi.encode(address(vault), alice, UP + 5e6, uint64(block.timestamp), uint64(block.number));
        routerB.deliver(address(rcv), ARC, address(sender), newer);
        routerB.deliver(address(rcv), ARC, address(sender), older);
        (uint256 paid,,,) = rcv.receipts(alice, address(vault));
        assertEq(paid, UP + 5e6);
        assertEq(rcv.vaultsOf(alice).length, 1);
    }
}
