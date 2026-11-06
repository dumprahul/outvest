# OutVest CRE workflows

Four Chainlink CRE workflows (TypeScript) that feed the deployed `ReportReceiver` on Arc Testnet.
Each is its own deployed workflow because the factory pins one workflow id per report type.

| Dir | Report | Trigger | What it does |
|---|---|---|---|
| `wf-bind` | BIND (1) | EVM log: factory `VerifyRequested` | Fetches the video description, checks the creator's challenge is present, reports the baseline views |
| `wf-snapshot` | SNAPSHOT (2) | Cron, every 6 h | Reads bound videos from the vault, fetches view counts (per-video median across nodes), reports up to 50 per message |
| `wf-final` | FINAL (3) | Cron, daily | Same as snapshot, but only after `bindDeadline + scheduleLength` and only if not finalized |
| `wf-payout` | CLAIM (4) | Cron, every 12 h | Reads `claimable()` per creator, batches wallets (max 25) at or above `minPayout` |

Reports carry no amounts. Envelope: `abi.encode(uint8 rtype, address vault, uint64 seq, uint64 ts, bytes payload)`.
`seq` is DON time in ms x 16 (+ chunk index), so it only goes up. `ts` is DON time in seconds.

Shared code is in `common/` (ABIs, envelope encoding, YouTube fetch with consensus, EVM read/write).
Config (`config.staging.json`) already holds the deployed factory `0xBD8e...17a4` and receiver `0x6818...9C2b`.
Secrets: only `YOUTUBE_API_KEY` (mapped to env var `YOUTUBE_API_KEY_VAR` in `secrets.yaml`).

## Checked so far
- `bun test common`: 10 unit tests (video id encoding, envelope/payload layout, bounds, seq, challenge match, YouTube parsing)
- `bunx tsc --noEmit`: clean
- `cre-compile` builds all four to WASM, so the code runs under CRE's QuickJS runtime
- NOT run: `cre workflow simulate` (needs `cre login`; Chainlink auth returned HTTP 500 when tested) and no onchain write

## Run it
```bash
cd chainlink/outvest-cre && bun install
cp .env.example .env        # fill YOUTUBE_API_KEY_VAR (and CRE_ETH_PRIVATE_KEY for broadcast)
cre login
cre workflow simulate wf-snapshot --target local-simulation --non-interactive --trigger-index 0
cre workflow simulate wf-bind --target local-simulation --non-interactive --trigger-index 0 --evm-tx-hash <tx of submitForVerification> --evm-event-index 0
```
Simulation without `--broadcast` sends nothing. Simulation uses the mock forwarder, which the receiver rejects
(it pins the production forwarder), so a real end-to-end check needs deployed workflows.

## Deploy order
1. `cre workflow deploy wf-bind|wf-snapshot|wf-final|wf-payout --target staging-settings`; note each workflow id and the owner address.
2. Confirm the ids with `cre workflow hash` / `cre workflow list`; they must be distinct.
3. Lock the identity (irreversible) with `WF_OWNER`, `WF_BIND`, `WF_SNAPSHOT`, `WF_FINAL`, `WF_PAYOUT` (see `docs/deployment.md` section 4.2).
4. Create the campaign, put its vault into `vaults` in the three cron configs (or rely on `maxCampaigns: 1` = newest campaign), redeploy (ids change, so only before locking; after locking, config edits that change the id need a new factory).
5. Fund the vault, add the secret with `cre secrets create`.

## Known limits
- 15 EVM reads per execution: one vault with up to ~12 creators fits. Beyond that the snapshot logs the cut and continues next run. Bigger campaigns need sharding.
- Two BIND reports in the same moment can arrive out of order; the later-seq one wins and the other soft-rejects `STALE_SEQ`. The creator retries after the 10 min cooldown.
- Changing config changes the workflow id. Because the factory pins ids, set final config before locking.
- YouTube key is a normal CRE secret. Confidential HTTP would also hide it from node request data.

## Demo mode: manual relayer (no CRE deploy access)
`relayer/cli.ts` sends the same reports as the workflows, from real YouTube data, by calling `receiver.onReport`
from the wallet set as the factory's forwarder. Deploy the factory with `FORWARDER=<relayer wallet>` and lock the
identity with that wallet as `WF_OWNER` (any distinct nonzero ids). Whoever holds that key is the oracle, so this
is a demo trust model, not the Chainlink one. Campaigns pin their forwarder, so real campaigns need a new factory.
```bash
export FACTORY=0x... ; bun relayer/cli.ts bind --vault 0x... --wallet 0x...   # add --dry-run to only simulate
bun relayer/cli.ts snapshot --vault 0x... ; bun relayer/cli.ts claim --vault 0x... ; bun relayer/cli.ts final --vault 0x...
```
Env: `RELAYER_PRIVATE_KEY` (or `PRIVATE_KEY`), `YOUTUBE_API_KEY_VAR`, optional `RPC_URL` (the public RPC rate-limits).
