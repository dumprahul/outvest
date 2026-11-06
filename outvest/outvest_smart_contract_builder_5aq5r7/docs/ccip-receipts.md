# CCIP earnings receipts

A creator's payout total on Arc can be copied to another chain with one Chainlink CCIP message. No USDC moves:
Arc's native USDC is not a CCIP token yet (checked against the CCIP API), so this carries state only.

| Piece | Chain | Address |
|---|---|---|
| `EarningsReceiptSender` | Arc Testnet | `0x96dfc97779d32f09988D6490159B4EcF4b31aBeE` |
| `EarningsReceiptReceiver` | Base Sepolia | `0x38E64d11eD3982D108266fA7829E31dd70292061` |
| Sender is bound to factory | Arc Testnet | `0xEfFB32747853C507c3cfa9C2a8f16DbC0eA5dFc8` |

- Anyone may call `sendReceipt(dstSelector, dstReceiver, vault, wallet)` and pays the CCIP fee in native token (excess is refunded).
- The message is built from the vault's own `creatorInfo(wallet).paid`; the caller supplies no amounts. The vault must come from the factory and the wallet must be bound.
- The receiver accepts only the pinned source chain selector and sender, has no owner, and a receipt can only ratchet upward.
- Live proof: send tx `0xb67e7cec4a2a6c35576d73b802d713e3ce55bb90ebfd34c062f91011ec5f25a6`, CCIP message
  `0x82fbdc6e88949640b016806f3345ec0cd08771064444aaab4e80e9288b12cb73` (SUCCESS), `totalEarned(wallet)` on Base Sepolia = 500000 (0.5 USDC).
- Deploy: `contracts/script/DeployCcipReceipts.s.sol` (`ROLE=sender` on Arc, `ROLE=receiver` on the destination). Tests: `contracts/test/OutVest.Ccip.t.sol`.
