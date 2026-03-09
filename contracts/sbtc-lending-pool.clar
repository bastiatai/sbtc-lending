;; sBTC Lending Pool
;; A DeFi protocol for lending and borrowing sBTC with collateralization

;; Constants
(define-constant contract-owner tx-sender)
(define-constant contract-principal (as-contract tx-sender))
(define-constant sbtc-token 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-insufficient-collateral (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-position-not-found (err u104))
(define-constant err-unhealthy-position (err u105))
(define-constant err-position-healthy (err u106))

;; Protocol parameters
(define-constant collateral-ratio u150) ;; 150% collateralization required
(define-constant liquidation-ratio u125) ;; 125% threshold for liquidation
(define-constant liquidation-penalty u10) ;; 10% penalty on liquidation
(define-constant interest-rate u5) ;; 5% annual interest (simplified)

;; Data variables
(define-data-var total-supplied uint u0)
(define-data-var total-borrowed uint u0)

;; Data maps
(define-map supplies principal uint)
(define-map borrows
  principal
  {
    amount: uint,
    collateral: uint,
    last-update: uint
  }
)

;; Read-only functions
(define-read-only (get-supply (user principal))
  (default-to u0 (map-get? supplies user))
)

(define-read-only (get-borrow (user principal))
  (map-get? borrows user)
)

(define-read-only (get-total-supplied)
  (var-get total-supplied)
)

(define-read-only (get-total-borrowed)
  (var-get total-borrowed)
)

(define-read-only (calculate-max-borrow (collateral-amount uint))
  (/ (* collateral-amount u100) collateral-ratio)
)

(define-read-only (calculate-health-factor (user principal))
  (match (map-get? borrows user)
    position
      (if (is-eq (get amount position) u0)
        u0 ;; No debt, health factor not applicable
        (/ (* (get collateral position) u100) (get amount position))
      )
    u0 ;; No position
  )
)

(define-read-only (is-position-healthy (user principal))
  (let ((health-factor (calculate-health-factor user)))
    (or (is-eq health-factor u0) (>= health-factor liquidation-ratio))
  )
)

;; Public functions

;; Supply sBTC to the pool to earn interest
(define-public (supply (amount uint))
  (let
    (
      (current-supply (get-supply tx-sender))
    )
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer sBTC from user to contract
    (try! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer amount tx-sender contract-principal none))

    ;; Update user's supply
    (map-set supplies tx-sender (+ current-supply amount))

    ;; Update total supplied
    (var-set total-supplied (+ (var-get total-supplied) amount))

    (ok true)
  )
)

;; Withdraw supplied sBTC
(define-public (withdraw (amount uint))
  (let
    (
      (current-supply (get-supply tx-sender))
      (recipient tx-sender)
    )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= current-supply amount) err-insufficient-balance)

    ;; Update user's supply
    (map-set supplies tx-sender (- current-supply amount))

    ;; Update total supplied
    (var-set total-supplied (- (var-get total-supplied) amount))

    ;; Transfer sBTC from contract to user
    ;; Inside as-contract, tx-sender is the contract (correct sender); recipient is the original caller
    (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      transfer amount tx-sender recipient none)))

    (ok true)
  )
)

;; Deposit collateral and borrow sBTC
(define-public (borrow (collateral-amount uint) (borrow-amount uint))
  (let
    (
      (max-borrow (calculate-max-borrow collateral-amount))
      (existing-position (get-borrow tx-sender))
      (recipient tx-sender)
    )
    (asserts! (> collateral-amount u0) err-invalid-amount)
    (asserts! (> borrow-amount u0) err-invalid-amount)
    (asserts! (<= borrow-amount max-borrow) err-insufficient-collateral)

    ;; Transfer collateral from user to contract
    (try! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer collateral-amount tx-sender contract-principal none))

    ;; Handle existing position or create new one
    (match existing-position
      position
        ;; Update existing position (accumulate both collateral and debt)
        (begin
          (map-set borrows tx-sender {
            amount: (+ (get amount position) borrow-amount),
            collateral: (+ (get collateral position) collateral-amount),
            last-update: stacks-block-height
          })
          (var-set total-borrowed (+ (var-get total-borrowed) borrow-amount))
        )
      ;; Create new position
      (begin
        (map-set borrows tx-sender {
          amount: borrow-amount,
          collateral: collateral-amount,
          last-update: stacks-block-height
        })
        (var-set total-borrowed (+ (var-get total-borrowed) borrow-amount))
      )
    )

    ;; Transfer borrowed sBTC from contract to user
    ;; Inside as-contract, tx-sender is the contract (correct sender); recipient is the original caller
    (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      transfer borrow-amount tx-sender recipient none)))

    (ok true)
  )
)

