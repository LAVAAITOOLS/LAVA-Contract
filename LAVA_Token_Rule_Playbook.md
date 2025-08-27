# LAVA Token — Rule Playbook (Plain English)

## High-level summary
LAVA is a Base-chain token with a fixed supply of 250,000,000 tokens. The token is designed for an IDO-style launch with transparent, fixed economics, short anti-snipe protections, and a comprehensive vesting system that distributes tokens across different stakeholder categories over time.

---

## Immutable rules (must-read)
- **Total Supply:** Fixed at 250,000,000 LAVA — no mint function.
- **Burning:** No burn function exists in the contract.
- **Taxes:** Trading tax (applies to AMM buys and sells only):
  - **First 90 days after trading enabled:** 2.5% buy / 2.5% sell.
  - **After 90 days:** permanently 1.0% buy / 1.0% sell.
  - **Owner cannot change these tax rates.**
- **Transfers:** Peer-to-peer wallet transfers are **tax-free**.
- **Blacklists / Pauses:** There are **no** blacklist or emergency pause functions.

---

## Launch & trading rules
- **Launch model:** IDO (not a fair launch). Owner will perform setup actions like adding liquidity and setting the AMM pair.
- **Liquidity lock:** Team will lock liquidity externally (recommended via launchpad or timelock). The contract does not lock LP tokens itself.
- **Trading enable:** Trading is enabled only after owner calls `enableTrading()`.
- **Token Distribution:** Tokens are distributed according to preset vesting schedules (see Token Distribution section below).

---

## Anti-snipe behavior
- For the **first 1 minute** after `enableTrading()`:
  - Any buy OR sell transaction interacting with an AMM pair is limited to **0.5% of total supply** per transaction.
  - This is to reduce sniper bots and large early dumps.
- After 1 minute, the limit is removed automatically.

---

## Token Distribution & Vesting

### Allocation Breakdown
The 250M LAVA tokens are distributed as follows:

| Stakeholder | Allocation | Percentage | Vesting Details |
|-------------|------------|------------|------------------|
| **Community Rewards** | 115M | 46% | No TGE, 2.5% monthly over 12 months |
| **Public Sale** | 50M | 20% | 35% at TGE, 32.5% weekly for 2 weeks |
| **CEX Listing** | 25M | 10% | No TGE, 25% quarterly over 4 quarters |
| **Advisors** | 20M | 8% | 25% at TGE, 25% weekly for 3 weeks |
| **Team** | 17.5M | 7% | No TGE, 5-month cliff, then 10% monthly for 10 months |
| **Private Sale** | 15M | 6% | 25% at TGE, 25% weekly for 3 weeks |
| **Liquidity** | 7.5M | 3% | 100% immediately available (no vesting) |

### Vesting Rules
- **TGE (Token Generation Event):** Set at contract deployment time
- **Cliff Period:** Only Team category has a 5-month cliff (no tokens released during this period)
- **Release Mechanism:** Tokens must be manually released by calling contract functions
- **Immutable Schedules:** Vesting schedules are hardcoded and cannot be changed
- **Wallet Control:** Only contract owner can set destination wallets for each category

### Key Vesting Timeline
- **Week 0 (TGE):** Private Sale (25%), Public Sale (35%), Advisors (25%) receive initial releases
- **Weeks 1-3:** Private Sale, Public Sale, Advisors continue weekly releases
- **Month 1-12:** Community Rewards receive monthly releases
- **Quarters 1-4:** CEX Listing receives quarterly releases
- **Month 6-15:** Team receives monthly releases (after 5-month cliff)

## Fee handling & transparency
- Fees collected by the contract are stored until they reach a swap threshold (`swapTokensAtAmount`).
- When swapping, fees are split according to configurable shares into: liquidity, marketing, and buyback wallets.
- Recommended: set marketing and buyback wallets as multisigs and publish their addresses.

---

## Recommended operational checklist (team)
1. Deploy contract with proper constructor arguments; verify the source on Basescan.
2. **Set all vesting wallet addresses** using `setVestingWallets()` function.
3. Provide liquidity to the selected AMM pair (3% of supply is immediately available).
4. Set the AMM pair address using `setAutomatedMarketMakerPair()`.
5. Optionally adjust fee split via `setFeeShares()` (total rates remain fixed).
6. Enable trading via `enableTrading()` once liquidity is secured and pair is set.
7. **Begin vesting releases:** Set up processes to release vested tokens according to schedules.
8. Lock LP tokens via a trusted service and publish the lock details.
9. Transfer ownership to multisig and publish multisig address publicly.
10. **Publish vesting wallet addresses** and release schedules for transparency.
11. Complete an external security audit and publish the report.

---

## Governance & compliance
- The token is not upgradable, fees are immutable, and vesting schedules are immutable. Team governance is external (multisig / off-chain governance).
- Team should maintain compliance documentation and KYC for wallets receiving marketing/buyback funds if required by jurisdictions.
- **Vesting Transparency:** All vesting wallet addresses and release schedules should be publicly documented.
- **Regular Releases:** Team should establish processes for timely vesting token releases according to schedules.

---

## FAQs (short)
- Q: Can owner change fees? A: No. Fee rates are hardcoded.
- Q: Can owner pause trading? A: No emergency pause exists.
- Q: Are transfers taxed? A: No — transfers between wallets are tax-free.
- Q: Is liquidity locked on-chain? A: No — the team will lock LP off-chain using a service.
- Q: Can vesting schedules be changed? A: No. All vesting schedules are immutable and hardcoded.
- Q: When do team tokens become available? A: After a 5-month cliff period, then 10% monthly for 10 months.
- Q: How are vested tokens released? A: Tokens must be manually released by calling the contract's release functions.
- Q: Are vesting wallets public? A: Yes, all vesting wallet addresses should be published for transparency.


---

Keep this playbook published alongside the contract verification to build trust with investors and auditors.
