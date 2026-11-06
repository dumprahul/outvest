# OutVest: changes to apply in Arc Studio

Feature: **instant settlement**. When Chainlink's `BIND` report is accepted, the vault pays the creator a fixed upfront share of their cap in the same transaction. The rest follows the early-release schedule.

Only **two contract files** change: `CampaignVault.sol` and `CampaignFactory.sol`. `ScheduleLib.sol`, `ReportReceiver.sol` and `interfaces/*` are untouched. Existing tests need no edits (new fields default to 0).

Tested here: 218 tests pass (206 original + 12 new), compiled with solc 0.8.27. Rebuild with your pinned 0.8.28 after pasting.

---

## 1. `contracts/CampaignVault.sol` (8 edits)

**1.1 New constant**, after `VERIFY_COOLDOWN`:
```solidity
    uint256 public constant VERIFY_COOLDOWN = 10 minutes;
    /// @notice Upper bound on the instant payout released when a creator's first video is bound (10% of the cap).
    uint32 public constant MAX_UPFRONT_PPM = 100_000;
```

**1.2 `Params` struct**: add `upfrontPpm` after `minPayout`, before `schedule` (field order matters for ABI encoding):
```solidity
        uint256 minPayout;
        uint32 upfrontPpm;
        ScheduleLib.Segment[] schedule;
```

**1.3 `Creator` struct**: add `upfront` after `creditedViews`, before `videoIds`:
```solidity
        uint128 creditedViews;
        uint128 upfront;
        bytes32[10] videoIds;
```

**1.4 New immutable**, after `minPayout`:
```solidity
    uint256 public immutable minPayout;
    uint32 public immutable upfrontPpm;
    uint256 public immutable scheduleLength;
```

**1.5 Constructor validation**: extend the last line of the `if`:
```solidity
            || p.staleAfter < 1 days || p.deadmanTimeout == 0 || p.upfrontPpm > MAX_UPFRONT_PPM) revert InvalidParams();
```

**1.6 Constructor assignment**, after `minPayout = p.minPayout;`:
```solidity
        minPayout = p.minPayout;
        upfrontPpm = p.upfrontPpm;
        scheduleLength = p.schedule[p.schedule.length - 1].start;
```

**1.7 `applyBind`**, two edits.

(a) Inside `if (!c.bound) { ... }`, right after `c.remaining = uint128(capPerCreator);`:
```solidity
            c.remaining = uint128(capPerCreator);
            c.upfront = uint128(capPerCreator * upfrontPpm / PPM);
            liability += capPerCreator;
```
(b) At the end, between `emit Bound(...)` and `return bytes32(0);`:
```solidity
        emit Bound(wallet, videoId, baselineViews, c.boundAt);
        // Instant settlement: the upfront share is paid in this same transaction, on the creator's first video only.
        // If the transfer fails the state is restored and the amount stays claimable through `claim`.
        if (c.upfront != 0 && c.videoCount == 1) _pay(wallet, false);
        return bytes32(0);
```

**1.8 `claimable`**: replace the whole function body:
```solidity
    function claimable(address wallet) public view returns (uint256) {
        Creator storage c = _creator[wallet];
        if (!c.bound) return 0;
        // The upfront share is always entitled; view-based entitlement only counts while snapshots are fresh.
        uint256 entitled = c.upfront;
        if (finalized || block.timestamp <= uint256(lastSnapshotTs) + staleAfter) {
            uint256 fraction = finalized ? PPM : ScheduleLib.fractionPpm(_schedule, block.timestamp - c.boundAt);
            uint256 viewBased = _earned(c) * fraction / PPM;
            if (viewBased > entitled) entitled = viewBased;
        }
        if (entitled <= c.paid) return 0;
        uint256 amount = entitled - c.paid;
        return amount > c.remaining ? c.remaining : amount;
    }
```
(Before: it returned 0 whenever snapshots were stale, and the upfront floor did not exist.)

---

## 2. `contracts/CampaignFactory.sol` (1 edit)

In `createCampaign`, extend the validation `if`:
```solidity
            || params.bucketLen < 1 hours || params.bucketLen > 7 days || params.staleAfter < 1 days
            || params.upfrontPpm > 100_000) {
            revert InvalidParams();
        }
```
No other change: the rule hash uses `abi.encode(params, ...)`, so `upfrontPpm` is included automatically.

---

## 3. What this changes at runtime

