# OutVest on Arc Testnet: deployment record and next steps

Network: Arc Testnet, chain id 5042002, RPC `https://rpc.testnet.arc.io`, explorer `https://explorer.testnet.arc.io`.
USDC (also the gas token): `0x3600000000000000000000000000000000000000`, 6 decimals.

## 1. What is deployed

| Item | Value |
|---|---|
| Factory (`CampaignFactory`) | `0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4` |
| Receiver (`ReportReceiver`, created by the factory) | `0x6818EFf02e79adDB7cB43bb68600a64c4C5b9C2b` |
| Forwarder (Chainlink CRE, Arc Testnet production) | `0x76c9cf548b4179F8901cda1f8623568b58215E62` |
| Deployer wallet (the only address that can lock the identity) | `0x0612D26676869aFcF8BCfdcC55Bd62a307fBF4b5` |
| Deploy transaction | `0xa8f8de1ceeb2fdf5a7ee2a7c4d977034ca60079ddcfd82c3c13d7a6e6173a733` |
| Block | 71067583 |
| Gas paid | 0.1516842 USDC (6,067,368 gas) |
| Identity locked | **No** (verified onchain) |
| Campaigns / vaults | None yet (`vault` printed as the zero address, as expected) |

The first script run only deploys the factory. It does not lock the identity and does not create a campaign. Nothing else has been sent.

## 2. What is still open

1. Build and deploy the four Chainlink workflows (bind, snapshot, final, payout). Each writes to the receiver address above.
2. Lock the identity (once, irreversible).
3. Create a campaign.
4. Fund the vault.
5. Run the campaign and settle it.

## 3. What you need from Chainlink before locking

| Variable | What it is |
|---|---|
| `WF_OWNER` | The wallet address that owns your workflows (the account you deploy them from). |
| `WF_BIND` | Id of the workflow that sends BIND reports (report type 1). |
| `WF_SNAPSHOT` | Id of the workflow that sends SNAPSHOT reports (type 2). |
| `WF_FINAL` | Id of the workflow that sends FINAL reports (type 3). |
| `WF_PAYOUT` | Id of the workflow that sends CLAIM/payout reports (type 4). |

- Each id is 32 bytes written as `0x` plus 64 hex characters. Chainlink prints it when you deploy the workflow, and `cre workflow hash` prints it too. Copy it from the deployed workflow.
- The four ids must all be different and nonzero, and the owner must be nonzero. The factory reverts otherwise.
- Locking cannot be undone. If you lock a wrong id, deploy a new factory and start again from step 1 of section 4. The old factory stays on chain and can be ignored.
- Each report type is only accepted from its own workflow. A snapshot workflow cannot send a payout report.

## 4. Commands to finish the deployment

Run these in the Code panel terminal. Your `PRIVATE_KEY` must be in `.env` and must be the deployer wallet above, because only that wallet can lock the identity.

### 4.1 Check the starting state

```
cast call 0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 "identityLocked()(bool)" --rpc-url https://rpc.testnet.arc.io
cast call 0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 "receiver()(address)" --rpc-url https://rpc.testnet.arc.io
```
Expected: `false`, and the receiver address from the table.

### 4.2 Lock the identity

```
FACTORY=0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 LOCK_IDENTITY=true \
WF_OWNER=0x<workflow owner address> \
WF_BIND=0x<64 hex chars> \
WF_SNAPSHOT=0x<64 hex chars> \
WF_FINAL=0x<64 hex chars> \
WF_PAYOUT=0x<64 hex chars> \
forge script contracts/script/DeployOutVest.s.sol:DeployOutVest \
  --rpc-url https://rpc.testnet.arc.io --broadcast
```
Then confirm:
```
cast call 0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 "identityLocked()(bool)" --rpc-url https://rpc.testnet.arc.io
cast call 0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 "workflowOwner()(address)" --rpc-url https://rpc.testnet.arc.io
```
Expected: `true`, and your owner address. You can also read `wfBind()`, `wfSnapshot()`, `wfFinal()` and `wfPayout()` the same way and compare them with your workflow ids.

### 4.3 Create a campaign

Anyone can do this once the identity is locked. The brand (the address that receives swept leftovers) defaults to the broadcasting wallet.

```
FACTORY=0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 CREATE_CAMPAIGN=true \
forge script contracts/script/DeployOutVest.s.sol:DeployOutVest \
  --rpc-url https://rpc.testnet.arc.io --broadcast
```
The script prints `vault (if created): 0x...`. Save it.

Defaults for the campaign:

