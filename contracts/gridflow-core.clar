;; GridFlow Energy Network - Core Contract
;; This contract manages the fundamental operations of the GridFlow energy trading platform
;; including user registration, energy listings, transaction matching, payment escrow, 
;; and settlement between energy producers and consumers.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-USER-ALREADY-REGISTERED u2)
(define-constant ERR-USER-NOT-REGISTERED u3)
(define-constant ERR-INVALID-ROLE u4)
(define-constant ERR-LISTING-NOT-FOUND u5)
(define-constant ERR-INSUFFICIENT-FUNDS u6)
(define-constant ERR-INVALID-AMOUNT u7)
(define-constant ERR-TRANSACTION-NOT-FOUND u8)
(define-constant ERR-ALREADY-VERIFIED u9)
(define-constant ERR-INSUFFICIENT-ENERGY u10)
(define-constant ERR-PROPOSAL-NOT-FOUND u11)
(define-constant ERR-ALREADY-VOTED u12)
(define-constant ERR-VOTING-CLOSED u13)
(define-constant ERR-INVALID-RATING u14)
(define-constant ERR-SELF-TRANSACTION u15)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PRODUCER-ROLE "producer")
(define-constant CONSUMER-ROLE "consumer")
(define-constant DUAL-ROLE "dual")
(define-constant PLATFORM-FEE-PERCENTAGE u2) ;; 2% platform fee
(define-constant MIN-ENERGY-AMOUNT u1)       ;; Minimum energy amount in kWh
(define-constant MAX-ENERGY-AMOUNT u10000)   ;; Maximum energy amount in kWh
(define-constant RATING-MIN u1)              ;; Minimum rating score
(define-constant RATING-MAX u5)              ;; Maximum rating score
(define-constant VOTING-DURATION u144)       ;; ~24 hours in blocks (assuming 10 min blocks)

;; Data Maps

;; Stores user information including role and reputation score
(define-map users 
  { address: principal } 
  { 
    role: (string-ascii 10),              ;; producer, consumer, or dual
    reputation: uint,                     ;; 0-100 reputation score
    total-energy-produced: uint,          ;; in kWh
    total-energy-consumed: uint,          ;; in kWh
    transaction-count: uint,              ;; number of completed transactions
    registered-at: uint                   ;; block height when registered
  }
)

;; Stores energy listings by producers
(define-map energy-listings
  { listing-id: uint }
  {
    producer: principal,
    energy-amount: uint,                  ;; in kWh
    price-per-kwh: uint,                  ;; in microSTX per kWh
    energy-type: (string-ascii 20),       ;; e.g., "solar", "wind", "hydro"
    location: (string-ascii 50),          ;; general location info
    expiration-height: uint,              ;; block height when listing expires
    active: bool                          ;; whether listing is still active
  }
)

;; Tracks pending and completed energy transactions
(define-map energy-transactions
  { transaction-id: uint }
  {
    listing-id: uint,
    seller: principal,
    buyer: principal,
    energy-amount: uint,
    total-price: uint,                    ;; in microSTX
    platform-fee: uint,                   ;; in microSTX
    status: (string-ascii 20),            ;; "pending", "completed", "cancelled"
    created-at: uint,                     ;; block height when created
    completed-at: uint,                   ;; block height when completed (0 if pending)
    delivery-verified: bool               ;; whether energy delivery was verified
  }
)

;; Stores user ratings after transactions
(define-map user-ratings
  { transaction-id: uint, rater: principal }
  {
    rated-user: principal,
    rating: uint,                         ;; 1-5 rating
    comment: (string-ascii 100),          ;; optional comment
    rated-at: uint                        ;; block height when rated
  }
)

;; Governance proposals for platform changes
(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    description: (string-ascii 500),
    changes: (string-ascii 500),          ;; technical description of changes
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 10),            ;; "active", "passed", "rejected"
    created-at: uint,
    expires-at: uint                      ;; when voting closes
  }
)

;; Tracks votes on governance proposals
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool,                           ;; true for yes, false for no
    voted-at: uint                        ;; block height when voted
  }
)

;; Data Variables

;; Counter for listing IDs
(define-data-var next-listing-id uint u1)

;; Counter for transaction IDs
(define-data-var next-transaction-id uint u1)

;; Counter for proposal IDs
(define-data-var next-proposal-id uint u1)

;; Total platform fees collected
(define-data-var total-fees-collected uint u0)

;; Total energy traded on the platform (kWh)
(define-data-var total-energy-traded uint u0)

;; Platform settings
(define-data-var platform-active bool true)

;; Private Functions

;; Calculate platform fee based on transaction amount
(define-private (calculate-fee (amount uint))
  (/ (* amount PLATFORM-FEE-PERCENTAGE) u100)
)

