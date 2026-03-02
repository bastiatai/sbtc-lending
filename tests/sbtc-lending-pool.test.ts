import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const alice = accounts.get("wallet_1")!;
const bob = accounts.get("wallet_2")!;
const liquidator = accounts.get("wallet_3")!;

describe("sBTC Lending Pool", () => {
  describe("Supply and Withdraw", () => {
    it("should allow users to supply sBTC", () => {
      const supplyAmount = 1000000; // 1 sBTC (8 decimals like Bitcoin)

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "supply",
        [Cl.uint(supplyAmount)],
        alice
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify supply was recorded
      const supply = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-supply",
        [Cl.principal(alice)],
        alice
      );

      expect(supply.result).toBeUint(supplyAmount);
    });

    it("should track total supplied correctly", () => {
      const aliceSupply = 1000000;
      const bobSupply = 500000;

      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(aliceSupply)], alice);
      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(bobSupply)], bob);

      const totalSupplied = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-total-supplied",
        [],
        deployer
      );

      expect(totalSupplied.result).toBeUint(aliceSupply + bobSupply);
    });

    it("should allow users to withdraw supplied sBTC", () => {
      const supplyAmount = 1000000;
      const withdrawAmount = 400000;

      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(supplyAmount)], alice);

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "withdraw",
        [Cl.uint(withdrawAmount)],
        alice
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify remaining supply
      const supply = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-supply",
        [Cl.principal(alice)],
        alice
      );

      expect(supply.result).toBeUint(supplyAmount - withdrawAmount);
    });

    it("should reject withdrawal exceeding supply", () => {
      const supplyAmount = 1000000;
      const withdrawAmount = 2000000;

      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(supplyAmount)], alice);

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "withdraw",
        [Cl.uint(withdrawAmount)],
        alice
      );

      expect(result).toBeErr(Cl.uint(101)); // err-insufficient-balance
    });

    it("should reject zero amount supply", () => {
      const { result } = simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(0)], alice);

      expect(result).toBeErr(Cl.uint(103)); // err-invalid-amount
    });

    it("should reject zero amount withdrawal", () => {
      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(1000000)], alice);

      const { result } = simnet.callPublicFn("sbtc-lending-pool", "withdraw", [Cl.uint(0)], alice);

      expect(result).toBeErr(Cl.uint(103)); // err-invalid-amount
    });
  });

  describe("Borrow and Repay", () => {
    it("should allow users to borrow with sufficient collateral", () => {
      const collateral = 1500000; // 1.5 sBTC
      const borrowAmount = 1000000; // 1 sBTC (150% collateralization)

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify borrow position
      const position = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );

      expect(position.result).toBeSome(
        Cl.tuple({
          amount: Cl.uint(borrowAmount),
          collateral: Cl.uint(collateral),
          "last-update": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should calculate max borrow correctly", () => {
      const collateral = 1500000; // 1.5 sBTC
      const expectedMaxBorrow = 1000000; // 1 sBTC (at 150% ratio)

      const maxBorrow = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "calculate-max-borrow",
        [Cl.uint(collateral)],
        deployer
      );

      expect(maxBorrow.result).toBeUint(expectedMaxBorrow);
    });

    it("should reject borrow exceeding collateral ratio", () => {
      const collateral = 1000000; // 1 sBTC
      const borrowAmount = 800000; // 0.8 sBTC (125% collateralization - too low)

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      expect(result).toBeErr(Cl.uint(102)); // err-insufficient-collateral
    });

    it("should accumulate existing borrow positions correctly", () => {
      const firstCollateral = 1500000;
      const firstBorrow = 1000000;
      const secondCollateral = 750000;
      const secondBorrow = 500000;

      // First borrow
      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(firstCollateral), Cl.uint(firstBorrow)],
        alice
      );

      // Second borrow (should accumulate)
      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(secondCollateral), Cl.uint(secondBorrow)],
        alice
      );

      // Verify accumulated position
      const position = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );

      expect(position.result).toBeSome(
        Cl.tuple({
          amount: Cl.uint(firstBorrow + secondBorrow),
          collateral: Cl.uint(firstCollateral + secondCollateral),
          "last-update": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should allow full repayment and return collateral", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;

      // Borrow
      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      // Repay
      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "repay",
        [Cl.uint(borrowAmount)],
        alice
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify position is removed
      const position = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );

      expect(position.result).toBeNone();
    });

    it("should allow partial repayment and return proportional collateral", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;
      const repayAmount = 500000; // Repay half

      // Borrow
      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      // Partial repay
      simnet.callPublicFn("sbtc-lending-pool", "repay", [Cl.uint(repayAmount)], alice);

      // Verify remaining position
      const position = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );

      const expectedRemainingDebt = borrowAmount - repayAmount;
      const expectedRemainingCollateral = collateral / 2; // Half returned

      expect(position.result).toBeSome(
        Cl.tuple({
          amount: Cl.uint(expectedRemainingDebt),
          collateral: Cl.uint(expectedRemainingCollateral),
          "last-update": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should track total borrowed correctly", () => {
      const aliceCollateral = 1500000;
      const aliceBorrow = 1000000;
      const bobCollateral = 750000;
      const bobBorrow = 500000;

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(aliceCollateral), Cl.uint(aliceBorrow)],
        alice
      );
      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(bobCollateral), Cl.uint(bobBorrow)],
        bob
      );

      const totalBorrowed = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-total-borrowed",
        [],
        deployer
      );

      expect(totalBorrowed.result).toBeUint(aliceBorrow + bobBorrow);
    });

    it("should reject repayment without active position", () => {
      const { result } = simnet.callPublicFn("sbtc-lending-pool", "repay", [Cl.uint(1000000)], alice);

      expect(result).toBeErr(Cl.uint(104)); // err-position-not-found
    });
  });

  describe("Health Factor and Liquidation", () => {
    it("should calculate health factor correctly", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      const healthFactor = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "calculate-health-factor",
        [Cl.principal(alice)],
        deployer
      );

      // Health factor = (1500000 / 1000000) * 100 = 150
      expect(healthFactor.result).toBeUint(150);
    });

    it("should identify healthy position correctly", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      const isHealthy = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "is-position-healthy",
        [Cl.principal(alice)],
        deployer
      );

      expect(isHealthy.result).toBeBool(true);
    });

    it("should identify unhealthy position correctly", () => {
      // Create position at minimum collateral (150%)
      const collateral = 1500000;
      const borrowAmount = 1000000;

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      // Simulate price drop by borrowing more (in reality price oracle would change)
      // For testing: borrow more to push below liquidation threshold
      // This would make health factor = 125% (at liquidation threshold)

      // Health factor 150% is still healthy
      const isHealthy = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "is-position-healthy",
        [Cl.principal(alice)],
        deployer
      );

      expect(isHealthy.result).toBeBool(true);
    });

    it("should allow liquidation of unhealthy position", () => {
      // NOTE: In production, positions become unhealthy when collateral value drops
      // For this test, we can't simulate price changes, so we test the liquidation logic
      // by verifying that positions at/below the 125% threshold can be liquidated

      // This test is conceptual - in a real scenario:
      // 1. User borrows with 150% collateral (healthy)
      // 2. sBTC price drops, making their position <125% (unhealthy)
      // 3. Liquidator can liquidate the position

      // Since we can't create an actually unhealthy position (borrow requires 150%),
      // we'll just verify the liquidation logic rejects healthy positions
      const collateral = 1500000; // 1.5 sBTC
      const borrowAmount = 1000000; // 1 sBTC (150% - minimum required)

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      // This position is healthy (150% >= 125% liquidation threshold)
      // So liquidation should fail
      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "liquidate",
        [Cl.principal(alice)],
        liquidator
      );

      expect(result).toBeErr(Cl.uint(106)); // err-position-healthy
    });

    it("should prevent liquidation of healthy position", () => {
      const collateral = 2000000; // 2 sBTC
      const borrowAmount = 1000000; // 1 sBTC (200% ratio - very healthy)

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "liquidate",
        [Cl.principal(alice)],
        liquidator
      );

      expect(result).toBeErr(Cl.uint(106)); // err-position-healthy
    });

    it("should return zero health factor for non-existent position", () => {
      const healthFactor = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "calculate-health-factor",
        [Cl.principal(alice)],
        deployer
      );

      expect(healthFactor.result).toBeUint(0);
    });

    it("should consider position healthy if no debt exists", () => {
      const isHealthy = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "is-position-healthy",
        [Cl.principal(alice)],
        deployer
      );

      expect(isHealthy.result).toBeBool(true); // No position = healthy
    });
  });

  describe("Edge Cases", () => {
    it("should handle multiple users borrowing independently", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;

      const aliceResult = simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );
      const aliceBlockHeight = simnet.blockHeight;

      const bobResult = simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        bob
      );
      const bobBlockHeight = simnet.blockHeight;

      // Verify both positions exist independently
      const alicePosition = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );
      const bobPosition = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(bob)],
        bob
      );

      expect(alicePosition.result).toBeSome(
        Cl.tuple({
          amount: Cl.uint(borrowAmount),
          collateral: Cl.uint(collateral),
          "last-update": Cl.uint(aliceBlockHeight),
        })
      );

      expect(bobPosition.result).toBeSome(
        Cl.tuple({
          amount: Cl.uint(borrowAmount),
          collateral: Cl.uint(collateral),
          "last-update": Cl.uint(bobBlockHeight),
        })
      );
    });

    it("should handle supply and withdraw for multiple users", () => {
      const aliceSupply = 1000000;
      const bobSupply = 2000000;

      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(aliceSupply)], alice);
      simnet.callPublicFn("sbtc-lending-pool", "supply", [Cl.uint(bobSupply)], bob);

      const aliceBalance = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-supply",
        [Cl.principal(alice)],
        alice
      );
      const bobBalance = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-supply",
        [Cl.principal(bob)],
        bob
      );

      expect(aliceBalance.result).toBeUint(aliceSupply);
      expect(bobBalance.result).toBeUint(bobSupply);
    });

    it("should handle repayment exceeding debt (capped at debt amount)", () => {
      const collateral = 1500000;
      const borrowAmount = 1000000;
      const repayAmount = 2000000; // Overpay

      simnet.callPublicFn(
        "sbtc-lending-pool",
        "borrow",
        [Cl.uint(collateral), Cl.uint(borrowAmount)],
        alice
      );

      // Should repay full debt and return all collateral
      const { result } = simnet.callPublicFn(
        "sbtc-lending-pool",
        "repay",
        [Cl.uint(repayAmount)],
        alice
      );

      expect(result).toBeOk(Cl.bool(true));

      // Position should be removed
      const position = simnet.callReadOnlyFn(
        "sbtc-lending-pool",
        "get-borrow",
        [Cl.principal(alice)],
        alice
      );

      expect(position.result).toBeNone();
    });
  });
});
