;; sBTC Lending Pool
;; A DeFi protocol for lending and borrowing sBTC with collateralization

;; Constants
(define-constant contract-owner tx-sender)
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

;; Private helper functions
(define-private (get-contract-principal)
  (as-contract? () tx-sender)
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
      (contract-principal (unwrap! (get-contract-principal) (err u999)))
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

    ;; Transfer sBTC from contract to user (requires as-contract? with allowances)
    (unwrap! (as-contract? ((with-ft 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token "sbtc-token" amount))
               (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer amount tx-sender recipient none) (err u998)))
             (err u999))

    (ok true)
  )
)

;; Deposit collateral and borrow sBTC
(define-public (borrow (collateral-amount uint) (borrow-amount uint))
  (let
    (
      (max-borrow (calculate-max-borrow collateral-amount))
      (existing-position (get-borrow tx-sender))
      (contract-principal (unwrap! (get-contract-principal) (err u999)))
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

    ;; Transfer borrowed sBTC from contract to user (requires as-contract? with allowances)
    (unwrap! (as-contract? ((with-ft 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token "sbtc-token" borrow-amount))
               (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer borrow-amount tx-sender recipient none) (err u998)))
             (err u999))

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
      (contract-principal (unwrap! (get-contract-principal) (err u999)))
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
        (unwrap! (as-contract? ((with-ft 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token "sbtc-token" (get collateral position)))
                   (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer (get collateral position) tx-sender recipient none) (err u998)))
                 (err u999))

        ;; Remove position
        (map-delete borrows tx-sender)
        (var-set total-borrowed (- (var-get total-borrowed) repay-amount))
        (ok true)
      )
      ;; Partial repayment - reduce debt proportionally
      (begin
        ;; Transfer proportional collateral back to user
        (unwrap! (as-contract? ((with-ft 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token "sbtc-token" collateral-to-return))
                   (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer collateral-to-return tx-sender recipient none) (err u998)))
                 (err u999))

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
(define-public (liquidate (borrower principal))
  (let
    (
      (position (unwrap! (get-borrow borrower) err-position-not-found))
      (health-factor (calculate-health-factor borrower))
      (debt (get amount position))
      (collateral (get collateral position))
      (penalty-amount (/ (* collateral liquidation-penalty) u100))
      (liquidator-reward penalty-amount)
      (remaining-collateral (- collateral penalty-amount))
      (contract-principal (unwrap! (get-contract-principal) (err u999)))
      (recipient tx-sender)
    )
    (asserts! (< health-factor liquidation-ratio) err-position-healthy)

    ;; Liquidator must repay the debt
    (try! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer debt tx-sender contract-principal none))

    ;; Transfer collateral to liquidator (with penalty bonus)
    (unwrap! (as-contract? ((with-ft 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token "sbtc-token" collateral))
               (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer collateral tx-sender recipient none) (err u998)))
             (err u999))

    ;; Remove position
    (map-delete borrows borrower)
    (var-set total-borrowed (- (var-get total-borrowed) debt))

    (ok true)
  )
)