- `applyBind` now **moves money**: first video of a creator, `upfront = cap x upfrontPpm / 1e6`, paid to the bound wallet. A second video pays nothing extra.
- The upfront amount counts toward the creator's entitlement: `entitled = max(upfront, earned x schedule)`, minus `paid`. No double payment, never above the cap.
- If the transfer fails (for example a blocked wallet), state is restored, the creator stays bound, and `claim` pays it later. It works even with stale snapshots.
- `upfrontPpm = 0` behaves exactly like before.
- Solvency is unchanged: the full cap is still reserved at bind, and paying upfront lowers balance and liability equally.

---

## 4. `createCampaign` argument order (for the frontend and Circle calls)

```
(brand, usdc, bindDeadline, ratePerThousand, capPerCreator, maxCreators,
 maxVideosPerCreator, bucketLen, maxGrowthPerDay, staleAfter, deadmanTimeout,
 minPayout, upfrontPpm, schedule[])
```
`schedule` is a list of `(start, startPpm, endPpm)`. `creatorInfo(wallet)` now also returns `upfront`, between `creditedViews` and `videoIds`.

Recommended demo values:

| Field | Value | Meaning |
|---|---|---|
| `upfrontPpm` | `100000` | 10% of cap paid instantly (30 USDC on a 300 USDC cap) |
| `bucketLen` | `3600` | 1-hour buckets, about a 7-hour lag window |
| `schedule` | `(0,250000,500000) (2592000,500000,800000) (5184000,800000,1000000) (7776000,1000000,1000000)` | 25% at day 0, 50% at day 30, 80% at day 60, 100% at day 90 |

---

## 5. Deploy order (in Arc Studio, from your own wallet)

If an older factory is already deployed, **redeploy**: everything is immutable, so the new factory has a new receiver address.

1. Deploy `CampaignFactory(forwarder)`. Use the production forwarder `0x76c9cf548b4179F8901cda1f8623568b58215E62`. The mock forwarder lets anyone forge reports, so use it only for throwaway runs.
2. Read `factory.receiver()` and point the Chainlink workflows at it.
3. Deploy the workflows and collect the 4 workflow IDs.
4. Call `lockIdentity(owner, bindId, snapshotId, finalId, payoutId)` once, from the deploying wallet. It cannot be undone.
5. Call `createCampaign(...)` with the values above, then approve and `fund` the vault in USDC (`0x3600000000000000000000000000000000000000`, 6 decimals).

---

## 6. Optional: tests for the new behavior

Paste as `contracts/test/OutVest.Upfront.t.sol` (the full file in the project has 12 tests; this is the core set):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OutVestBase} from "./OutVest.Base.t.sol";
import {CampaignVault} from "../CampaignVault.sol";
import {CampaignFactory} from "../CampaignFactory.sol";

contract UpfrontTest is OutVestBase {
    uint256 internal constant UPFRONT = 30e6; // 10% of 300e6 cap
    CampaignVault internal uv;

    function setUp() public override {
        super.setUp();
        CampaignVault.Params memory p = _params();
        p.upfrontPpm = 100_000;
        uv = _newVault(p);
        _fundVault(uv, 1_000e6);
    }

    function _bindU(address w, bytes32 vid, uint64 baseline) internal {
        vm.prank(w);
        bytes32 ch = uv.requestBinding(vid);
        _sendTo(uv, 1, _bindPayload(w, vid, ch, baseline));
    }

    function test_Upfront_PaidInSameTxAsBind() public {
        _bindU(alice, VID, 1_000);
        assertEq(usdc.balanceOf(alice), UPFRONT);
        assertEq(uv.creatorInfo(alice).paid, UPFRONT);
        assertEq(uv.liability(), 300e6 - UPFRONT);
    }

    function test_Upfront_OnlyOnFirstVideo() public {
        _bindU(alice, VID, 0);
        _bindU(alice, VID2, 0);
        assertEq(usdc.balanceOf(alice), UPFRONT);
    }

    function test_Upfront_FailedTransferFallsBackToClaim() public {
        usdc.setBlocked(alice, true);
        _bindU(alice, VID, 0);
        assertTrue(uv.creatorInfo(alice).bound);
        usdc.setBlocked(alice, false);
        vm.warp(block.timestamp + 30 days); // snapshots stale
        assertEq(uv.claimable(alice), UPFRONT);
        uv.claim(alice);
        assertEq(usdc.balanceOf(alice), UPFRONT);
    }

    function test_Upfront_RejectsAboveTenPercent() public {
        CampaignVault.Params memory p = _params();
        p.upfrontPpm = 100_001;
        vm.expectRevert(CampaignFactory.InvalidParams.selector);
        factory.createCampaign(p);
    }
}
```

Not changed, still open: the optional `maxGrowthPerDay > 0` check (some existing tests set it to 0), and the three workflow risks from the earlier review (report ordering, spam vaults, baseline views).
