# OutVest deployed contracts

All on **Arc Testnet** (chain id 5042002, explorer https://testnet.arcscan.app) unless noted.
Deployer / relayer / demo forwarder: `0x0612D26676869aFcF8BCfdcC55Bd62a307fBF4b5`.

## Active (what the app uses)

| Contract | Address |
|---|---|
| Demo `CampaignFactory` (`NEXT_PUBLIC_FACTORY`) | `0xEfFB32747853C507c3cfa9C2a8f16DbC0eA5dFc8` |
| Demo `ReportReceiver` | `0xe32e77c2B3D177603594b7697706656E92fDE8cD` |
| `EarningsReceiptSender` (CCIP, Arc) | `0x96dfc97779d32f09988D6490159B4EcF4b31aBeE` |
| `EarningsReceiptReceiver` (CCIP, **Base Sepolia**, chain id 84532) | `0x38E64d11eD3982D108266fA7829E31dd70292061` |
| USDC (Arc native USDC ERC-20 interface, 6 decimals) | `0x3600000000000000000000000000000000000000` |

The demo factory's forwarder is the deployer wallet above, and its workflow identity is locked with placeholder
workflow ids. A relayer (`chainlink/outvest-cre`, `bun run watch`) sends the reports that Chainlink CRE workflows
would send. Whoever holds that key is the oracle, so this is a demo trust model.

## Funded campaign vaults on the demo factory

| Vault | Cap per creator | Max creators | Rate per 1,000 views | Funded |
|---|---|---|---|---|
| `0x08173A4F1538F9d4cFe53BaAFC5452B5ABBDb693` | 5 USDC | 2 | 2 USDC | 10 USDC |
| `0xC2E0a5343cE6B579A1db079c9228FBAc20f01c39` | 5 USDC | 3 | 2 USDC | 15 USDC |
| `0xa08F9609F7A5f26e992281D863531089e996E39f` | 3 USDC | 3 | 1 USDC | 9 USDC |
| `0x7b6A85b846fFad614A1dcd297AFf25855Db0a95E` | 8 USDC | 2 | 4 USDC | 16 USDC |
| `0x7b94381ce532a334b0869847929ae07DB4A92Ca9` | 2 USDC | 3 | 0.5 USDC | 6 USDC |
| `0x3a47b7baF04bBA273aBfC1B985750e3A61452142` | 1 USDC | 3 | 0.5 USDC | 3 USDC |
| `0x3c69f8A357D7017B45aC160a4aBBAaeF24D68351` | 1.5 USDC | 3 | 0.75 USDC | 4.5 USDC |
| `0x171812c56bB48678bE60e6Ec69f9F771a22C0E6C` | 2 USDC | 3 | 1 USDC | 6 USDC |
| `0xCFb49045912308dF3a1fe5643B7507246d7D4B0B` | 3 USDC | 3 | 1.5 USDC | 9 USDC |

All use the demo schedule (25% at day 0, 50% at day 30, 80% at day 60, 100% at day 90) and pay 10% of the cap
upfront when a creator's first video is verified.

## Unfunded campaigns (created by mistake, ignore)

These four were created with default settings (300 USDC cap, 10 creators) and never funded. They cannot be edited
or removed, and the creator page hides them because they are unfunded.

- `0xC26AE043B672478cc365361d65bfAB886A90DE4A`
- `0x33B1B6d46Ba7D4b26b4E06E3a0183B759F67FA39`
- `0x9C9D6b6fb0B682C6D67e95Da2592A1cf126A80E3`
- `0xEFb17e66bA79A5e59a09885832e3bB9256A913d7`

## Other deployments

| Contract | Address | Notes |
|---|---|---|
| Production `CampaignFactory` | `0xBD8e1748BE54775d32Cbd2Cbe193F2FD6Cd017a4` | Real Chainlink forwarder. Identity not locked, no campaigns. Waiting on CRE deploy access. |
| Production `ReportReceiver` | `0x6818EFf02e79adDB7cB43bb68600a64c4C5b9C2b` | Belongs to the factory above. |
| Mock-forwarder test factory | `0x14Fc4e415A3b8ccCfaABA81Bd43c6D3948b9d311` | Throwaway, for testing only. |
| Mock-forwarder test vault | `0x5655cA74C4F5702C9C452fdebF5a6E6bc6dEb994` | Throwaway. |

## External addresses used

| What | Address |
|---|---|
| CCIP router, Arc | `0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8` |
| CCIP router, Base Sepolia | `0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93` |
| Arc production forwarder | `0x76c9cf548b4179F8901cda1f8623568b58215E62` |
| Arc mock forwarder | `0x6E9EE680ef59ef64Aa8C7371279c27E496b5eDc1` |
| Multicall3 (batched reads in the web app) | `0xcA11bde05977b3631167028862bE2a173976CA11` |

CCIP chain selectors: Arc `3034092155422581607`, Base Sepolia `10344971235874465080`.

## Source

Contracts: `outvest_smart_contract_builder_5aq5r7/contracts/` (`CampaignFactory`, `CampaignVault`, `ReportReceiver`,
`ScheduleLib`, `ccip/`). Deploy scripts: `contracts/script/DeployOutVest.s.sol` and `DeployCcipReceipts.s.sol`.
