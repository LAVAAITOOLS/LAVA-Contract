# LAVA Token — Rule Playbook (Plain English)

## High-level summary

LAVA is a Base-chain token with a fixed supply of 50,000,000 tokens. The token is designed for an IDO-style launch with transparent, fixed economics, short anti-snipe protections, and a comprehensive vesting system that distributes tokens across different stakeholder categories over time.

---

## Immutable rules (must-read)

- **Total Supply:** Fixed at 50,000,000 LAVA — no mint function.
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

The 50M LAVA tokens are distributed as follows:

| Stakeholder           | Allocation | Percentage | Vesting Details                                       |
| --------------------- | ---------- | ---------- | ----------------------------------------------------- |
| **Community Rewards** | 20M        | 40%        | No TGE, 5% monthly over 20 months                     |
| **Public Sale**       | 10M        | 20%        | 100% immediately available (no vesting)                    |
| **CEX Listing**       | 5M         | 10%        | No TGE, 25% quarterly over 4 quarters                 |
| **Advisors**          | 4M         | 8%         | 25% at TGE, 25% weekly for 3 weeks                    |
| **Team**              | 3.5M       | 7%         | No TGE, 3-month cliff, then 10% monthly for 10 months |
| **Private Sale**      | 4.5M       | 9%         | 25% at TGE, 25% weekly for 3 weeks                    |
| **Liquidity**         | 3M         | 6%         | 100% immediately available (no vesting)               |

### Vesting Rules

- **TGE (Token Generation Event):** Set at contract deployment time
- **Cliff Period:** Only Team category has a 3-month cliff (no tokens released during this period)
- **Release Mechanism:** Tokens must be manually released by calling contract functions
- **Immutable Schedules:** Vesting schedules are hardcoded and cannot be changed
- **Wallet Control:** Only contract owner can set destination wallets for each category

### Key Vesting Timeline

- **Week 0 (TGE):** Private Sale (25%), Public Sale (100%), Advisors (25%) receive initial releases
- **Weeks 1-3:** Private Sale, Advisors continue weekly releases
- **Month 1-12:** Community Rewards receive monthly releases
- **Quarters 1-4:** CEX Listing receives quarterly releases
- **Month 4-14:** Team receives monthly releases (after 3-month cliff)

## Fee handling & transparency

- Fees collected by the contract are distributed in the designated wallets.

---

## Governance & compliance

- The token is not upgradable, fees are immutable, and vesting schedules are immutable. Team governance is external (off-chain governance).
- **Vesting Transparency:** All vesting wallet addresses and release schedules should be publicly documented.
- **Regular Releases:** Team should establish processes for timely vesting token releases according to schedules.

---

## FAQs (short)

- Q: Can owner change fees? A: No. Fee rates are hardcoded.
- Q: Can owner pause trading? A: No emergency pause exists.
- Q: Are transfers taxed? A: No — transfers between wallets are tax-free.
- Q: Is liquidity locked on-chain? A: No — the team will lock LP off-chain using a service.
- Q: Can vesting schedules be changed? A: No. All vesting schedules are immutable and hardcoded.
- Q: When do team tokens become available? A: After a 3-month cliff period, then 10% monthly for 10 months.
- Q: How are vested tokens released? A: Tokens must be manually released by calling the contract's release functions.

---
