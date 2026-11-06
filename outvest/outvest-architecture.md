# OutVest: Final Implementation Architecture

Programmatic stablecoin finance for YouTube creators. Brands pool USDC into a campaign vault on **Arc**. Creators are paid on a hybrid schedule (minimal drip, then tranches) as **Chainlink CRE** verifies public YouTube view counts. Users get **Circle Wallets**. No admin, operator or mediator can release money: only verified CRE reports plus a fixed time schedule can.

> Status: design document, not audited code. Items marked **[VERIFY]** were not confirmed in the docs I read and must be checked before building. Not legal or financial advice.

---

## 1. What the app is

OutVest is a campaign escrow where a brand locks USDC and a creator earns it per verified view, released over time.

- **Brand**: creates a campaign (budget, rate per 1,000 views, per-creator cap, schedule), funds it in USDC.
- **Creator**: joins with a wallet, proves they own a video by pasting a challenge code in the video description, then claims USDC as it unlocks.
- **Verifier**: a CRE workflow that reads the public YouTube Data API and writes signed reports onchain. It is the only thing that can move state.
- **Contracts**: hold the money and enforce the rules. No owner key exists.

## 2. Problem it solves

| Today | With OutVest |
|---|---|
| Brands pay creators by invoice or trust; creators chase payments | Funds are escrowed upfront, visible onchain |
| Creators fear non-payment, brands fear fake views | Pay follows verified views with a lag and a time schedule |
| Platforms/mediators hold funds and can freeze or arbitrate | No mediator; rules fixed at creation |
| Cross-border payouts are slow and costly | USDC on Arc, settled in seconds |
| Clawbacks are messy | Ratchet: paid amounts never reverse; exposure is bounded by the schedule |

Verification uses only **public** YouTube Data API v3 numbers (`videos.list`, `part=statistics`, API key, 1 quota unit per call, up to 50 IDs per call). The Analytics API needs channel-owner OAuth and is not used.

## 3. System overview

```
                         +------------------------+
                         |   Web app (Next.js)    |
                         |  brand view / creator  |
                         +-----------+------------+
                                     |
                +--------------------+---------------------+
                |                                          |
     Circle Wallets (user-controlled)             Backend (read-only helper)
     sign-in, approve, fund, claim                indexing, UI data, gas policy
                |                                          |
                v                                          v
   +--------------------------- Arc (EVM, USDC gas) ----------------------------+
   |  CampaignFactory -> CampaignVault  <-- onReport --  ReportReceiver          |
   |                          ^                               ^                  |
   |                    ChannelRegistry                       |                  |
   +--------------------------+-------------------------------+------------------+
                              | events (EVM log trigger)      | signed reports
                              v                               |
                   +----------------------- Chainlink CRE ---------------------+
                   |  WF-1 Registration check   (EVM log trigger)              |
                   |  WF-2 View snapshot        (cron trigger)                 |
                   |  WF-3 Final settlement     (cron/log trigger)             |
                   |  WF-4 Payout keeper        (cron trigger) -> CLAIM report |
                   |  HTTP capability -> YouTube Data API (key in CRE secrets) |
                   |  DON consensus -> runtime.report -> evmClient.writeReport |
                   +-----------------------------------------------------------+
                              |
                  KeystoneForwarder (Chainlink) -> onReport(metadata, report)
```

Autonomy loop: **fund (user tx) -> event -> CRE reads YouTube -> signed `SNAPSHOT` report -> forwarder -> ReportReceiver -> vault state -> CRE payout keeper (WF-4) sends a `CLAIM` report -> vault pays USDC to each creator's bound wallet**. Chainlink both verifies and triggers the payout, so no human or app has to press claim. `claim()` stays permissionless as a fallback if CRE is down.

## 4. Components

### 4.1 Smart contracts (Solidity, built in Arc Studio, deployed manually)

**CampaignFactory**
- `createCampaign(params)` deploys a `CampaignVault` with immutable parameters. Params: brand refund address, budget, rate, per-creator cap, schedule table, lag window, report-staleness limit, dead-man timeout, end time.
- Stores the **rule hash** (`keccak256` of all parameters) and emits it.
- Pins the CRE identity (forwarder, workflow IDs, workflow owner) into the receiver as immutables.
- Factory has no owner and no setters.