;; Check if user exists and return boolean
(define-private (is-user-registered (user principal))
  (is-some (map-get? users { address: user }))
)

;; Check if user has the required role
(define-private (has-role (user principal) (required-role (string-ascii 10)))
  (match (map-get? users { address: user })
    user-data (or 
                (is-eq (get role user-data) required-role)
                (is-eq (get role user-data) DUAL-ROLE)
                (and (is-eq required-role PRODUCER-ROLE) (is-eq (get role user-data) DUAL-ROLE))
                (and (is-eq required-role CONSUMER-ROLE) (is-eq (get role user-data) DUAL-ROLE)))
    false
  )
)

;; Update user reputation based on new rating
(define-private (update-reputation (user principal) (rating uint))
  (match (map-get? users { address: user })
    user-data 
      (let 
        (
          (current-reputation (get reputation user-data))
          (transaction-count (get transaction-count user-data))
          (new-count (+ transaction-count u1))
          (weighted-old-rep (* current-reputation transaction-count))
          (new-reputation (/ (+ weighted-old-rep (* rating u20)) new-count))
        )
        (map-set users 
          { address: user } 
          (merge user-data { 
            reputation: new-reputation, 
            transaction-count: new-count 
          })
        )
        true
      )
    false
  )
)

;; Read-Only Functions

;; Get user profile information
(define-read-only (get-user-info (user principal))
  (map-get? users { address: user })
)

;; Get energy listing details
(define-read-only (get-energy-listing (listing-id uint))
  (map-get? energy-listings { listing-id: listing-id })
)

;; Get transaction details
(define-read-only (get-transaction (transaction-id uint))
  (map-get? energy-transactions { transaction-id: transaction-id })
)

;; Get user rating for a transaction
(define-read-only (get-rating (transaction-id uint) (rater principal))
  (map-get? user-ratings { transaction-id: transaction-id, rater: rater })
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Check if user has voted on a proposal
(define-read-only (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? proposal-votes { proposal-id: proposal-id, voter: voter }))
)

;; Public Functions

;; Register as a user with specified role
(define-public (register-user (role (string-ascii 10)))
  (let 
    ((sender tx-sender))
    (asserts! (or 
                (is-eq role PRODUCER-ROLE) 
                (is-eq role CONSUMER-ROLE) 
                (is-eq role DUAL-ROLE)
              ) 
              (err ERR-INVALID-ROLE))
    (asserts! (not (is-user-registered sender)) (err ERR-USER-ALREADY-REGISTERED))
    
    (ok (map-set users 
      { address: sender } 
      { 
        role: role,
        reputation: u50,                  ;; Default starting reputation
        total-energy-produced: u0,
        total-energy-consumed: u0,
        transaction-count: u0,
        registered-at: block-height
      }
    ))
  )
)

;; Create a new energy listing
(define-public (create-energy-listing 
  (energy-amount uint) 
  (price-per-kwh uint) 
  (energy-type (string-ascii 20)) 
  (location (string-ascii 50))
  (expiration-blocks uint)
)
  (let 
    (
      (sender tx-sender)
      (listing-id (var-get next-listing-id))
      (expiration-height (+ block-height expiration-blocks))
    )
    ;; Check if user is registered and is a producer
    (asserts! (is-user-registered sender) (err ERR-USER-NOT-REGISTERED))
    (asserts! (has-role sender PRODUCER-ROLE) (err ERR-NOT-AUTHORIZED))
    
    ;; Validate listing parameters
    (asserts! (>= energy-amount MIN-ENERGY-AMOUNT) (err ERR-INVALID-AMOUNT))
    (asserts! (<= energy-amount MAX-ENERGY-AMOUNT) (err ERR-INVALID-AMOUNT))
    (asserts! (> price-per-kwh u0) (err ERR-INVALID-AMOUNT))
    (asserts! (> expiration-blocks u0) (err ERR-INVALID-AMOUNT))
    
    ;; Create the listing
    (map-set energy-listings
      { listing-id: listing-id }
      {
        producer: sender,
        energy-amount: energy-amount,
        price-per-kwh: price-per-kwh,
        energy-type: energy-type,
        location: location,
        expiration-height: expiration-height,
        active: true
      }
    )
    
    ;; Increment listing ID counter
    (var-set next-listing-id (+ listing-id u1))
    
    (ok listing-id)
  )
)

