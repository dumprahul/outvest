# OutVest final check (Part 1 + Part 2)

Verdict: **READY for Arc Testnet** after two small fixes made during this check. Open items are the K assumptions below, not code.

Line numbers refer to the current files in `contracts/`. V = CampaignVault.sol, R = ReportReceiver.sol, F = CampaignFactory.sol, S = ScheduleLib.sol.

## Fixes made during this check

1. **Challenge reuse (E2/E5).** Binding cleared the whole pending entry, which reset the nonce to 0, so an old challenge for the same wallet and video could be issued again. The nonce is now kept when the pending request is cleared (V:228-232).
2. **Skipped entries were silent (F6).** Unknown videos and stale-timestamp observations are now reported with a new `EntrySkipped(videoId, reason)` event, using the `UNKNOWN_VIDEO` and `STALE_TS` reasons (V:120, V:338-347).
3. **Missing fuzz properties (J9).** Added `invariant_OnlyReceiverReachesApply` and `invariant_ReplayedReportsRejected`, plus 15 unit tests for the two fixes.

## A. No privilege

| ID | Result | Evidence |
|---|---|---|
| A1 | PASS | Grep over `contracts/` finds no `Ownable`, `AccessControl`, `Pausable`, `Proxy`, `delegatecall`, `selfdestruct`, `assembly` or `unchecked`. The only `decimals()` is in `test/MockUSDC.sol`. |
| A2 | PASS | The only outflows are `_transfer(wallet, …)` in `_pay` (V:390-407), which pays only when `claimable(wallet) > 0` and that needs `bound`, and `_transfer(brand, …)` in `sweep` (V:290-296). Reports carry no amounts or destinations. |
| A3 | PASS | All params are `immutable` and set in the constructor (V:132-162). `_schedule` is written only in the constructor. |
| A4 | PASS | `sweep` reverts `TooEarly` before `bindDeadline` (V:291) and sends `balance - liability` only (V:292-294). |
| A5 | PASS | F:40-54 enforces deployer-only (`NotDeployer`), once (`IdentityAlreadyLocked`), and nonzero owner and ids. `createCampaign` reverts `IdentityNotLocked` (F:57). |

## B. Factory

| ID | Result | Evidence |
|---|---|---|
| B1 | PASS | F:37 `new ReportReceiver(forwarder_, address(this))`. |
| B2 | PASS | F:57-65 covers every listed rule. `deadmanTimeout > 0` and a USDC address with code are enforced by the vault constructor (V:134-140), whose error surfaces through the factory. |
| B3 | PASS | F:66-67 builds the hash from the exact fields. The vault stores it as `immutable rulesHash` (V:72). It is emitted in `CampaignCreated` (F:71). |
| B4 | PASS | F:69-70, F:79-80. |
| B5 | PASS | F:74-77 emits `VerifyRequested(msg.sender, …)` and reverts `Unauthorized` for non-vaults. |

## C. ScheduleLib

| ID | Result | Evidence |
|---|---|---|
| C1 | PASS | S:19-40. The 250000 cap applies to every segment up to and including the one before the first upward jump. |
| C2 | PASS | S:42-53. The last segment returns `startPpm`, and interpolation multiplies before it divides. |
| C3 | PASS | `test_Fraction_SpecTable` and `test_Fraction_DefaultKnownPoints` cover 3d, 7d, 18.5d, 20d, 30d, 45d, 60d and 90d. |

## D. Receiver

| ID | Result | Evidence |
|---|---|---|
| D1 | PASS | R:12 `IReceiver, ERC165, ReentrancyGuard`. No owner, no setters. |
| D2 | PASS | R:54-63: forwarder, then owner (R:56), decode, workflow (R:60), `isVault`, replay revert, then seq/ts. |
| D3 | PASS | R:87-88 reads bytes 0-32 and 42-62 and never reads the name. `test_WorkflowNameIsNotPinned` covers it. |
| D4 | PASS | R:58 decodes the envelope. `_validatePayload` (R:112-144) and `_route` (R:96-109) enforce the payloads. |
| D5 | PARTIAL | R:66-74 gives soft `STALE_SEQ`, `FUTURE_TS` and `STALE_TS` (skew and age constants at R:15-16). The receiver also hard-reverts on `UnknownReportType` (R:59), `InvalidMetadata` (R:86) and a malformed envelope. These extras are not in your hard-revert list, but they are auth or format failures and look safer. I kept them. |
| D6 | PASS | R:19-20, R:75-76, R:79. `test_SeqGapsAllowed` and `test_SeqIsPerVaultAndPerType` cover it. |
| D7 | PASS | `_checkMetadata` (R:84-94) reverts `WrongWorkflow`. `test_ClaimReportFromSnapshotWorkflowRejected` covers it. |

