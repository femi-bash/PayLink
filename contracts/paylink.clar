;; PayLink Protocol - Smart Payment Request Infrastructure
;;
;; Title: PayLink Protocol - Next-Generation Payment Request System
;;
;; Summary: 
;; Revolutionary payment infrastructure that transforms how digital payments 
;; are requested, tracked, and settled. PayLink creates secure, time-bound 
;; payment requests with automatic state management and real-time settlement 
;; verification using sBTC on the Stacks blockchain.
;;
;; Description:
;; PayLink Protocol establishes a new standard for digital payment requests 
;; by combining the security of Bitcoin with the programmability of smart 
;; contracts. The protocol enables merchants, service providers, and individuals 
;; to generate cryptographically secure payment links with built-in escrow-like 
;; functionality, automatic expiration, and transparent settlement tracking. 
;; Each PayLink request is immutably recorded on-chain with complete audit trails, 
;; making it perfect for professional invoicing, e-commerce integrations, and 
;; peer-to-peer transactions requiring verifiable payment proof.

;; ERROR CONSTANTS
(define-constant ERR-TAG-EXISTS u100)
(define-constant ERR-NOT-PENDING u101)
(define-constant ERR-INSUFFICIENT-FUNDS u102)
(define-constant ERR-NOT-FOUND u103)
(define-constant ERR-UNAUTHORIZED u104)
(define-constant ERR-EXPIRED u105)
(define-constant ERR-INVALID-AMOUNT u106)
(define-constant ERR-EMPTY-MEMO u107)
(define-constant ERR-MAX-EXPIRATION-EXCEEDED u108)
(define-constant ERR-INVALID-RECIPIENT u109)
(define-constant ERR-SELF-PAYMENT u110)

;; PAYMENT STATE DEFINITIONS
(define-constant STATE-PENDING "pending")
(define-constant STATE-PAID "paid")
(define-constant STATE-EXPIRED "expired")
(define-constant STATE-CANCELED "canceled")

;; PROTOCOL CONFIGURATION
;; sBTC token contract integration (mainnet deployment ready)
(define-constant SBTC-CONTRACT 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token)

;; Protocol administrator for emergency controls
(define-constant CONTRACT-DEPLOYER tx-sender)

;; Security parameters
(define-constant MAX-EXPIRATION-BLOCKS u4320) ;; 30 days maximum (~10 min/block)
(define-constant MAX-TAGS-PER-USER u100) ;; Efficient indexing limit
(define-constant MIN-PAYMENT-AMOUNT u1000) ;; Anti-spam threshold (0.00001 sBTC)

;; DATA STRUCTURES

;; Primary payment request storage
(define-map payment-tags
  { id: uint }
  {
    creator: principal,
    recipient: principal,
    amount: uint,
    created-at: uint,
    expires-at: uint,
    memo: (optional (string-ascii 256)),
    state: (string-ascii 16),
    payment-tx: (optional (buff 32)),
    payment-block: (optional uint),
  }
)

;; Creator-based indexing for efficient queries
(define-map creator-index
  { creator: principal }
  {
    tag-ids: (list 100 uint),
    count: uint,
  }
)

;; Recipient-based indexing for payment tracking  
(define-map recipient-index
  { recipient: principal }
  {
    tag-ids: (list 100 uint),
    count: uint,
  }
)

;; Protocol analytics and metrics
(define-map contract-stats
  { key: (string-ascii 32) }
  { value: uint }
)

;; STATE VARIABLES
(define-data-var tag-counter uint u0)
(define-data-var contract-paused bool false)

;; INTERNAL UTILITY FUNCTIONS

;; Index management for creator tracking
(define-private (add-to-creator-index
    (creator principal)
    (tag-id uint)
  )
  (let (
      (current-data (default-to {
        tag-ids: (list),
        count: u0,
      }
        (map-get? creator-index { creator: creator })
      ))
      (current-list (get tag-ids current-data))
      (current-count (get count current-data))
    )
    (match (as-max-len? (append current-list tag-id) u100)
      new-list (begin
        (map-set creator-index { creator: creator } {
          tag-ids: new-list,
          count: (+ current-count u1),
        })
        true
      )
      false
    )
  )
)

;; Index management for recipient tracking
(define-private (add-to-recipient-index
    (recipient principal)
    (tag-id uint)
  )
  (let (
      (current-data (default-to {
        tag-ids: (list),
        count: u0,
      }
        (map-get? recipient-index { recipient: recipient })
      ))
      (current-list (get tag-ids current-data))
      (current-count (get count current-data))
    )
    (match (as-max-len? (append current-list tag-id) u100)
      new-list (begin
        (map-set recipient-index { recipient: recipient } {
          tag-ids: new-list,
          count: (+ current-count u1),
        })
        true
      )
      false
    )
  )
)