;; Purchase energy from a listing
(define-public (purchase-energy (listing-id uint) (energy-amount uint))
  (let 
    (
      (buyer tx-sender)
      (listing (unwrap! (map-get? energy-listings { listing-id: listing-id }) (err ERR-LISTING-NOT-FOUND)))
      (seller (get producer listing))
      (price-per-kwh (get price-per-kwh listing))
      (available-amount (get energy-amount listing))
      (is-active (get active listing))
      (expiration (get expiration-height listing))
      (total-price (* energy-amount price-per-kwh))
      (platform-fee (calculate-fee total-price))
      (payment-to-seller (- total-price platform-fee))
      (transaction-id (var-get next-transaction-id))
    )
    
    ;; Check if buyer is registered and is a consumer
    (asserts! (is-user-registered buyer) (err ERR-USER-NOT-REGISTERED))
    (asserts! (has-role buyer CONSUMER-ROLE) (err ERR-NOT-AUTHORIZED))
    
    ;; Check if listing is valid and active
    (asserts! is-active (err ERR-LISTING-NOT-FOUND))
    (asserts! (<= block-height expiration) (err ERR-LISTING-NOT-FOUND))
    (asserts! (<= energy-amount available-amount) (err ERR-INSUFFICIENT-ENERGY))
    (asserts! (> energy-amount u0) (err ERR-INVALID-AMOUNT))
    
    ;; Prevent self-transactions
    (asserts! (not (is-eq buyer seller)) (err ERR-SELF-TRANSACTION))
    
    ;; Transfer payment from buyer to contract (escrow)
    (asserts! (>= (stx-get-balance buyer) total-price) (err ERR-INSUFFICIENT-FUNDS))
    
    ;; Create the transaction record
    (try! (stx-transfer? total-price buyer (as-contract tx-sender)))
    
    (map-set energy-transactions
      { transaction-id: transaction-id }
      {
        listing-id: listing-id,
        seller: seller,
        buyer: buyer,
        energy-amount: energy-amount,
        total-price: total-price,
        platform-fee: platform-fee,
        status: "pending",
        created-at: block-height,
        completed-at: u0,
        delivery-verified: false
      }
    )
    
    ;; Update listing with remaining energy
    (if (is-eq energy-amount available-amount)
      (map-set energy-listings
        { listing-id: listing-id }
        (merge listing { 
          energy-amount: u0,
          active: false
        })
      )
      (map-set energy-listings
        { listing-id: listing-id }
        (merge listing { 
          energy-amount: (- available-amount energy-amount)
        })
      )
    )
    
    ;; Increment transaction ID counter
    (var-set next-transaction-id (+ transaction-id u1))
    
    (ok transaction-id)
  )
)

;; Verify energy delivery and complete transaction
(define-public (confirm-energy-delivery (transaction-id uint))
  (let 
    (
      (sender tx-sender)
      (tx (unwrap! (map-get? energy-transactions { transaction-id: transaction-id }) (err ERR-TRANSACTION-NOT-FOUND)))
      (buyer (get buyer tx))
      (seller (get seller tx))
      (total-price (get total-price tx))
      (platform-fee (get platform-fee tx))
      (seller-amount (- total-price platform-fee))
      (energy-amount (get energy-amount tx))
    )
    
    ;; Only the buyer can confirm delivery
    (asserts! (is-eq sender buyer) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-eq (get status tx) "pending") (err ERR-ALREADY-VERIFIED))
    
    ;; Transfer funds from escrow to seller and platform fee to contract owner
    (as-contract 
      (begin
        (try! (stx-transfer? seller-amount tx-sender seller))
        (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))
      )
    )
    
    ;; Update transaction status
    (map-set energy-transactions
      { transaction-id: transaction-id }
      (merge tx {
        status: "completed",
        completed-at: block-height,
        delivery-verified: true
      })
    )
    
    ;; Update platform statistics
    (var-set total-fees-collected (+ (var-get total-fees-collected) platform-fee))
    (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
    
    ;; Update user statistics
    (match (map-get? users { address: seller })
      seller-data 
        (map-set users 
          { address: seller } 
          (merge seller-data { 
            total-energy-produced: (+ (get total-energy-produced seller-data) energy-amount)
          })
        )
      false
    )
    
    (match (map-get? users { address: buyer })
      buyer-data 
        (map-set users 
          { address: buyer } 
          (merge buyer-data { 
            total-energy-consumed: (+ (get total-energy-consumed buyer-data) energy-amount)
          })
        )
      false
    )
    
    (ok true)
  )
)

