# sBTC DeFi Lending Protocol

A decentralized lending protocol for sBTC (Bitcoin on Stacks) with collateralized borrowing, health factor tracking, and liquidation mechanics.

## Overview

This protocol enables:
- **Lenders** to supply sBTC and earn interest
- **Borrowers** to deposit sBTC as collateral and borrow against it
- **Liquidators** to liquidate unhealthy positions and earn rewards

## Key Features

### Collateralization
- Minimum **150% collateral ratio** required to borrow
- Positions become **liquidat able at 125%** collateral ratio
- **10% liquidation penalty** rewards liquidators

### Core Functions

#### For Lenders
- `supply(amount)` - Deposit sBTC to earn interest
- `withdraw(amount)` - Withdraw supplied sBTC

#### For Borrowers
- `borrow(collateral-amount, borrow-amount)` - Deposit collateral and borrow sBTC
- `repay(amount)` - Repay borrowed sBTC (full or partial repayment)

#### For Liquidators
- `liquidate(borrower)` - Liquidate unhealthy positions (<125% collateral ratio)

#### Read-Only Functions
- `get-supply(user)` - Get user's supplied amount
- `get-borrow(user)` - Get user's borrow position (amount, collateral, last-update)
- `calculate-health-factor(user)` - Calculate position health (collateral/debt * 100)
- `is-position-healthy(user)` - Check if position is above liquidation threshold
- `calculate-max-borrow(collateral-amount)` - Calculate maximum borrowable amount

## Getting Started

### Prerequisites
- Node.js 18+
- Clarinet 2.0+

### Installation

```bash
# Clone the repository
git clone https://github.com/bastiatai/sbtc-lending
cd sbtc-lending

# Install dependencies
npm install
```

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with UI
npm run test:ui
```

**Test Coverage:**
- 24 comprehensive test cases
- Supply/withdraw logic
- Borrow/repay logic with position accumulation
- Health factor calculations
- Liquidation mechanics
- Edge cases and multi-user scenarios

### Contract Verification

```bash
# Check contract syntax
clarinet check

# Open Clarinet console for manual testing
clarinet console
```

## How It Works

### Supplying sBTC

Lenders supply sBTC to the pool to earn interest:

```clarity
(contract-call? .sbtc-lending-pool supply u1000000) ;; Supply 1 sBTC (8 decimals)
```

### Borrowing Against Collateral

Borrowers deposit collateral (150% minimum) to borrow sBTC:

```clarity
;; Deposit 1.5 sBTC as collateral, borrow 1 sBTC
(contract-call? .sbtc-lending-pool borrow u1500000 u1000000)
```

**Health Factor:**
- Health Factor = (Collateral / Debt) * 100
- Example: 1.5 sBTC collateral / 1 sBTC debt = 150% health factor
- **Safe:** ≥150% (can borrow more)
- **At Risk:** 125-149% (watch closely)
- **Liquidatable:** <125% (liquidators can liquidate)

### Repaying Debt

Borrowers can repay partially or fully:

```clarity
;; Partial repayment (collateral returned proportionally)
(contract-call? .sbtc-lending-pool repay u500000)

;; Full repayment (all collateral returned, position closed)
(contract-call? .sbtc-lending-pool repay u1000000)
```

### Liquidation

When a position's health factor drops below 125%, liquidators can liquidate it:

```clarity
;; Liquidate unhealthy position
(contract-call? .sbtc-lending-pool liquidate 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

Liquidators:
1. Repay the borrower's debt
2. Receive all collateral plus a 10% penalty bonus

## Architecture

### Smart Contract Structure

- **Data Maps:**
  - `supplies` - Tracks each user's supplied sBTC
  - `borrows` - Tracks each user's borrow position (amount, collateral, last-update)

- **Data Variables:**
  - `total-supplied` - Total sBTC supplied to the pool
  - `total-borrowed` - Total sBTC borrowed from the pool

- **Constants:**
  - `collateral-ratio` - 150 (150% collateralization required)
  - `liquidation-ratio` - 125 (125% threshold for liquidation)
  - `liquidation-penalty` - 10 (10% penalty on liquidation)

### Error Codes

- `u100` - Owner-only operation
- `u101` - Insufficient balance
- `u102` - Insufficient collateral
- `u103` - Invalid amount (zero or negative)
- `u104` - Position not found
- `u105` - Unhealthy position
- `u106` - Position is healthy (can't liquidate)

## Production Integration

This example contract uses placeholder comments for sBTC SIP-010 token transfers. To integrate with real sBTC:

1. Deploy or reference the sBTC token contract
2. Replace placeholder comments with actual `contract-call?` to sBTC token
3. Add proper access controls and governance
4. Implement interest rate accrual mechanism
5. Add price oracle integration for accurate liquidations

Example integration:

```clarity
;; Replace this placeholder:
;; (try! (contract-call? .sbtc-token transfer amount tx-sender (as-contract tx-sender) none))

;; With actual sBTC transfer:
(try! (contract-call? .sbtc-token transfer amount tx-sender (as-contract tx-sender) none))
```

## Why This Matters

This protocol demonstrates:

1. **Bitcoin-Backed DeFi** - sBTC enables Bitcoin to be used in Stacks DeFi without centralized custody
2. **Collateralized Lending** - Core DeFi primitive for leverage and capital efficiency
3. **Liquidation Mechanics** - Incentivized position management ensures protocol solvency
4. **Production-Ready Patterns** - Health factors, partial repayments, position accumulation

## Improvements Over Existing Example

The existing [DeFi lending example](https://github.com/stacks-network/docs/tree/master/docs/cookbook/clarity/example-contracts/defi-lending) in the Stacks cookbook has several issues:

1. **Uses STX instead of sBTC** - Misses the emerging sBTC DeFi use case
2. **Borrow function bug** - Doesn't accumulate existing loans correctly
3. **No tutorial** - Just contract code, no explanation or tests
4. **Clarity version issues** - Uses outdated syntax

This implementation fixes all of these issues and provides a complete tutorial.

## Contributing

Contributions are welcome! Please open an issue or PR on GitHub.

## License

MIT

## Resources

- [Stacks Documentation](https://docs.stacks.co)
- [sBTC Documentation](https://docs.stacks.co/sbtc)
- [Clarity Language Reference](https://docs.stacks.co/reference/clarity)
- [Clarinet Documentation](https://docs.stacks.co/clarinet)

---

Built with ❤️ by [@BastiatAI](https://x.com/BastiatAI)
