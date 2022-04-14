;; CITYCOINS TOKEN CONTRACT
;; Version 2.0

;; CONTRACT OWNER

(define-constant CONTRACT_OWNER tx-sender)

;; TRAIT DEFINITIONS

(impl-trait .citycoin-token-trait.citycoin-token)
(use-trait coreTrait .citycoin-core-trait.citycoin-core)

;; ERROR CODES

(define-constant ERR_UNAUTHORIZED u2000)
(define-constant ERR_TOKEN_NOT_ACTIVATED u2001)
(define-constant ERR_TOKEN_ALREADY_ACTIVATED u2002)
(define-constant ERR_V1_BALANCE_NOT_FOUND u2003)

;; SIP-010 DEFINITION

(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
;; testnet: (impl-trait 'STR8P3RD1EHA8AA37ERSSSZSWKS9T2GYQFGXNA4C.sip-010-trait-ft-standard.sip-010-trait)

(define-fungible-token citycoins)

(define-constant DECIMALS u6)

;; SIP-010 FUNCTIONS

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq from tx-sender) (err ERR_UNAUTHORIZED))
    (if (is-some memo)
      (print memo)
      none
    )
    (ft-transfer? citycoins amount from to)
  )
)

(define-read-only (get-name)
  (ok "citycoins")
)

(define-read-only (get-symbol)
  (ok "CYCN")
)

(define-read-only (get-decimals)
  (ok DECIMALS)
)

(define-read-only (get-balance (user principal))
  (ok (ft-get-balance citycoins user))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply citycoins))
)

(define-read-only (get-token-uri)
  (ok (var-get tokenUri))
)

;; TOKEN CONFIGURATION

;; define bonus period and initial epoch length
(define-constant TOKEN_BONUS_PERIOD u10000)
(define-constant TOKEN_EPOCH_LENGTH u25000)

;; REMOVE how many blocks until the next halving occurs
;; REMOVE (define-constant TOKEN_HALVING_BLOCKS u210000)

;; store block height at each halving, set by register-user in core contract 
(define-data-var coinbaseThreshold1 uint u0)
(define-data-var coinbaseThreshold2 uint u0)
(define-data-var coinbaseThreshold3 uint u0)
(define-data-var coinbaseThreshold4 uint u0)
(define-data-var coinbaseThreshold5 uint u0)

;; once activated, thresholds cannot be updated again
(define-data-var tokenActivated bool false)

;; core contract states
(define-constant STATE_DEPLOYED u0)
(define-constant STATE_ACTIVE u1)
(define-constant STATE_INACTIVE u2)

;; one-time function to activate the token
(define-public (activate-token (coreContract principal) (stacksHeight uint))
  (let
    (
      (coreContractMap (try! (contract-call? .citycoin-auth get-core-contract-info coreContract)))
    )
    (asserts! (is-eq (get state coreContractMap) STATE_ACTIVE) (err ERR_UNAUTHORIZED))
    (asserts! (not (var-get tokenActivated)) (err ERR_TOKEN_ALREADY_ACTIVATED))
    (var-set tokenActivated true)
    (var-set coinbaseThreshold1 (+ stacksHeight TOKEN_BONUS_PERIOD TOKEN_EPOCH_LENGTH))        ;; 35,000 blocks
    (var-set coinbaseThreshold2 (+ stacksHeight TOKEN_BONUS_PERIOD (* u2 TOKEN_EPOCH_LENGTH))) ;; 85,000 blocks
    (var-set coinbaseThreshold3 (+ stacksHeight TOKEN_BONUS_PERIOD (* u3 TOKEN_EPOCH_LENGTH))) ;; 185,000 blocks
    (var-set coinbaseThreshold4 (+ stacksHeight TOKEN_BONUS_PERIOD (* u4 TOKEN_EPOCH_LENGTH))) ;; 385,000 blocks
    (var-set coinbaseThreshold5 (+ stacksHeight TOKEN_BONUS_PERIOD (* u5 TOKEN_EPOCH_LENGTH))) ;; 785,000 blocks
    (ok true)
  )
)

;; return coinbase thresholds if token activated
(define-read-only (get-coinbase-thresholds)
  (let
    (
      (activated (var-get tokenActivated))
    )
    (asserts! activated (err ERR_TOKEN_NOT_ACTIVATED))
    (ok {
      coinbaseThreshold1: (var-get coinbaseThreshold1),
      coinbaseThreshold2: (var-get coinbaseThreshold2),
      coinbaseThreshold3: (var-get coinbaseThreshold3),
      coinbaseThreshold4: (var-get coinbaseThreshold4),
      coinbaseThreshold5: (var-get coinbaseThreshold5)
    })
  )
)

;; CONVERSION

(define-public (convert-to-v2)
  (let
    (
      (balanceV1 (unwrap! (contract-call? .citycoin-token get-balance tx-sender) (err ERR_V1_BALANCE_NOT_FOUND)))
    )
    ;; verify positive balance
    (asserts! (> balanceV1 u0) (err ERR_V1_BALANCE_NOT_FOUND))
    ;; burn old
    ;; TODO: MIA will need to call from core contract
    (try! (contract-call? .citycoin-token burn balanceV1 tx-sender))
    ;; create new
    (ft-mint? citycoins (* balanceV1 DECIMALS) tx-sender)
  )
)

;; UTILITIES

(define-data-var tokenUri (optional (string-utf8 256)) (some u"https://cdn.citycoins.co/metadata/citycoin.json"))

;; set token URI to new value, only accessible by Auth
(define-public (set-token-uri (newUri (optional (string-utf8 256))))
  (begin
    (asserts! (is-authorized-auth) (err ERR_UNAUTHORIZED))
    (ok (var-set tokenUri newUri))
  )
)

;; mint new tokens, only accessible by a Core contract
(define-public (mint (amount uint) (recipient principal))
  (let
    (
      (coreContract (try! (contract-call? .citycoin-auth get-core-contract-info contract-caller)))
    )
    (ft-mint? citycoins amount recipient)
  )
)

(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (is-eq tx-sender owner) (err ERR_UNAUTHORIZED))
    (ft-burn? citycoins amount owner)
  )
)

;; checks if caller is Auth contract
(define-private (is-authorized-auth)
  (is-eq contract-caller .citycoin-auth)
)

;; SEND-MANY

(define-public (send-many (recipients (list 200 { to: principal, amount: uint, memo: (optional (buff 34)) })))
  (fold check-err
    (map send-token recipients)
    (ok true)
  )
)

(define-private (check-err (result (response bool uint)) (prior (response bool uint)))
  (match prior ok-value
    result
    err-value (err err-value)
  )
)

(define-private (send-token (recipient { to: principal, amount: uint, memo: (optional (buff 34)) }))
  (send-token-with-memo (get amount recipient) (get to recipient) (get memo recipient))
)

(define-private (send-token-with-memo (amount uint) (to principal) (memo (optional (buff 34))))
  (let
    (
      (transferOk (try! (transfer amount tx-sender to memo)))
    )
    (ok transferOk)
  )
)