| Setting | Default | Variable |
|---|---|---|
| Brand | broadcasting wallet | `BRAND` |
| Pay rate | 2 USDC per 1,000 credited views | `RATE_PER_THOUSAND` (token units, `2000000`) |
| Cap per creator | 300 USDC | `CAP_PER_CREATOR` (`300000000`) |
| Max creators | 10 | `MAX_CREATORS` |
| Max videos per creator | 3 | `MAX_VIDEOS_PER_CREATOR` |
| Binding window | 30 days from creation | `BIND_DEADLINE` (unix seconds) |
| Bucket length | 3,600 s (1 hour) | `BUCKET_LEN` |
| Max view growth per day, per video | 200,000 | `MAX_GROWTH_PER_DAY` |
| Stale-snapshot limit | 3 days | `STALE_AFTER` (seconds) |
| Dead-man timeout | 30 days | `DEADMAN_TIMEOUT` (seconds) |
| Minimum batch payout | 1 USDC | `MIN_PAYOUT` (`1000000`) |
| Upfront at bind | 10% of cap (30 USDC on a 300 cap) | `UPFRONT_PPM` (`100000`, max `100000`) |
| Schedule | 25% at day 0, 50% at day 30, 80% at day 60, 100% at day 90 | `CLASSIC_SCHEDULE=true` switches to 0% / 20% / 50% / 80% / 100% |

Smaller test campaign (needs only 100 USDC of funding): add `CAP_PER_CREATOR=20000000 MAX_CREATORS=5` to the command.

You can run 4.2 and 4.3 together by putting `LOCK_IDENTITY=true`, the `WF_*` values and `CREATE_CAMPAIGN=true` in one command.

### 4.4 Fund the vault

Each creator who binds reserves their full cap in the vault. The vault only accepts a bind while its USDC balance covers the cap on top of what is already reserved, so fund before creators bind. Funding needed: `cap x max creators` (3,000 USDC for the defaults, 100 USDC for the smaller test above).

```
cast send 0x3600000000000000000000000000000000000000 "approve(address,uint256)" <vault> <amount in units> \
  --rpc-url https://rpc.testnet.arc.io --private-key $PRIVATE_KEY
cast send <vault> "fund(uint256)" <amount in units> \
  --rpc-url https://rpc.testnet.arc.io --private-key $PRIVATE_KEY
```
USDC has 6 decimals, so 100 USDC is `100000000`. Anyone can fund a vault. Funds can only leave to creators or the brand.

### 4.5 Check the campaign

```
cast call <vault> "upfrontPpm()(uint32)"   --rpc-url https://rpc.testnet.arc.io
cast call <vault> "liability()(uint256)"   --rpc-url https://rpc.testnet.arc.io
cast call <vault> "bindDeadline()(uint64)" --rpc-url https://rpc.testnet.arc.io
cast call 0x3600000000000000000000000000000000000000 "balanceOf(address)(uint256)" <vault> --rpc-url https://rpc.testnet.arc.io
cast call 0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4 "campaignCount()(uint256)" --rpc-url https://rpc.testnet.arc.io
```

## 5. How the Chainlink workflows must talk to the contracts

### 5.1 Where reports go
Write every report to the **receiver** `0x6818EFf02e79adDB7cB43bb68600a64c4C5b9C2b`. The forwarder `0x76c9cf548b4179F8901cda1f8623568b58215E62` is the only address that can call it. Chainlink delivers `onReport(metadata, report)`.

### 5.2 Metadata (set by Chainlink)
`workflowId (bytes32) | workflowName (bytes10) | workflowOwner (address)`, plus a trailing 2-byte report id that the receiver ignores. The receiver checks the owner and the workflow id for the report type. The workflow name is not checked.

### 5.3 Report body
`abi.encode(uint8 rtype, address vault, uint64 seq, uint64 ts, bytes payload)`

| `rtype` | Name | Must come from | Payload |
|---|---|---|---|
| 1 | BIND | `WF_BIND` | `abi.encode(address wallet, bytes32 videoId, bytes32 challenge, uint64 baselineViews)` |
| 2 | SNAPSHOT | `WF_SNAPSHOT` | `abi.encode(bytes32[] ids, uint64[] views)`, at most 50 entries |
| 3 | FINAL | `WF_FINAL` | same as SNAPSHOT, at most 50 entries |
| 4 | CLAIM | `WF_PAYOUT` | `abi.encode(address[] wallets)`, at most 25 wallets |

- `videoId` is the 11-character YouTube id as ASCII, left-aligned in the 32 bytes, with the remaining 21 bytes zero.
- `challenge` is the value the creator received from `requestBinding` (also in the `BindingRequested` and `VerifyRequested` events). The workflow confirms it appears on the YouTube video, then reports the current view count as `baselineViews`.
- A report never carries an amount or a destination. The vault computes what each creator is owed.

### 5.4 Rules the workflows must follow

