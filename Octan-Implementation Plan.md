# Implementation Plan

- [ ] 1. Set up base project structure
  - Create project folder with basic monorepo (e.g. `contracts/`, `backend/`, `proofs/`)
  - Set up Hardhat + TypeScript + testing stack (Chai, Mocha)
  - Install dependencies: `@openzeppelin/contracts`, `forge-std`, `zksync-toolkit` (optional), etc.
  - _Requirements: 1.1, 2.1_

- [ ] 2. Implement minimal Uniswap v4 Hook
  - [ ] 2.1 Create `BuilderFeeHook.sol` contract
    - Redirect 0.3–1% fee to YDS Vault
    - Emit event `BuilderSwap(address user, uint256 amount)`
    - _Requirements: 1.1, 1.2_
  - [ ] 2.2 Write tests for swap + fee simulation
    - Verify fee destination address
    - Simulate multiple users
    - _Requirements: 1.3_

- [ ] 3. Build ERC-4626 Vault for Yield Donating Strategy (YDS)
  - [ ] 3.1 Write `BuilderYieldVault.sol` contract based on `ERC4626`
    - Only donates generated yield to `TAM` address
    - Stores principal without affecting it
    - _Requirements: 2.1, 2.2_
  - [ ] 3.2 Write deposit/withdrawal + simulated yield generation tests
    - Mock DeFi strategy
    - Verify share minting for donation
    - _Requirements: 2.3_

- [ ] 4. Build TAM: `ReputationSplitter.sol`
  - [ ] 4.1 Create `claimYield()` function with inputs:
    - GitHub proof (score + signature)
    - Talent score
    - Self verification
    - _Requirements: 3.1, 3.2_
  - [ ] 4.2 Write normalized builderScore calculation logic
    - Multipliers by source (e.g. GitHub * 0.4 + Talent * 0.4 + Self * 0.2)
    - Apply proportional split of available yield
    - _Requirements: 5.1, 5.2_
  - [ ] 4.3 Unit tests:
    - Score validation + calculation
    - Edge case tests: score 0, invalid, multiple claim
    - _Requirements: 5.3, 5.4_

- [ ] 5. Build proof generation backend
  - [ ] 5.1 Create `/proof/github` endpoint
    - Input: username + wallet address
    - Output: score signed with `privateKey` + payload
    - Source: [GitHub Readme Stats API](https://github.com/anuraghazra/github-readme-stats)
    - _Requirements: 3.1_
  - [ ] 5.2 `/proof/talent` endpoint
    - Query builderScore in Talent Protocol
    - Sign JWT with wallet + score
    - _Requirements: 3.1_
  - [ ] 5.3 `/proof/self` endpoint
    - Self QR SDK integration
    - Store verified `sessionId` and associate wallet
    - _Requirements: 4.1_

- [ ] 6. End-to-end integration
  - [ ] 6.1 Script that simulates:
    - swap on Uniswap → generates fee
    - deposits yield in vault
    - sends yield to splitter
    - multiple builders claim yield with different proofs
  - _Requirements: full flow_