;; Repay borrowed sBTC
(define-public (repay (amount uint))
  (let
    (
      (position (unwrap! (get-borrow tx-sender) err-position-not-found))
      (repay-amount (if (<= amount (get amount position))
                      amount
                      (get amount position)))
      (new-debt (- (get amount position) repay-amount))
      (collateral-to-return (/ (* (get collateral position) repay-amount) (get amount position)))
      (remaining-collateral (- (get collateral position) collateral-to-return))
      (recipient tx-sender)
    )
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer repayment from user to contract
    (try! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer repay-amount tx-sender contract-principal none))

    ;; Update position
    (if (is-eq repay-amount (get amount position))
      ;; Full repayment - return all collateral
      (begin
        ;; Transfer collateral back to user
        ;; Inside as-contract, tx-sender is the contract (correct sender); recipient is the original caller
        (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
          transfer (get collateral position) tx-sender recipient none)))

        ;; Remove position
        (map-delete borrows tx-sender)
        (var-set total-borrowed (- (var-get total-borrowed) repay-amount))
        (ok true)
      )
      ;; Partial repayment - reduce debt proportionally
      (begin
        ;; Transfer proportional collateral back to user
        ;; Inside as-contract, tx-sender is the contract (correct sender); recipient is the original caller
        (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
          transfer collateral-to-return tx-sender recipient none)))

        ;; Update position
        (map-set borrows tx-sender {
          amount: new-debt,
          collateral: remaining-collateral,
          last-update: stacks-block-height
        })
        (var-set total-borrowed (- (var-get total-borrowed) repay-amount))
        (ok true)
      )
    )
  )
)

;; Liquidate an unhealthy position
;;
;; Fix: The original code only gave the liquidator the penalty amount (10% of collateral),
;; which is less than the debt they repay -- making liquidation unprofitable and broken.
;;
;; Correct model:
;;   liquidator pays: debt
;;   liquidator receives: debt + penalty (debt repayment value + 10% bonus)
;;   surplus (collateral - debt - penalty) is returned to the borrower
;;
;; Example: collateral=150, debt=100, penalty=10% of debt=10
;;   liquidator pays 100, receives 110 (net +10 profit)
;;   borrower receives 40 (150 - 100 - 10) surplus
(define-public (liquidate (borrower principal))
  (let
    (
      (position (unwrap! (get-borrow borrower) err-position-not-found))
      (health-factor (calculate-health-factor borrower))
      (debt (get amount position))
      (collateral (get collateral position))
      ;; Penalty is 10% of the debt amount, paid as bonus to liquidator
      (penalty-amount (/ (* debt liquidation-penalty) u100))
      ;; Liquidator receives debt value + penalty bonus in collateral
      (liquidator-reward (+ debt penalty-amount))
      ;; Any remaining collateral after covering debt + penalty goes back to borrower
      (borrower-surplus (if (> collateral liquidator-reward)
                           (- collateral liquidator-reward)
                           u0))
      (recipient tx-sender)
    )
    (asserts! (< health-factor liquidation-ratio) err-position-healthy)
    ;; Ensure there is enough collateral to cover the liquidator reward
    (asserts! (>= collateral liquidator-reward) err-insufficient-collateral)

    ;; Liquidator repays the debt
    (try! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer debt tx-sender contract-principal none))

    ;; Transfer liquidator reward (debt + 10% penalty) to liquidator
    ;; Inside as-contract, tx-sender is the contract (correct sender); recipient is the original caller (liquidator)
    (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
      transfer liquidator-reward tx-sender recipient none)))

    ;; Return surplus collateral to borrower (if any)
    (if (> borrower-surplus u0)
      (try! (as-contract (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
        transfer borrower-surplus tx-sender borrower none)))
      true
    )

    ;; Remove position
    (map-delete borrows borrower)
    (var-set total-borrowed (- (var-get total-borrowed) debt))

    (ok true)
  )
)