;; Expiration validation logic
(define-private (is-tag-expired (expires-at uint))
  (>= stacks-block-height expires-at)
)

;; Analytics helper for protocol metrics
(define-private (increment-stat (stat-key (string-ascii 32)))
  (let ((current-value (default-to u0 (get value (map-get? contract-stats { key: stat-key })))))
    (map-set contract-stats { key: stat-key } { value: (+ current-value u1) })
  )
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieve current payment request counter
(define-read-only (get-tag-counter)
  (var-get tag-counter)
)

;; Fetch specific payment request details
(define-read-only (get-payment-tag (tag-id uint))
  (match (map-get? payment-tags { id: tag-id })
    tag-data (ok tag-data)
    (err ERR-NOT-FOUND)
  )
)

;; Query all payment requests created by user
(define-read-only (get-creator-tags (creator principal))
  (match (map-get? creator-index { creator: creator })
    index-data (ok (get tag-ids index-data))
    (ok (list))
  )
)

;; Query all payment requests for recipient
(define-read-only (get-recipient-tags (recipient principal))
  (match (map-get? recipient-index { recipient: recipient })
    index-data (ok (get tag-ids index-data))
    (ok (list))
  )
)

;; Validate if payment request can be expired
(define-read-only (can-expire-tag (tag-id uint))
  (match (map-get? payment-tags { id: tag-id })
    tag-data (if (and
        (is-eq (get state tag-data) STATE-PENDING)
        (is-tag-expired (get expires-at tag-data))
      )
      (ok true)
      (ok false)
    )
    (err ERR-NOT-FOUND)
  )
)

;; Retrieve protocol analytics
(define-read-only (get-contract-stats (stat-key (string-ascii 32)))
  (match (map-get? contract-stats { key: stat-key })
    stat-data (ok (get value stat-data))
    (ok u0)
  )
)

;; Check protocol operational status
(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

;; Batch query multiple payment requests
(define-read-only (get-multiple-tags (tag-ids (list 20 uint)))
  (ok (map get-tag-safe tag-ids))
)

;; Safe tag retrieval for batch operations
(define-private (get-tag-safe (tag-id uint))
  (map-get? payment-tags { id: tag-id })
)

;; CORE PAYMENT FUNCTIONS

;; Create new payment request with full validation
(define-public (create-payment-tag
    (recipient principal)
    (amount uint)
    (expires-in-blocks uint)
    (memo (optional (string-ascii 256)))
  )
  (let (
      (new-tag-id (+ (var-get tag-counter) u1))
      (expiration-block (+ stacks-block-height expires-in-blocks))
    )
    (begin
      ;; Protocol state validation
      (asserts! (not (var-get contract-paused)) (err ERR-UNAUTHORIZED))
      ;; Input parameter validation
      (asserts! (>= amount MIN-PAYMENT-AMOUNT) (err ERR-INVALID-AMOUNT))
      (asserts! (<= expires-in-blocks MAX-EXPIRATION-BLOCKS)
        (err ERR-MAX-EXPIRATION-EXCEEDED)
      )
      (asserts! (> expires-in-blocks u0) (err ERR-INVALID-AMOUNT))
      (asserts! (not (is-eq tx-sender recipient)) (err ERR-SELF-PAYMENT))
      ;; Memo validation if provided
      (match memo
        some-memo (asserts! (> (len some-memo) u0) (err ERR-EMPTY-MEMO))
        true
      )
      ;; Create payment request record
      (map-set payment-tags { id: new-tag-id } {
        creator: tx-sender,
        recipient: recipient,
        amount: amount,
        created-at: stacks-block-height,
        expires-at: expiration-block,
        memo: memo,
        state: STATE-PENDING,
        payment-tx: none,
        payment-block: none,
      })
      ;; Update global counter
      (var-set tag-counter new-tag-id)
      ;; Update indexing structures
      (add-to-creator-index tx-sender new-tag-id)
      (add-to-recipient-index recipient new-tag-id)
      ;; Update protocol metrics
      (increment-stat "tags-created")
      ;; Broadcast creation event
      (print {
        event: "payment-tag-created",
        tag-id: new-tag-id,
        creator: tx-sender,
        recipient: recipient,
        amount: amount,
        expires-at: expiration-block,
        memo: memo,
      })
      (ok new-tag-id)
    )
  )
)