## E. Funding and binding

| ID | Result | Evidence |
|---|---|---|
| E1 | PASS | V:164-171, `nonReentrant`, reverts after finalize, uses `safeTransferFrom`. |
| E2 | PASS | V:173-187 checks the deadline, the id charset (V:426-436), unowned video, video count, and nonce increment with overwrite. The challenge matches the spec. |
| E3 | PASS | V:189-196 needs a pending request, checks the deadline, applies the 10-minute cooldown, and calls the factory. The cooldown survives re-requests. |
| E4 | PASS | V:199-235: `onlyReceiver`, `DEADLINE` (V:202), `NO_MATCH` (V:204), `VIDEO_TAKEN` (V:205), `MAX_VIDEOS` (V:207), `FULL` (V:209), `BUDGET` (V:210). A new creator gets `boundAt`, `remaining = cap`, and liability is raised. |
| E5 | PASS | A second video leaves `boundAt` and liability alone. The pending entry is cleared and the nonce is kept (V:228-232). `videoOwner` is set. |
| E6 | PASS | The bind epoch bucket is set to the baseline (V:224-228). `test_ApplyBind_StoresBaselineInBindEpochBucket` covers it. |

## F. View accounting

| ID | Result | Evidence |
|---|---|---|
| F1 | PASS | V:356-366. |
| F2 | PASS | V:367-374 ignores empty and expired slots and skips the update if none is valid. |
| F3 | PASS | V:375. |
| F4 | PASS | V:376-381. Decreases apply at once and increases are limited to `credited + allowance`. |
| F5 | PASS | V:382-383. |
| F6 | PASS | V:338-347 skips unknown and stale entries and now emits `EntrySkipped`. Missing videos are untouched. |
| F7 | PASS | V:332-352 handles length mismatch and the 50-entry cap, and `lastSnapshotTs` only moves forward. |

## G. Payment

| ID | Result | Evidence |
|---|---|---|
| G1 | PASS | V:299-307. A creator with `remaining == 0` gets 0 because the result is capped by `remaining`. |
| G2 | PASS | V:385-388 and V:299-307, with uint256 intermediates, multiply first, floor. |
| G3 | PASS | V:264 and `test_Claim_PaysBoundWalletEvenIfCalledByAnotherAddress`. |
| G4 | PASS | V:255-261, V:390-393. |
| G5 | PASS | V:390-407. State is changed before the call and fully restored on failure with `PayoutFailed`, and the batch continues. |
| G6 | PASS | `claimable` reads `creditedViews` and never loops. |
| G7 | PASS | `test_WorkedExample` asserts exactly 11,304,300 / 100e6 / 224e6 / 300e6 cumulative. |

## H. Finalize, settle, sweep

| ID | Result | Evidence |
|---|---|---|
| H1 | PASS | V:244-252 requires `bindDeadline + scheduleLength`. |
| H2 | PASS | V:268-271. |
| H3 | PASS | Both paths use `_finalize(bool)` (V:420-424), which sets `finalizedAt` and emits `Finalized(at, deadman)`. |
| H4 | PASS | V:274-287. |
| H5 | PASS | V:290-296. A zero surplus is a no-op, and it can be called repeatedly. |
| H6 | PASS | `invariant_BalanceCoversLiability` and `invariant_LiabilityEqualsSumOfRemaining` pass. |

## I. Security

