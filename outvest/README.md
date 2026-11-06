# OutVest

Escrowed USDC payouts for YouTube creators on Arc. Brands lock USDC in a campaign vault; creators are paid per verified
view on a fixed schedule (10% instantly when their video is verified). Chainlink CRE verifies public YouTube numbers,
Circle user-controlled wallets handle sign-in and signing, and Chainlink CCIP carries portable earnings receipts.

## Layout

| Path | What it is |
|---|---|
| `web/` | Next.js app: landing, Circle wallet onboarding, brand and creator dashboards wired to the contracts |
| `outvest_smart_contract_builder_5aq5r7/` | Final Solidity contracts (factory, receiver, vault, schedule), CCIP receipt contracts, Foundry tests, deploy scripts, docs |
| `outvest_smart_contract_builder_5708kl/` | Earlier contract build kept for history |
| `chainlink/outvest-cre/` | Four CRE workflows (bind, snapshot, final, payout), shared code, and the manual relayer used while CRE deploy access is pending |
| `outvest-architecture.md` | Full architecture and design decisions |
| `.agents/skills/` | Chainlink agent skills used while building (CRE, CCIP, and others) |

## Arc Testnet deployments

| Contract | Address |
|---|---|
| Production factory (identity not locked) | `0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4` |
| Demo factory (relayer wallet is forwarder, identity locked) | `0xEfFB32747853C507c3cfa9C2a8f16DbC0eA5dFc8` |
| `EarningsReceiptSender` (CCIP) | `0x96dfc97779d32f09988D6490159B4EcF4b31aBeE` |
| `EarningsReceiptReceiver` (CCIP, Base Sepolia) | `0x38E64d11eD3982D108266fA7829E31dd70292061` |

The production factory is waiting on Chainlink CRE deploy access, because it needs the four deployed workflow ids before
its identity can be locked. Until then the demo factory uses a manual relayer (`chainlink/outvest-cre/relayer`) that
sends the same reports the workflows would. That is a weaker trust model: whoever holds the relayer key is the oracle.

## Run it

```bash
# contracts
cd outvest_smart_contract_builder_5aq5r7 && bun install
FOUNDRY_SOLC_VERSION=0.8.27 forge test --match-path 'contracts/test/OutVest.*t.sol'   # 244 tests

# CRE workflows
cd chainlink/outvest-cre && bun install && bun test common && bunx tsc --noEmit
cre workflow simulate wf-snapshot --target local-simulation --non-interactive --trigger-index 0

# web app (needs .env.local, see web/.env.example)
cd web && bun install && bun run dev
```

Secrets stay out of git: `.env`, `.env.local` and `broadcast/` are ignored. See each folder's README or `docs/` for details.
