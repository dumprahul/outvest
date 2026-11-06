// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";
import {ReportReceiver} from "../ReportReceiver.sol";
import {ScheduleLib} from "../ScheduleLib.sol";

contract FactoryTest is OutVestBase {
    CampaignFactory internal fresh;

    function setUp() public override {
        super.setUp();
        fresh = new CampaignFactory(address(fwd)); // unlocked, deployed by this test contract
    }

    // ------------------------------------------------------------ construction

    function test_Constructor_SetsForwarderAndProductionReceiver() public {
        assertEq(fresh.forwarder(), address(fwd));
        assertFalse(fresh.identityLocked());
        ReportReceiver r = ReportReceiver(fresh.receiver());
        assertEq(r.forwarder(), address(fwd));
        assertEq(address(r.factory()), address(fresh));
        assertGt(fresh.receiver().code.length, 0);
    }

    function test_Constructor_RevertsOnZeroForwarder() public {
        vm.expectRevert(CampaignFactory.InvalidIdentity.selector);
        new CampaignFactory(address(0));
    }

    // ------------------------------------------------------------ lockIdentity

    function test_LockIdentity_DeployerOnlyAndStoresIdentity() public {
        vm.expectEmit(true, false, false, true, address(fresh));
        emit CampaignFactory.IdentityLocked(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        assertTrue(fresh.identityLocked());
        assertEq(fresh.workflowOwner(), wfOwner);
        assertEq(fresh.wfBind(), WF_BIND);
        assertEq(fresh.wfSnapshot(), WF_SNAP);
        assertEq(fresh.wfFinal(), WF_FINAL);
        assertEq(fresh.wfPayout(), WF_PAY);
    }

    function test_LockIdentity_RevertsForNonDeployer() public {
        vm.prank(stranger);
        vm.expectRevert(CampaignFactory.NotDeployer.selector);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        assertFalse(fresh.identityLocked());
        // not even the workflow owner or the forwarder may bootstrap
        vm.prank(wfOwner);
        vm.expectRevert(CampaignFactory.NotDeployer.selector);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        vm.prank(address(fwd));
        vm.expectRevert(CampaignFactory.NotDeployer.selector);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
    }

    function test_LockIdentity_OnlyOnce() public {
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        vm.expectRevert(CampaignFactory.IdentityAlreadyLocked.selector);
        fresh.lockIdentity(stranger, keccak256("a"), keccak256("b"), keccak256("c"), keccak256("d"));
        assertEq(fresh.workflowOwner(), wfOwner);
    }

    function test_LockIdentity_RevertsOnZeroOrDuplicateValues() public {
        bytes4 sel = CampaignFactory.InvalidIdentity.selector;
        vm.expectRevert(sel);
        fresh.lockIdentity(address(0), WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, bytes32(0), WF_SNAP, WF_FINAL, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, bytes32(0), WF_FINAL, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, bytes32(0), WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, bytes32(0));
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_BIND, WF_FINAL, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_BIND, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_BIND);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_SNAP, WF_PAY);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_SNAP);
        vm.expectRevert(sel);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_FINAL);
        assertFalse(fresh.identityLocked());
    }

    // ------------------------------------------------------------ createCampaign

    function test_CreateCampaign_ClosedUntilIdentityLocked() public {
        CampaignVault.Params memory p = _params();
        vm.expectRevert(CampaignFactory.IdentityNotLocked.selector);
        fresh.createCampaign(p);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        address v = fresh.createCampaign(p); // permissionless afterwards
        assertTrue(fresh.isVault(v));
    }

    function test_CreateCampaign_AnyoneCanCreate_RegistersAndEmits() public {
        CampaignVault.Params memory p = _params();
        bytes32 expectedHash = keccak256(
            abi.encode(
                p, receiver, address(fwd), wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY, block.chainid, address(factory)
            )
        );
        uint256 before = factory.campaignCount();
        vm.prank(stranger);
        vm.expectEmit(false, true, false, true, address(factory));
        emit CampaignFactory.CampaignCreated(address(0), brand, expectedHash);
        address v = factory.createCampaign(p);

        assertEq(factory.campaignCount(), before + 1);
        assertEq(factory.campaignAt(before), v);
        assertTrue(factory.isVault(v));
        CampaignVault cv = CampaignVault(v);
        assertEq(cv.rulesHash(), expectedHash);
        assertEq(cv.receiver(), receiver);
        assertEq(cv.factory(), address(factory));
        assertEq(cv.brand(), brand);
    }

    function test_RulesHash_DependsOnParams() public {
        CampaignVault.Params memory p = _params();
        CampaignVault a = _newVault(p);
        p.capPerCreator += 1;
        CampaignVault b = _newVault(p);
        assertNotEq(a.rulesHash(), b.rulesHash());
        assertEq(a.rulesHash(), vault.rulesHash(), "identical params => identical hash (deterministic)");
    }

    function test_RulesHash_BindsFactoryIdentity() public {
        // identical params under a different factory (different receiver/address) -> different hash
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        CampaignVault other = CampaignVault(fresh.createCampaign(_params()));
        assertNotEq(other.rulesHash(), vault.rulesHash());
    }

    function test_CreateCampaign_RevertsOnInvalidSchedule() public {
        CampaignVault.Params memory p = _params();
        p.schedule = new ScheduleLib.Segment[](0);
        vm.expectRevert(ScheduleLib.InvalidSchedule.selector);
        factory.createCampaign(p);
    }

    function test_LockIdentity_NonDeployerCheckedBeforeAlreadyLocked() public {
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        vm.prank(stranger);
        vm.expectRevert(CampaignFactory.NotDeployer.selector);
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
    }

    function _bad(CampaignVault.Params memory p) internal {
        vm.expectRevert(CampaignFactory.InvalidParams.selector);
        factory.createCampaign(p);
    }

    function test_CreateCampaign_RejectsEachInvalidParam() public {
        CampaignVault.Params memory p = _params();
        p.brand = address(0);
        _bad(p);
        p = _params();
        p.usdc = address(0);
        _bad(p);
        p = _params();
        p.bindDeadline = uint64(block.timestamp); // must be strictly in the future
        _bad(p);
        p = _params();
        p.bindDeadline = 0;
        _bad(p);
        p = _params();
        p.capPerCreator = 0;
        _bad(p);
        p = _params();
        p.capPerCreator = uint256(type(uint128).max) + 1;
        _bad(p);
        p = _params();
        p.ratePerThousand = 0;
        _bad(p);
        p = _params();
        p.ratePerThousand = uint256(type(uint128).max) + 1;
        _bad(p);
        p = _params();
        p.maxCreators = 0;
        _bad(p);
        p = _params();
        p.maxVideosPerCreator = 0;
        _bad(p);
        p = _params();
        p.maxVideosPerCreator = 11;
        _bad(p);
        p = _params();
        p.staleAfter = 1 days - 1;
        _bad(p);
        p = _params();
        p.staleAfter = 0;
        _bad(p);
        assertEq(factory.campaignCount(), 1, "only the setUp campaign exists");
    }

    function test_CreateCampaign_RejectsBucketLenOutsideRange() public {
        CampaignVault.Params memory p = _params();
        p.bucketLen = 0;
        _bad(p);
        p.bucketLen = 3599;
        _bad(p);
        p.bucketLen = uint32(7 days + 1);
        _bad(p);
        p.bucketLen = type(uint32).max;
        _bad(p);
    }

    function test_CreateCampaign_AcceptsBoundaryValues() public {
        CampaignVault.Params memory p = _params();
        p.bucketLen = 3600;
        assertTrue(factory.isVault(factory.createCampaign(p)));
        p.bucketLen = uint32(7 days);
        assertTrue(factory.isVault(factory.createCampaign(p)));
        p = _params();
        p.bindDeadline = uint64(block.timestamp + 1);
        p.staleAfter = 1 days;
        p.maxVideosPerCreator = 10;
        p.capPerCreator = type(uint128).max;
        p.ratePerThousand = type(uint128).max;
        p.maxCreators = 1;
        assertTrue(factory.isVault(factory.createCampaign(p)));
    }

    function test_CreateCampaign_InvalidVaultOnlyParamsRevertViaVaultConstructor() public {
        // deadmanTimeout == 0 and a code-less usdc are only enforced by the vault constructor
        CampaignVault.Params memory p = _params();
        p.deadmanTimeout = 0;
        _bad(p);
        p = _params();
        p.usdc = stranger;
        _bad(p);
    }

    function test_CreateCampaign_FailedCreateRegistersNothing() public {
        CampaignVault.Params memory p = _params();
        p.maxCreators = 0;
        uint256 n = factory.campaignCount();
        _bad(p);
        assertEq(factory.campaignCount(), n);
    }

    function test_CampaignCountAndAt_TrackInOrder() public {
        address v0 = address(vault); // created in setUp
        address v1 = address(_newVault(_params()));
        address v2 = address(_newVault(_params()));
        assertEq(factory.campaignCount(), 3);
        assertEq(factory.campaignAt(0), v0);
        assertEq(factory.campaignAt(1), v1);
        assertEq(factory.campaignAt(2), v2);
        vm.expectRevert();
        factory.campaignAt(3);
    }

    // ------------------------------------------------------------ emitVerifyRequest

    function test_EmitVerifyRequest_RevertsForNonVault() public {
        vm.prank(stranger);
        vm.expectRevert(CampaignFactory.Unauthorized.selector);
        factory.emitVerifyRequest(alice, VID, bytes32(uint256(1)));
        vm.expectRevert(CampaignFactory.Unauthorized.selector);
        factory.emitVerifyRequest(alice, VID, bytes32(uint256(1)));
    }

    function test_EmitVerifyRequest_VaultCanEmitViaSubmit() public {
        bytes32 ch = _request(alice, VID);
        vm.expectEmit(true, true, true, true, address(factory));
        emit CampaignFactory.VerifyRequested(address(vault), alice, VID, ch);
        vm.prank(alice);
        vault.submitForVerification();
    }

    function test_EmitVerifyRequest_VaultFromOtherFactoryRejected() public {
        // a vault registered with `fresh` is not a vault of `factory`
        fresh.lockIdentity(wfOwner, WF_BIND, WF_SNAP, WF_FINAL, WF_PAY);
        address foreign = fresh.createCampaign(_params());
        vm.prank(foreign);
        vm.expectRevert(CampaignFactory.Unauthorized.selector);
        factory.emitVerifyRequest(alice, VID, bytes32(uint256(1)));
    }
}
