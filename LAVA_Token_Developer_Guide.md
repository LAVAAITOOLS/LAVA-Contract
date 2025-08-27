# LAVA Token — Developer Guide

## Overview
This guide explains the LAVA token contract, deployment steps, configuration, and testing checklist. The contract is intentionally conservative: immutable supply, fixed initial fees, a 1-minute anti-snipe limit (0.5% total supply), minimal owner controls for IDO operations, and a comprehensive vesting mechanism for token distribution across different categories.

---

## Files in this package
- `LAVA.sol` — Solidity token contract (final). Compile with Solidity ^0.8.17.
- `LAVA_Token_Developer_Guide.md` — (this file) developer instructions.
- `LAVA_Token_Rule_Playbook.md` — plain-English rulebook for investors/auditors.

---

## Deployment prerequisites
1. Install Hardhat or your preferred framework (Hardhat recommended).
2. Set up a deployer wallet with private key and fund with Base-native tokens for gas.
3. Prepare addresses for:
   - Router (AMM router on Base)
   - Marketing wallet (team multisig recommended)
   - Buyback wallet (team multisig recommended)
   - Liquidity provision wallet (receives 3% of supply immediately)
4. Prepare vesting wallet addresses for:
   - Private Sale (6% of supply)
   - Public Sale (20% of supply)
   - Community Rewards (46% of supply)
   - Advisors (8% of supply)
   - CEX Listing (10% of supply)
   - Team (7% of supply)
5. Optional: prepare a multisig for ownership transfer after deployment.

---

## Recommended Deployment Steps (Hardhat example)
1. Compile: `npx hardhat compile`.
2. Deploy with constructor args: `routerAddress`, `marketingWallet`, `buybackWallet`, `liquidityWallet`.
   - Example Hardhat script will call `new LAVA(router, marketing, buyback, liquidityWallet)`.
   - Note: TGE timestamp is set at deployment time automatically.
3. Verify contract source on Basescan/Etherscan as soon as possible.
4. Set all vesting wallets using `setVestingWallets()` or individual setter functions.
5. Add liquidity: create LAVA <-> BASE (or LAVA <-> stable) pool and provide liquidity.
6. Set AMM pair: call `setAutomatedMarketMakerPair(pairAddress, true)` from owner.
7. Set any desired fee share splits (optional) with `setFeeShares`.
8. Set swap threshold if needed using `setSwapSettings`.
9. Enable trading by calling `enableTrading()` once liquidity is added and pair is set.
10. Begin vesting token releases according to schedules (see Vesting section below).

---

## Important Operational Notes
- **Trading Enable:** Only call `enableTrading()` after liquidity is live and `automatedMarketMakerPairs` contains the correct pair address. The 1-minute anti-snipe window and the 90-day initial fee timer are set from `tradingStartTimestamp` when you call this.

- **Temporary Limits:** The 0.5% per-transaction limit applies only to transactions involving an AMM pair and only during the first 1 minute after trading starts. Normal transfers between wallets are not affected.

- **Fees:** Fees are enforced by contract logic: 2.5% for the first 90 days -> 1% after. The owner cannot change these rates. Fee routing (liquidity/marketing/buyback) is configurable via `setFeeShares` but the overall rates are immutable.

- **SwapBack:** When the contract accumulates `swapTokensAtAmount` or more tokens from fees, it swaps and routes ETH to the marketing/buyback wallets and adds liquidity for the liquidity portion. Ensure the router address is correct for Base.

- **Ownership:** For security, transfer ownership to a multisig (Gnosis Safe) after deployment and initial setup. This reduces risk of key compromise.

---

## Testing Checklist (recommended)
- Unit tests on Hardhat for:
  - ERC20 basics (mint distribution, transfers)
  - Fee application on buy & sell (simulate AMM interactions via pair addresses)
  - SwapBack behavior (simulate contract token accumulation and swap)
  - 1-minute limit behavior: ensure limit enforced and then cleared after 60s
  - 90-day fee reduction behavior (use evm_increaseTime in tests)
  - **Vesting mechanism tests:**
    - TGE releases for applicable categories
    - Weekly/monthly vesting calculations
    - Team cliff period enforcement (5 months)
    - Proper token release functionality
    - Edge cases: multiple releases, full vesting completion
    - Wallet address management functions
- Manual test on a public testnet or forked mainnet: full deploy, liquidity add, pair set, enableTrading, perform buys/sells, and test vesting releases over time.

---

## Gas & Optimization Tips
- Use `hardhat-gas-reporter` and testnet runs to estimate deployment cost.
- Avoid frequent on-chain writes from external scripts during launch to reduce gas spikes.

---

## Vesting Mechanism

### Token Distribution Overview
The contract implements a sophisticated vesting system for different stakeholder categories:

| Category | Allocation | TGE Release | Vesting Schedule | Total Duration |
|----------|------------|-------------|------------------|----------------|
| Private Sale | 6% | 25% | 25% weekly for 3 weeks | 4 weeks |
| Public Sale | 20% | 35% | 32.5% weekly for 2 weeks | 3 weeks |
| Liquidity | 3% | 100% | Immediate (no vesting) | N/A |
| Community Rewards | 46% | 0% | 2.5% monthly for 12 months | 12 months |
| CEX Listing | 10% | 0% | 25% quarterly for 4 quarters | 12 months |
| Advisors | 8% | 25% | 25% weekly for 3 weeks | 4 weeks |
| Team | 7% | 0% | 10% monthly after 5-month cliff | 15 months |

### Vesting Functions
- `releaseTokens(VestingCategory category)`: Releases available vested tokens for a category
- `calculateVested(VestingCategory category)`: View function to check total vested amount
- `getAvailableToRelease(VestingCategory category)`: View function to check releasable amount
- `setVestingWallet(VestingCategory category, address wallet)`: Set wallet for a category
- `setVestingWallets(...)`: Set all vesting wallets at once

### Vesting Categories Enum
```solidity
enum VestingCategory { PrivateSale, PublicSale, CommunityRewards, Advisors, CexListing, Team }
```

### Important Vesting Notes
- TGE (Token Generation Event) timestamp is set at contract deployment
- Team tokens have a 5-month cliff period before any tokens can be released
- All vesting calculations are based on weeks (7 days) from TGE timestamp
- Tokens must be released manually by calling `releaseTokens()` function
- Only the contract owner can set vesting wallet addresses

## Post-Deployment Recommendations
- Verify contract source on Basescan.
- Set all vesting wallet addresses immediately after deployment.
- Transfer ownership to a multisig.
- Lock LP via the chosen launchpad or a timelock service and publish lock info publicly.
- Announce fee schedule and vesting schedules publicly - both are immutable to build investor trust.
- Create automated scripts or manual processes for regular vesting token releases.
- Schedule an external security audit and publish the report.


---

If you want, I can provide a sample Hardhat deploy script and basic unit tests next.