| ID | Result | Evidence |
|---|---|---|
| I1 | PASS | `nonReentrant` on `fund`, `claim`, `applyPayout`, `settle` and `sweep`. |
| I2 | PASS | `onlyReceiver` reverts `NotReceiver` (V:127-130). |
| I3 | PASS | Payloads hold addresses to try and observations only. |
| I4 | PASS | Loops are bounded by constants 50, 25, 10, 8 and 7. |
| I5 | PASS | All 14 events exist. |
| I6 | PASS | `pragma ^0.8.24`, no `unchecked`. |
| I7 | PASS | `contracts/test/TestReportReceiver.sol` is test-only, and nothing in `contracts/script/` or `scripts/` references it. |

## J. Tests

| ID | Result | Evidence |
|---|---|---|
| J1 | PASS | `test_Rejects_*` in `OutVest.Schedule.t.sol`, one per rule. |
| J2 | PASS | `test_Fraction_SpecTable`. |
| J3 | PASS | `test_WorkedExample`. |
| J4 | PASS | `OutVest.Buckets.t.sol`, plus `test_Snapshot_OldTimestampSkippedPerVideo` for backwards timestamps. |
| J5 | PASS | `OutVest.Apply.t.sol` covers each bind failure, including two creators racing one video. |
| J6 | PASS | `OutVest.VaultPayout.t.sol` and `OutVest.Settle.t.sol`. |
| J7 | PASS | `OutVest.Settle.t.sol`. |
| J8 | PASS | `OutVest.Receiver.t.sol`. |
| J9 | PASS | `OutVest.Invariant.t.sol` has eight invariants, including the two added in this check. |

## K. Assumptions

| ID | Status | Finding |
|---|---|---|
| K1 | PARTIAL | Verified onchain: `0x3600000000000000000000000000000000000000` has 6 decimals and symbol USDC. **UNVERIFIED:** its transfer return value, blocklist behaviour and any fee-on-transfer behaviour. The contracts tolerate both a revert and a `false` return. |
| K2 | VERIFIED (official docs) | The transaction succeeds even when `onReport` reverts, and the workflow sees `receiverContractExecutionStatus = REVERTED`. Hard reverts such as `Replay` and `WrongWorkflow` therefore show up only in the workflow, so it must check that status and not retry blindly. |
| K3 | VERIFIED (official directory) | Arc Testnet production forwarder is `0x76c9cf548b4179F8901cda1f8623568b58215E62`. The mock forwarder is `0x6E9EE680ef59ef64Aa8C7371279c27E496b5eDc1`. **UNVERIFIED, one secondary source:** the mock forwarder checks no signatures and anyone can call it. If a factory is deployed with the mock, anyone could forge the workflow metadata, so use the mock only for throwaway testnet runs. |
| K4 | UNVERIFIED | Arc Testnet is listed. Arc mainnet is not in the forwarder directory I read, so mainnet support is not confirmed. |

## (a) FAIL / PARTIAL

- **D5 (PARTIAL):** extra hard reverts for unknown report type, short metadata and a malformed envelope.
- **K1, K4 (PARTIAL / UNVERIFIED):** token behaviour and Arc mainnet support.

## (b) Build and test results

- `forge build --force`: success, exit 0 (lint warnings only).
- `forge test -vv --match-path 'contracts/test/OutVest.*t.sol'`: **213 passed, 0 failed, 0 skipped** across 13 suites. All 8 invariants pass (64 runs, depth 80).

## (d) Extras and deviations

No privileged function was found. The one deployer-gated function is `lockIdentity` (one-time, as specified). Deviations, all on the safer side:

- `lockIdentity` also requires the four workflow ids to be different from each other.
- Metadata is accepted when it is at least 62 bytes, because real forwarders append a 2-byte report id.
- `fund` reverts `UnsupportedToken` if the vault's balance doesn't rise by exactly the amount, which rejects fee-on-transfer tokens.
- A failed `sweep` transfer to a blocked brand emits `PayoutFailed` instead of reverting.
- The new `EntrySkipped` event.

Design points that follow your spec and are worth knowing:

- A FINAL report carries at most 50 videos and finalizes the whole campaign.
- The first 7 days after a bind earn nothing from that video, because the bind bucket stays in the rolling minimum.
- Identical campaign params give identical `rulesHash` values.
- The `MAX_VIDEOS` soft reject in `applyBind` can't be reached through normal calls, because `requestBinding` already enforces the limit.
- A report timestamp up to 15 minutes in the future can move `lastSnapshotTs` ahead of the block time.