**CampaignVault** (one per campaign)
- Holds USDC. Tracks per-creator: bound wallet, video IDs, snapshots, `alreadyPaid`.
- `fund(amount)`: pulls USDC from the brand (after `approve`). Only allowed before `startTime`. Funding is additive; **no withdrawal path** for the brand mid-campaign.
- `claim(creator)`: permissionless fallback; computes `claimable` and pays **only** the bound creator wallet.
- `payoutBatch(creators[])`: callable **only by the ReportReceiver** (when it processes a verified `CLAIM` report). For each address it recomputes `claimable` onchain and pays the bound wallet; entries with zero claimable, unbound wallets or below `minPayout` are skipped. The report supplies only *who to try*, never amounts or destinations. Batch size is capped (e.g. 25) to bound gas.
- `sweepUnallocated()`: permissionless, after final settlement; sends the remainder to the brand address fixed at creation.
- Automatic pause: rule-based on report content (growth too fast, stale reports). No pause key.
- Dead-man rule: if no valid report for N days after end, anyone can call `finalizeFromLastSnapshot()`.

**ChannelRegistry** (can live inside the vault or be shared)
- `requestBinding(campaignId, videoId)`: issues `challenge = keccak256(campaignId, creatorWallet, videoId, nonce)` and emits `BindingRequested`.
- Binding is written **only** by a verified report from WF-1.

**ReportReceiver**
- Implements `IReceiver` (`onReport(bytes metadata, bytes report)`).
- Accepts calls only from the Arc KeystoneForwarder, and only for the pinned workflow ID and owner.
- Rejects malformed, out-of-order (sequence number), duplicate (report hash) and stale (timestamp) reports.
- Report types: `BIND`, `SNAPSHOT`, `FINAL`, `CLAIM`.

Important design choice: Chainlink's `ReceiverTemplate` extends OpenZeppelin `Ownable` and has owner-settable forwarder/workflow checks. That contradicts "no admin". Use a **custom receiver with immutables** (forwarder, workflowId, workflowOwner) and no owner, or renounce ownership immediately after configuring the template. The template's workflow-name check requires owner validation (name is `bytes10`, collisions possible); prefer ID + owner and skip the name.

**Payment math (on `claim`)**
```
payableViews(t) = min(snapshot views over trailing lag window)        // lagged-minimum
earned(t)       = min(payableViews * rate / 1000, perCreatorCap)
f(t)            = schedule(t)                                         // 0..1
claimable(t)    = max(0, f(t) * earned(t) - alreadyPaid)
alreadyPaid    += claimable                                           // ratchet, never decreases
```
Default schedule (fixed per campaign at creation): day 0-7: 0%; day 7-30: linear 0 to 20%; day 30: 50%; day 60: 80%; day 90: 100%. Minimal drip capped (e.g. at most 25%).

Worked example: budget 1,000 USDC, rate 2 USDC per 1k views, cap 300 USDC. Day 20 -> 15.8, day 30 -> 100, day 60 -> 153.6, day 90 -> 184.

### 4.2 CRE workflows (TypeScript or Go, `cre` CLI)

| Workflow | Trigger | Does | Report |
|---|---|---|---|
| WF-1 Registration check | EVM log: `BindingRequested` | Fetch video description via Data API `videos.list part=snippet`; confirm challenge code present; consensus across nodes | `BIND(campaign, wallet, videoId)` |
| WF-2 View snapshot | Cron (e.g. every 6-24 h) | Batch up to 50 video IDs per call, `part=statistics`; nodes agree on a median/bucketed value; attach timestamp and sequence | `SNAPSHOT(campaign, [videoId, views], seq, ts)` |
| WF-3 Final settlement | Cron/log at campaign end | Last snapshot set after end; computes final lagged-min | `FINAL(campaign, ...)` |
| WF-4 Payout keeper | Cron (e.g. daily, and right after each schedule step) | EVM-reads each bound creator's `claimable()` from the vault; selects those above `minPayout`; chunks into batches | `CLAIM(campaign, [creator, ...])` |

Notes
- YouTube counts arrive as strings; parse carefully. The API returns only current totals, so **the contract stores its own snapshot history** to compute the lagged minimum.
- Each workflow call uses the HTTP capability; nodes run it independently and reach consensus before the report is signed.
- Write path: `runtime.report()` creates the signed report, `evmClient.writeReport()` submits it, the Chainlink `KeystoneForwarder` validates signatures and calls `onReport`.
- **YouTube API key** is stored as a CRE secret, never in the repo or onchain. Confidential HTTP (production-supported since Feb 2026) can keep the key out of node-visible request data.
- Workflow ID changes on every redeploy, so the factory pins a specific ID. Updating verification logic means a new factory/version for **new** campaigns; existing campaigns keep their pinned workflow (this is the autonomy trade-off).

### 4.3 Circle Wallets

