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