;; Rate another user after a transaction
(define-public (rate-user (transaction-id uint) (rating uint) (comment (string-ascii 100)))
  (let 
    (
      (rater tx-sender)
      (tx (unwrap! (map-get? energy-transactions { transaction-id: transaction-id }) (err ERR-TRANSACTION-NOT-FOUND)))
      (buyer (get buyer tx))
      (seller (get seller tx))
      (rated-user (if (is-eq rater buyer) seller buyer))
    )
    
    ;; Check if transaction is completed and rater was involved
    (asserts! (is-eq (get status tx) "completed") (err ERR-TRANSACTION-NOT-FOUND))
    (asserts! (or (is-eq rater buyer) (is-eq rater seller)) (err ERR-NOT-AUTHORIZED))
    (asserts! (and (>= rating RATING-MIN) (<= rating RATING-MAX)) (err ERR-INVALID-RATING))
    
    ;; Check if user has already rated this transaction
    (asserts! (is-none (map-get? user-ratings { transaction-id: transaction-id, rater: rater })) (err ERR-ALREADY-VOTED))
    
    ;; Record the rating
    (map-set user-ratings
      { transaction-id: transaction-id, rater: rater }
      {
        rated-user: rated-user,
        rating: rating,
        comment: comment,
        rated-at: block-height
      }
    )
    
    ;; Update user reputation
    (update-reputation rated-user rating)
    
    (ok true)
  )
)

;; Cancel a listing by the producer
(define-public (cancel-listing (listing-id uint))
  (let 
    (
      (sender tx-sender)
      (listing (unwrap! (map-get? energy-listings { listing-id: listing-id }) (err ERR-LISTING-NOT-FOUND)))
      (producer (get producer listing))
      (is-active (get active listing))
    )
    
    ;; Check if sender is the listing producer
    (asserts! (is-eq sender producer) (err ERR-NOT-AUTHORIZED))
    (asserts! is-active (err ERR-LISTING-NOT-FOUND))
    
    ;; Mark listing as inactive
    (map-set energy-listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    
    (ok true)
  )
)

;; Create a governance proposal
(define-public (create-proposal (description (string-ascii 500)) (changes (string-ascii 500)))
  (let 
    (
      (proposer tx-sender)
      (proposal-id (var-get next-proposal-id))
      (expires-at (+ block-height VOTING-DURATION))
    )
    
    ;; Check if proposer is a registered user
    (asserts! (is-user-registered proposer) (err ERR-USER-NOT-REGISTERED))
    
    ;; Create the proposal
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: proposer,
        description: description,
        changes: changes,
        votes-for: u0,
        votes-against: u0,
        status: "active",
        created-at: block-height,
        expires-at: expires-at
      }
    )
    
    ;; Increment proposal ID counter
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Vote on a governance proposal
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let 
    (
      (voter tx-sender)
      (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) (err ERR-PROPOSAL-NOT-FOUND)))
      (status (get status proposal))
      (expires-at (get expires-at proposal))
      (votes-for (get votes-for proposal))
      (votes-against (get votes-against proposal))
    )
    
    ;; Check if voter is registered
    (asserts! (is-user-registered voter) (err ERR-USER-NOT-REGISTERED))
    
    ;; Check if proposal is still active and voting is open
    (asserts! (is-eq status "active") (err ERR-VOTING-CLOSED))
    (asserts! (<= block-height expires-at) (err ERR-VOTING-CLOSED))
    
    ;; Check if voter has already voted
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })) (err ERR-ALREADY-VOTED))
    
    ;; Record the vote
    (map-set proposal-votes
      { proposal-id: proposal-id, voter: voter }
      {
        vote: vote,
        voted-at: block-height
      }
    )
    
    ;; Update proposal vote count
    (map-set governance-proposals
      { proposal-id: proposal-id }
      (merge proposal { 
        votes-for: (if vote (+ votes-for u1) votes-for), 
        votes-against: (if vote votes-against (+ votes-against u1)) 
      })
    )
    
    (ok true)
  )
)

;; Close voting on a proposal and finalize result
(define-public (finalize-proposal (proposal-id uint))
  (let 
    (
      (sender tx-sender)
      (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) (err ERR-PROPOSAL-NOT-FOUND)))
      (status (get status proposal))
      (expires-at (get expires-at proposal))
      (votes-for (get votes-for proposal))
      (votes-against (get votes-against proposal))
      (new-status (if (> votes-for votes-against) "passed" "rejected"))
    )
    
    ;; Check if proposal is active and voting period has ended
    (asserts! (is-eq status "active") (err ERR-VOTING-CLOSED))
    (asserts! (>= block-height expires-at) (err ERR-VOTING-CLOSED))
    
    ;; Update proposal status
    (map-set governance-proposals
      { proposal-id: proposal-id }
      (merge proposal { status: new-status })
    )
    
    (ok true)
  )
)

;; Update platform settings (restricted to contract owner)
(define-public (update-platform-status (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
    (var-set platform-active active)
    (ok true)
  )
)