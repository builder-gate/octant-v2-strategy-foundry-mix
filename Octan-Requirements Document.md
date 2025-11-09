# Requirements Document

## Introduction

This feature introduces a **Reputation-Gated Builder Vault** (RGBV) that allocates yield from a Yield Donating Strategy (YDS) only to wallets that can prove meaningful contribution to the Web3 ecosystem.

The core innovation lies in using **verifiable reputation mechanisms**—such as zkProofs of GitHub contributions, attestations from platforms like Self or Otterspace, and Builder Badges—to gate yield distribution. This vault is not intended for passive capital providers, but rather for **active, high-signal contributors**, such as developers, maintainers, and technical content creators.

The source of yield originates from **fees collected via Uniswap v4 hooks**, configured in custom pools (e.g. `Builder/ETH`). These hooks redirect protocol fees into an Octant-compatible vault following the ERC-4626 standard. Yield is distributed through a Tokenized Allocation Mechanism (TAM) that validates proofs of reputation and dynamically scales rewards based on contributor impact (via a score multiplier model).

This system enables DAOs, protocols, or even public DeFi apps to **fund builders programmatically**, with no application forms, governance votes or manual selection.

## Requirements

### Requirement 1: Yield Source via Uniswap v4 Hook
**User Story:**  
As a protocol owner, I want a Uniswap v4 Hook to redirect a percentage of swap fees to a vault, so that I can transform DEX activity into sustainable funding for builders.

#### Acceptance Criteria
1. WHEN a swap is executed in a pool with the Hook active THEN the system SHALL redirect the hook fee to a designated YDS vault address  
2. IF the pool contains BuilderToken THEN the hook SHALL use the BuilderToken as the fee asset  
3. WHILE swaps are occurring THE Hook SHALL continuously stream yield into the vault address

---

### Requirement 2: Yield Donating Vault Integration
**User Story:**  
As a vault admin, I want the principal to remain untouched and only the yield to be routed, so that the system preserves capital and sustains ongoing funding.

#### Acceptance Criteria
1. WHEN users deposit ETH or stablecoins THEN the vault SHALL mint yield-donating shares  
2. IF yield is generated THEN the system SHALL mint new shares only for the donation address  
3. WHILE the vault is active THE share-to-asset ratio SHALL reflect only actual strategy profit

---

### Requirement 3: Reputation-Gated Yield Access
**User Story:**  
As a builder, I want to prove my contributions to the ecosystem so that I can receive a fair share of the distributed yield.

#### Acceptance Criteria
1. IF a user submits a valid zkProof (e.g., GitHub, DevDAO badge) THEN the TAM SHALL recognize eligibility  
2. IF a user lacks proof THEN the TAM SHALL deny yield allocation  
3. IF a user presents multiple valid proofs THEN the TAM SHALL apply a reputation multiplier to increase their share  
4. WHILE proofs are valid THE user SHALL remain eligible in future allocations

---

### Requirement 4: Attestation Support for Hook-Based Participation
**User Story:**  
As a builder who swaps in BuilderToken pools, I want my participation to be recognized via attestations so that I can build a yield-earning reputation.

#### Acceptance Criteria
1. WHEN a swap occurs THEN the Hook SHALL emit an attestation of participation  
2. IF the attestation is signed and timestamped THEN it SHALL be verifiable on-chain or via aggregator  
3. WHILE the attestation remains valid THE user SHALL gain eligibility to yield rewards

---

### Requirement 5: Yield Split Based on Reputation Score
**User Story:**  
As a reputation oracle, I want to define multipliers for builder score so that yield can be fairly distributed according to proven value.

#### Acceptance Criteria
1. IF a user has a builder score THEN the TAM SHALL use it to scale the allocated yield  
2. WHEN multiple users qualify THEN the split SHALL follow a normalized scoring curve  
3. WHILE scores are valid THE TAM SHALL distribute proportional shares of the total yield

---

## Edge Cases Considered
- Users with outdated proofs (expired attestations or revoked badges)
- Builders with multiple wallets and Sybil-like behavior
- Pool draining scenarios that temporarily halt swap-based yield
- Vault underperformance or negative yield scenarios (buffer logic)
- zkProofs that cannot be verified in the timeframe of reward cycles

---

## Technical Constraints
- Vault must comply with ERC-4626 and integrate seamlessly with Octant’s YDS pattern  
- All proofs and attestations must be verifiable either on-chain or via ZK verifier contracts  
- Hook must be gas-optimized and auditable (following Uniswap v4 standards)  
- TAM must be modular and upgradable to support future scoring models or voting mechanisms