| Role | Wallet type | Why |
|---|---|---|
| Brand, creator (people) | **User-controlled** (email/social/PIN sign-in; user approves each tx) | Non-custodial from the app's side; user authorizes `approve`/`fund`/`claim` |
| Optional embedded passkey experience | **Modular** (passkeys, optional gasless module) | Smoother UX later; **[VERIFY]** availability on Arc |
| Deployer/ops wallet (only for deploying and tooling, holds no campaign power) | **Developer-controlled SCA** | Used by Circle Contracts API to deploy; Gas Station sponsors fees on Arc Testnet |

Gas: Arc uses USDC as gas. For SCA wallets, **Gas Station** sponsors fees on Arc Testnet (per Arc's deploy tutorial). **[VERIFY]** that Gas Station policies cover user-controlled/modular wallets on Arc and what the mainnet policy looks like. Circle's Wallets overview page does not mention Arc; the Arc docs do show dev-controlled SCA on `ARC-TESTNET`.

Security
- `CIRCLE_API_KEY` and `CIRCLE_ENTITY_SECRET` stay server-side only (secret manager), never in the frontend.
- The backend never holds creator or brand funds and cannot call `claim` for a different payee (contract enforces payee).
- Because `claim()` is permissionless and pays only the bound wallet, the app (or anyone) can trigger claims for creators without gaining control.

### 4.4 Frontend and backend
- **Frontend**: brand dashboard (create, fund, status, rule hash, schedule chart), creator dashboard (register video, copy challenge code, claimable now, next unlock, claim button), public campaign page (anyone can verify rules and reports).
- **Backend** (stateless helper): indexes contract events, serves charts, relays Circle SDK calls, reads CRE report history. It has **no privileged onchain role**. If it goes down, funds still release.

## 5. End-to-end flows

**A. Create and fund (brand)**
1. Brand signs in (Circle user-controlled wallet), enters terms.
2. `createCampaign` -> vault + rule hash emitted; receiver pinned to CRE workflow IDs.
3. Brand `approve` USDC, then `fund`. Funds locked; no brand withdrawal.

**B. Join and bind (creator)**
1. Creator signs in, picks campaign, enters video ID, calls `requestBinding` -> challenge code.
2. Pastes code into the video description.
3. `BindingRequested` event triggers WF-1; nodes read description via Data API; report `BIND` -> `onReport` -> wallet bound to video. Nobody can bind manually.

**C. Snapshots**
Cron fires WF-2; `SNAPSHOT` reports update stored counts. Abnormal jumps trigger the automatic pause rule.

**D. Payout (triggered by Chainlink)**
WF-4 wakes on its cron, reads `claimable` for bound creators, and submits a `CLAIM` report. The forwarder delivers it to the ReportReceiver, which calls `payoutBatch`. The vault recomputes each amount from its own snapshots and schedule, then transfers USDC to the bound wallets. Creators receive funds with no action. Fallback: anyone, including the creator, can call `claim(creator)` if WF-4 is delayed.

Why the report carries no amounts: even a faulty WF-4 can only cause payouts the contract would allow anyway, to the right wallets, never early or larger. Worst case is a delay.

**E. Settlement and sweep**
After end, WF-3 sends `FINAL`. Then `sweepUnallocated()` returns the remainder to the brand address. If no valid report arrives for N days, `finalizeFromLastSnapshot()` does the same deterministically.

## 6. Autonomy and security model

Guarantees:
- No owner/admin/operator/arbiter/proxy; all rules fixed at creation and committed as a rule hash.
- Only the Chainlink forwarder, for the pinned workflow ID and owner, can change state (including triggering payouts); `claim()` is the only other path and can only pay out what the rules already allow.
- Bindings come only from verified reports; payee is always the bound wallet.
- Ratchet and caps bound loss; lag window blunts view manipulation and later YouTube invalid-traffic removals.
- Dead-man finalization prevents stuck funds.

Honest limits:
- A contract bug or bad data cannot be patched after launch. Mitigate: audit, small caps, conservative defaults, per-campaign budget limits.
- Trust moves to the CRE network, YouTube's public numbers, and the code.
- YouTube may remove invalid views after validation; the lag window reduces but does not eliminate this.
- Immutable workflow pinning means a compromised/buggy workflow version cannot be swapped for existing campaigns.
- Arc Studio output is AI-generated; the Arc Studio UI itself warns to review generated contracts. Treat as a draft.

## 7. Build and deployment plan

**Contracts (Arc Studio, manual deploy)**
1. Draft `CampaignFactory`, `CampaignVault`, `ReportReceiver` in Arc Studio; review and test locally (Foundry/Hardhat) with the mock forwarder.
2. Deploy to **Arc Testnet** from your machine (or via Circle Contracts API `POST /templates/{id}/deploy` / contract import, with `blockchain: ARC-TESTNET`).
3. Use the **production** forwarder for deployed workflows, mock forwarder only for simulation.

**CRE project**
1. Create a Chainlink Platform account and organization; install `cre` CLI (v1.0.7+; TS SDK v1.3.1+ or Go SDK v1.1.4+ for Arc Testnet).
2. In `project.yaml`, use chain name `arc-testnet`.
3. Add secret: `YOUTUBE_API_KEY`.
4. `cre workflow simulate --broadcast` against the mock forwarder, then `cre workflow deploy`.
5. Read the deployed workflow IDs and set them into the factory/receiver.

**Forwarders for Arc Testnet** (from the CRE Forwarder Directory; re-check before use):
- Simulation (MockKeystoneForwarder): `0x6E9EE680ef59ef64Aa8C7371279c27E496b5eDc1`
- Production (KeystoneForwarder): `0x76c9cf548b4179F8901cda1f8623568b58215E62`

**Testing**
- Simulation with the mock forwarder does **not** provide workflow metadata, so receiver checks on workflow ID/owner fail in simulation. Use a test-only receiver that skips metadata checks; never ship that to production.
- Unit tests: schedule math, lagged-min, ratchet, duplicate/stale/out-of-order reports, pause/dead-man paths, payee enforcement, rounding.
- Testnet dry run with a real video and a small budget.

## 8. Functionality list

Brand: create campaign, fund, view rule hash and schedule, monitor payouts, receive swept remainder after settlement.
Creator: sign in with email/social/PIN, request binding, see challenge code, view claimable and next unlock, claim, view history.
Public: verify rules, reports, balances; call `claim`, `finalizeFromLastSnapshot`, `sweepUnallocated`.
System: snapshot cron, binding verification, Chainlink-triggered automatic payouts (WF-4), final settlement, auto-pause, dead-man finalization, event indexing.

## 9. Roadmap

1. **MVP (testnet)**: factory, vault, receiver, WF-1/2/3, Circle user-controlled wallets, one campaign type.
2. **Hardening**: audit, caps, multi-video per creator, multi-creator pools.
3. **Optional claim-to-chain via CCIP**: plain USDC token transfer with no data (no receiver contract to fail), claimer pays native fee, same-chain claim remains default. Check the CCIP Directory for lane availability. CCIP is live on Arc mainnet per launch announcements.
4. **DeFi layer**: tokenized payout positions/advances with anti-loop rules (price on lagged-min views, transfer lock until first checkpoint, haircut and cap, creator retains a share); opt-in yield on idle escrow via ERC-4626; risk tranches later; optional Superfluid streaming.

## 10. Risks and open items

| Item | Status |
|---|---|
| CRE on **Arc mainnet** | Docs I read list Arc **Testnet** only for CRE; mainnet support **not confirmed**. Until confirmed, ship on testnet or plan a different verification path for mainnet |
| Circle user-controlled / modular wallets on Arc | **[VERIFY]**; only dev-controlled SCA on Arc Testnet confirmed |
| Gas Station coverage for user wallets on Arc | **[VERIFY]** |
| Setter/getter names on ReceiverTemplate | Seen: `getExpectedWorkflowId`; others **[VERIFY]**; custom immutable receiver avoids this |
| Arc USDC token interface/address | **[VERIFY]** in Arc docs before coding transfers |
| YouTube API policy | Stored-data refresh rule (~30 days) and wording changed in 2026; onchain store only counts/hashes/amounts; read current policy before launch |
| Fraud/view botting | Mitigated by lag + cap + ratchet, not eliminated |
| Regulatory | Keep non-custodial; GENIUS Act rules not finalized; India has no stablecoin framework; get legal advice |
| Competitors | FlowBack, Chainfluence, ClipPool, clippay, Whop Content Rewards, YTPayouts; differentiate on hybrid schedule, no-mediator autonomy, public-data verification, pooled treasuries |
| WF-4 gas and cost | Each `CLAIM` batch costs gas (USDC on Arc) paid by the CRE write; tune cadence and `minPayout` so tiny payouts are not gas-negative. Confirm CRE write gas limits for batch size. |
| CRE examples | Chainlink labels them educational and unaudited |

## 11. Sources

- Circle Wallets: https://developers.circle.com/wallets
- Chainlink CRE getting started: https://docs.chain.link/cre/getting-started/overview
- CRE supported networks (TS): https://docs.chain.link/cre/supported-networks-ts
- CRE Forwarder Directory: https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-go
- Building consumer contracts: https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
- Onchain write (TS): https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/overview-ts
- Arc deploy contracts tutorial: https://docs.arc.io/arc/tutorials/deploy-contracts
- Arc Studio: https://developers.circle.com/ai/arc-studio
- Idea doc: `youtube-creator-payouts-idea.md`