- `seq` must be strictly greater than the last accepted one for the same vault and report type. Gaps are fine.
- `ts` must not be more than 15 minutes in the future or more than 3 days old, and must not be earlier than the last accepted `ts` for that vault and type.
- An identical report (same bytes) sent twice reverts. A rejected report still counts as used, so send a new one with a new `seq`.
- Soft rejects do not revert. The receiver emits `ReportRejected(vault, rtype, reason)` and the transaction succeeds. Reasons: `DEADLINE`, `NO_MATCH`, `VIDEO_TAKEN`, `FULL`, `BUDGET`, `MAX_VIDEOS`, `STALE_SEQ`, `STALE_TS`, `FUTURE_TS`, `FINALIZED`, `FINAL_TOO_EARLY`, `BATCH_TOO_LARGE`, `LENGTH_MISMATCH`, `MALFORMED_PAYLOAD`.
- Hard reverts (wrong forwarder, wrong owner, wrong workflow id, unknown vault, replay, unknown report type, short metadata, undecodable bytes) do not fail the Chainlink transaction. Chainlink reports the receiver status as `REVERTED`. Check `receiverContractExecutionStatus` after every write, and watch `ReportRejected` and `ReportAccepted` events.
- Unknown videos and videos whose `ts` is older than the last update are skipped, with an `EntrySkipped` event. Videos missing from a snapshot are not changed.
- FINAL is only accepted from `bindDeadline` plus the last schedule segment start (90 days with the default demo schedule).

### 5.5 What the bind workflow listens for
The factory emits `VerifyRequested(vault, wallet, videoId, challenge)` when a creator calls `submitForVerification()` on the vault. Use that event on `0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4` as the trigger. The creator can request a check once every 10 minutes.

## 6. How the campaign runs

1. A creator calls `requestBinding(videoId)` on the vault and puts the returned challenge on the YouTube video, then calls `submitForVerification()`.
2. The bind workflow verifies it and sends a BIND report. On acceptance the creator is bound, their full cap is reserved, and the **upfront** share (10% by default) is paid in the same transaction.
3. The snapshot workflow sends view counts regularly (at least once per stale-snapshot period, 3 days by default, or payments freeze).
4. Creators, or anyone, call `claim(wallet)` on the vault to pay a bound creator what the schedule allows. The payout workflow can also send CLAIM reports for batches, which respect the minimum payout.
5. After the last schedule point, the final workflow sends a FINAL report, which finalizes the campaign. If it never arrives, anyone can call `finalizeFromLastSnapshot()` after `bindDeadline` plus the schedule length plus the dead-man timeout.
6. After finalizing, anyone calls `settle(wallet)` per creator to release unearned reserve, and `sweep()` to send everything unreserved to the brand. `sweep()` can be called any time after the binding deadline and only moves funds not reserved for creators.

## 7. Safety notes

- Keep the deployer key in `.env` only. Never paste it into chat or commit it. The key must be a testnet-only wallet.
- Do not use the mock forwarder (`0x6E9EE680ef59ef64Aa8C7371279c27E496b5eDc1`) for anything with value. It is for simulation, and one source says it lets anyone forge reports.
- The upfront is paid on any accepted BIND report, so the bind workflow must verify video ownership carefully before reporting.
- The brand cannot withdraw before the binding deadline, and after it can only receive unreserved funds.
- No owner, admin, pause or upgrade function exists. Settings of a campaign cannot be changed after creation.
- Arc mainnet is not covered. The script refuses to run on any chain other than Arc Testnet.

## 8. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `NotDeployer` when locking | Wrong wallet. Use the deployer `0x0612...F4b5`. |
| `IdentityAlreadyLocked` | Already locked. Read `workflowOwner()` and the `wf*` values instead. |
| `InvalidIdentity` | Zero or repeated ids, or a zero owner. |
| `IdentityNotLocked` when creating a campaign | Lock the identity first. |
| `InvalidParams` when creating a campaign | A value is out of range: bucket length 3,600 s to 7 days, stale limit at least 1 day, upfront at most 100000 ppm, 1 to 10 videos per creator, deadline in the future, cap and rate above zero. |
| Chainlink write shows `REVERTED` | Check the forwarder is the production one, the workflow owner and id match what was locked, the vault is from this factory, and the report bytes are new. |
| `ReportRejected` with `BUDGET` | The vault holds less than the cap plus existing reserves. Fund it. |
| `ReportRejected` with `NO_MATCH` | The challenge or video does not match the creator's latest `requestBinding`. |
| Creator claims 0 | Snapshots are stale, or the schedule fraction has not reached their earned amount yet. |
| Forge says insufficient funds | The deployer wallet needs more test USDC (the sidebar button), because Arc gas is paid in USDC. |

## 9. Reference

- `createCampaign` argument order: brand, usdc, bindDeadline, ratePerThousand, capPerCreator, maxCreators, maxVideosPerCreator, bucketLen, maxGrowthPerDay, staleAfter, deadmanTimeout, minPayout, upfrontPpm, schedule[(start, startPpm, endPpm)].
- Contracts: `contracts/CampaignFactory.sol`, `contracts/ReportReceiver.sol`, `contracts/CampaignVault.sol`, `contracts/ScheduleLib.sol`.
- Deploy script: `contracts/script/DeployOutVest.s.sol` (variables listed at the top).
- Test status at deployment time: 243 Foundry tests pass, both security reviews had no findings.
- Chainlink forwarder directory: `https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-ts`.
