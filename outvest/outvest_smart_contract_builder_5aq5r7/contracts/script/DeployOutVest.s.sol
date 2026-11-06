// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CampaignFactory} from "../CampaignFactory.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {ScheduleLib} from "../ScheduleLib.sol";

/// @notice Arc Testnet deployment for OutVest. The broadcaster becomes the factory deployer, the only
/// address that can call `lockIdentity`, so this must run from your own wallet (never via a CREATE2 helper).
///
/// Required env:  PRIVATE_KEY (testnet-only key)
/// Optional env:
///   FACTORY            existing factory to attach to (skips deploying)
///   FORWARDER          default: Arc Testnet production forwarder (ignored when FACTORY is set)
///   LOCK_IDENTITY      true to lock the workflow identity (irreversible)
///     WF_OWNER, WF_BIND, WF_SNAPSHOT, WF_FINAL, WF_PAYOUT   required when LOCK_IDENTITY=true
///   CREATE_CAMPAIGN    true to create a campaign with the default schedule
///     BRAND (default: broadcaster), USDC (default: Arc Testnet USDC), BIND_DEADLINE (unix, default: now + 30 days),
///     RATE_PER_THOUSAND (token units, default 2e6), CAP_PER_CREATOR (default 300e6), MAX_CREATORS (10),
///     MAX_VIDEOS_PER_CREATOR (3), BUCKET_LEN (3600), MAX_GROWTH_PER_DAY (views, 200000),
///     STALE_AFTER (seconds, 3 days), DEADMAN_TIMEOUT (seconds, 30 days), MIN_PAYOUT (token units, 1e6),
///     UPFRONT_PPM (default 100000 = 10% of cap paid when a creator's first video binds; max 100000),
///     CLASSIC_SCHEDULE (true = 0/20%/50%/80%/100% schedule; default is the demo schedule
///     25% at day 0, 50% at day 30, 80% at day 60, 100% at day 90)
contract DeployOutVest is Script {
    uint256 internal constant ARC_TESTNET_CHAIN_ID = 5042002;
    address internal constant ARC_TESTNET_USDC = 0x3600000000000000000000000000000000000000;
    address internal constant ARC_TESTNET_FORWARDER = 0x76c9cf548b4179F8901cda1f8623568b58215E62;
    address internal constant ARC_TESTNET_MOCK_FORWARDER = 0x6E9EE680ef59ef64Aa8C7371279c27E496b5eDc1;

    function run() external returns (CampaignFactory factory, address vault) {
        require(block.chainid == ARC_TESTNET_CHAIN_ID, "DeployOutVest: not Arc Testnet (5042002)");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        address existing = vm.envOr("FACTORY", address(0));
        if (existing == address(0)) {
            address forwarder = vm.envOr("FORWARDER", ARC_TESTNET_FORWARDER);
            if (forwarder == ARC_TESTNET_MOCK_FORWARDER) {
                console.log("WARNING: mock forwarder. Anyone may be able to forge reports. Throwaway use only.");
            }
            factory = new CampaignFactory(forwarder);
        } else {
            factory = CampaignFactory(existing);
        }

        if (vm.envOr("LOCK_IDENTITY", false) && !factory.identityLocked()) {
            factory.lockIdentity(
                vm.envAddress("WF_OWNER"),
                vm.envBytes32("WF_BIND"),
                vm.envBytes32("WF_SNAPSHOT"),
                vm.envBytes32("WF_FINAL"),
                vm.envBytes32("WF_PAYOUT")
            );
        }

        if (vm.envOr("CREATE_CAMPAIGN", false)) {
            vault = factory.createCampaign(_params(deployer));
        }

        vm.stopBroadcast();

        console.log("deployer          :", deployer);
        console.log("factory           :", address(factory));
        console.log("receiver          :", factory.receiver());
        console.log("forwarder         :", factory.forwarder());
        console.log("identityLocked    :", factory.identityLocked());
        console.log("vault (if created):", vault);
    }

    function _params(address deployer) internal view returns (CampaignVault.Params memory p) {
        p.brand = vm.envOr("BRAND", deployer);
        p.usdc = vm.envOr("USDC", ARC_TESTNET_USDC);
        p.bindDeadline = uint64(vm.envOr("BIND_DEADLINE", block.timestamp + 30 days));
        p.ratePerThousand = vm.envOr("RATE_PER_THOUSAND", uint256(2e6));
        p.capPerCreator = vm.envOr("CAP_PER_CREATOR", uint256(300e6));
        p.maxCreators = uint32(vm.envOr("MAX_CREATORS", uint256(10)));
        p.maxVideosPerCreator = uint8(vm.envOr("MAX_VIDEOS_PER_CREATOR", uint256(3)));
        p.bucketLen = uint32(vm.envOr("BUCKET_LEN", uint256(1 hours)));
        p.maxGrowthPerDay = uint64(vm.envOr("MAX_GROWTH_PER_DAY", uint256(200_000)));
        p.staleAfter = uint64(vm.envOr("STALE_AFTER", uint256(3 days)));
        p.deadmanTimeout = uint64(vm.envOr("DEADMAN_TIMEOUT", uint256(30 days)));
        p.minPayout = vm.envOr("MIN_PAYOUT", uint256(1e6));
        p.upfrontPpm = uint32(vm.envOr("UPFRONT_PPM", uint256(100_000)));
        if (vm.envOr("CLASSIC_SCHEDULE", false)) {
            p.schedule = ScheduleLib.defaultSchedule();
        } else {
            // Demo schedule: 25% at day 0 rising to 50% by day 30, 80% by day 60, 100% at day 90.
            p.schedule = new ScheduleLib.Segment[](4);
            p.schedule[0] = ScheduleLib.Segment(0, 250_000, 500_000);
            p.schedule[1] = ScheduleLib.Segment(30 days, 500_000, 800_000);
            p.schedule[2] = ScheduleLib.Segment(60 days, 800_000, 1_000_000);
            p.schedule[3] = ScheduleLib.Segment(90 days, 1_000_000, 1_000_000);
        }
    }
}
