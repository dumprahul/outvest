# OutVest

USDC campaign escrow that pays YouTube creators per verified view, released on a fixed time schedule. There is no owner, admin, proxy, upgrade or pause key.

Built with [Arc Studio](https://studio.arc.io)

## Tech stack

- Solidity ^0.8.24 (OpenZeppelin SafeERC20 and ReentrancyGuard), Foundry
- Vite, React, TypeScript, wagmi, viem

## Contracts

- `CampaignFactory`: pins the report workflow identity once, then lets anyone open campaigns.
- `ReportReceiver`: accepts forwarder reports (bind, snapshot, final, payout) and routes them to the right campaign.
- `CampaignVault`: one per campaign; holds the USDC and pays creators on the schedule.
- `ScheduleLib`: validates and evaluates the release schedule.
- `contracts/test/TestReportReceiver.sol` is test-only and must never be deployed.

## Development

Prerequisites: Bun, Foundry.

```
bun install
forge build
forge test
bun run dev
```


## Instant settlement

When a creator's first video is verified and bound, they are paid an upfront share of their cap (up to 10%, set per campaign) right away. The rest is released over time as views are verified.

## Deploy to Arc Testnet

Run from your own testnet wallet (the deployer is the only address that can lock the workflow identity):

```
forge script contracts/script/DeployOutVest.s.sol:DeployOutVest --rpc-url https://rpc.testnet.arc.io --broadcast
```

Options are set with environment variables listed at the top of `contracts/script/DeployOutVest.s.sol`.

## Environment variables

`PRIVATE_KEY` (deploy script only, testnet key) plus the optional deploy options documented in `contracts/script/DeployOutVest.s.sol`.
