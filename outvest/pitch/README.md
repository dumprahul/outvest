# OutVest pitch deck brief (8 slides)

Brief for generating the deck. Follow the slide order, the copy and the design system below. All slides share one design.

**Product in one line:** OutVest locks a brand's USDC in escrow on Arc and pays YouTube creators automatically for verified views. Chainlink CRE does the verifying.

---

## Design system (same as the OutVest web app)

**Mood:** calm, soft, modern fintech. Pastel gradient cards on a near-white background, dark navy text, one purple accent. Lots of whitespace, large rounded corners, gentle shadows. No harsh black, no neon.

**Colours**

| Role | Hex |
|---|---|
| Slide background | `#F6F9FB` |
| Card / panel | `#FFFFFF` |
| Ink (headings, body) | `#12123B` |
| Muted text | `#5B6180` |
| Primary accent (buttons, lines, highlights) | `#6C6BBD` |
| Secondary tint | `#EEF0FB` |
| Border | `#E4E8F0` |
| Success / "paid" | `#2F8F5B` |
| Problem / warning | `#B5473B` |

**Pastel card gradients** (160deg, from top-left to a near-white bottom-right), used to colour-code areas:

| Name | Gradient |
|---|---|
| Sky | `#CDEFFA` → `#ECF8FC` → `#F7FBFD` |
| Lilac | `#E3D9FB` → `#F0EAFC` → `#F9F7FE` |
| Peach | `#F9D4CC` → `#FCE9E5` → `#FEF7F5` |
| Periwinkle | `#DCDDF9` → `#EBECFB` → `#F7F7FE` |

**Typography:** Inter (variable). Headings bold with slightly tight letter spacing. Body regular. Monospace only for addresses and code.

**Shapes and effects:** corner radius 24 to 32 px on cards, pill-shaped buttons and tags, soft shadow `0 12px 32px -8px rgba(18,18,59,0.12)`. Thin 1.5 px line icons in `#6C6BBD`. Arrows are thin `#6C6BBD` lines.

**Colour coding used across slides:** Sky = brands (payers). Peach = creators. Lilac = Chainlink CRE. Periwinkle = Arc smart contracts. Use the same colours on every slide.

**Layout rules:** 16:9. One idea per slide. Left-aligned titles. Keep text short. A small "OutVest" wordmark bottom-left and the slide number bottom-right in muted text.

---

## Slide 1: Problem hook

Only one sentence, centred, large. No other content besides the wordmark.

> **Creators do the work. Getting paid is a guessing game.**

Suggested look: sky/lilac gradient background panel with the sentence in ink `#12123B`. A small red `#B5473B` underline on the word "guessing".

---

## Slide 2: Existing problems

Title: **How creator payouts work today**

Three cards side by side (peach, lilac, sky):

1. **Scattered data, no traceability**
   Views live in screenshots, spreadsheets and private dashboards. Nobody can trace what was counted, when, or by whom.
2. **No automation, manual ops**
   Invoices, approvals and bank transfers done by hand. Payment is late, partial or never arrives, and the creator chases it.
3. **It's rigged**
   Whoever holds the money and the data decides the number. Creators can't check it, and brands can't verify what they're billed.

---

## Slide 3: Solution (one liner)

Only one sentence, large:

> **OutVest locks the money first and pays creators automatically for views that are verified onchain.**

Suggested look: same style as slide 1, with a small `#2F8F5B` check icon.

---

## Slide 4: Solution architecture

Title: **How OutVest works**

Diagram, left to right, three zones:

- **Left, sky card: "Brands (payers)"**
  - Create a campaign
  - Fund the vault with USDC
  - Set rate, cap per creator, schedule
- **Middle, two stacked cards:**
  - Top, lilac card: **"Chainlink CRE"**. Verifies the video and the public view count, reaches consensus, sends a signed report.
  - Bottom, periwinkle card: **"Arc smart contracts (DeFi)"**. USDC escrow vault, upfront payout, view-based earnings, unlock schedule, claims and refunds.
- **Right, peach card: "Creators"**
  - Sign in with email or Google (Circle wallet)
  - Register a video with a code in its description
  - Get paid automatically in USDC

Arrows:
1. Brand to Arc contracts: "Fund USDC (escrow)".
2. Creator to Arc contracts: "Register video".
3. Arc contracts to CRE: "VerifyRequested event".
4. CRE to Arc contracts: "Signed report (views)".
5. Arc contracts to Creator: "10% instantly, then scheduled payouts".

Small footer line: "Money is locked before work starts. Numbers come from public data, agreed by many nodes."

---

## Slide 5: Demo time

Title: **Demo time**

Large centred text "Live demo", with a short flow underneath as five small pills in order:

`Brand funds a campaign` → `Creator gets a code` → `Paste code in YouTube description` → `Verify (CRE)` → `Paid in USDC`

Keep this slide very simple, with plenty of empty space.

---

## Slide 6: CRE implementation

Title: **Chainlink CRE implementation**

**I will attach a photo for this slide.** Place the photo large on the right, around 60% of the width, in a rounded card. On the left, add this short text as a caption list (keep it small):

- 4 workflows: bind, snapshot, final, payout
- Trigger: contract event (bind) and cron schedules (the other three)
- Each node reads YouTube independently; results agree by median
- Output: one signed report to the receiver contract
- Identity locked on-chain: only our workflows can move money

---

## Slide 7: Arc contracts, core functions

Title: **Arc smart contracts: core functions**

Use a grid of six small cards (periwinkle gradient), each with an icon, a function name in monospace and one line:

1. `CampaignFactory.createCampaign` Deploys a vault per campaign.
2. `CampaignVault.fund` Locks brand USDC in escrow.
3. `requestBinding` and `submitForVerification` Register a video and ask for verification.
4. `applyBind` Binds the creator and pays 10% of the cap instantly.
5. `claim` / `payout` Pays earned USDC as it unlocks on the schedule.
6. `settle` and `sweep` Final settlement, and unused funds return to the brand.

Footer strip: "Also: ReportReceiver (accepts only the signed CRE reports) and CCIP earnings receipts (proof of earnings on Base Sepolia)."

---

## Slide 8: Thank you

Centred, large: **Thank you**. Under it in muted text: "OutVest. Escrowed, verified, automatic creator pay." Add the repo link `github.com/dumprahul/outvest` as a small pill.

---

## Notes for the designer

- Use the colour coding from the design system on every slide (Sky brands, Peach creators, Lilac CRE, Periwinkle Arc).
- Keep slides 1, 3, 5 and 8 sparse. Slides 2, 4, 6 and 7 can hold more.
- Keep copy as written. Do not add claims such as audited, mainnet, or production.
