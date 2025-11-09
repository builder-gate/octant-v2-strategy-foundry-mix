// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ReputationSplitter
 * @notice Simplified reward distribution system based on builder scores using ERC20 tokens
 * @dev Three-phase cycle: Registration → Active → Distribution
 */
contract ReputationSplitter is ReentrancyGuard, Ownable {

    /// @notice Contract states
    enum Phase {
        Registration,   // Devs can register
        Active,         // Admin loads scores
        Distribution    // Rewards are being distributed
    }

    /// @notice Reward token used for distributions
    IERC20 public immutable rewardToken;

    /// @notice Current phase of the contract
    Phase public currentPhase;

    /// @notice Current round ID (starts at 1)
    uint256 public currentRound;

    /// @notice Total reward pool per round
    mapping(uint256 => uint256) public roundRewardPool;

    /// @notice Total rewards claimed from each round
    mapping(uint256 => uint256) public roundClaimedRewards;

    /// @notice Array of registered developers per round
    mapping(uint256 => address[]) private _roundRegisteredDevs;

    /// @notice Mapping to check if dev is registered in a round
    mapping(uint256 => mapping(address => bool)) public isRegisteredInRound;

    /// @notice Mapping from round to dev address to their score
    mapping(uint256 => mapping(address => uint256)) public roundDevScores;

    /// @notice Total sum of all scores per round
    mapping(uint256 => uint256) public roundTotalScore;

    /// @notice Mapping to track if dev has claimed in a round
    mapping(uint256 => mapping(address => bool)) public hasClaimedInRound;

    /// @notice Events
    event DevRegistered(address indexed dev, uint256 indexed round);
    event ScoresLoaded(uint256 indexed round, uint256 devsCount, uint256 totalScore);
    event RewardClaimed(address indexed dev, uint256 indexed round, uint256 amount);
    event PhaseChanged(Phase newPhase, uint256 indexed round);
    event RewardsDeposited(uint256 indexed round, uint256 amount);
    event NewRoundStarted(uint256 indexed round);

    /**
     * @notice Constructor initializes the contract
     * @param _rewardToken Address of the ERC20 token used for rewards
     */
    constructor(address _rewardToken) Ownable(msg.sender) {
        require(_rewardToken != address(0), "ReputationSplitter: invalid token address");
        rewardToken = IERC20(_rewardToken);
        currentPhase = Phase.Registration;
        currentRound = 1;
    }

    // ============================================
    // DEV FUNCTIONS
    // ============================================

    /**
     * @notice Devs register themselves for the current round
     * @dev Only available during Registration phase
     */
    function register() external {
        require(currentPhase == Phase.Registration, "ReputationSplitter: not in registration phase");
        require(!isRegisteredInRound[currentRound][msg.sender], "ReputationSplitter: already registered");

        _roundRegisteredDevs[currentRound].push(msg.sender);
        isRegisteredInRound[currentRound][msg.sender] = true;

        emit DevRegistered(msg.sender, currentRound);
    }

    /**
     * @notice Devs claim their proportional rewards from all unclaimed rounds
     * @dev Iterates from round 1 to currentRound and claims all pending rewards
     */
    function claim() external nonReentrant {
        uint256 totalReward = 0;
        uint256 claimedRounds = 0;

        // Iterate through all rounds from 1 to current
        for (uint256 roundId = 1; roundId <= currentRound; roundId++) {
            // Skip if already claimed or not registered in this round
            if (hasClaimedInRound[roundId][msg.sender] || !isRegisteredInRound[roundId][msg.sender]) {
                continue;
            }

            // Skip if no score assigned
            if (roundDevScores[roundId][msg.sender] == 0) {
                continue;
            }

            // Calculate reward for this round
            uint256 roundReward = calculateRewardForRound(msg.sender, roundId);

            if (roundReward > 0) {
                hasClaimedInRound[roundId][msg.sender] = true;
                totalReward += roundReward;
                roundClaimedRewards[roundId] += roundReward;
                claimedRounds++;
                emit RewardClaimed(msg.sender, roundId, roundReward);
            }
        }

        require(totalReward > 0, "ReputationSplitter: no rewards to claim");

        // Transfer ERC20 tokens to claimer
        require(rewardToken.transfer(msg.sender, totalReward), "ReputationSplitter: token transfer failed");
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Admin loads scores for all registered devs
     * @param devs Array of dev addresses
     * @param scores Array of scores (must match devs by index)
     * @dev Only available during Active phase. Automatically transitions to Distribution phase after loading.
     */
    function setScores(address[] calldata devs, uint256[] calldata scores) external onlyOwner {
        require(currentPhase == Phase.Active, "ReputationSplitter: not in active phase");
        require(devs.length == scores.length, "ReputationSplitter: length mismatch");
        require(devs.length > 0, "ReputationSplitter: empty arrays");

        // Calculate unclaimed rewards from previous rounds (allocated but not yet claimed)
        uint256 unclaimedRewards = 0;
        for (uint256 i = 1; i < currentRound; i++) {
            unclaimedRewards += (roundRewardPool[i] - roundClaimedRewards[i]);
        }

        // Set the reward pool for this round to current balance minus unclaimed rewards from previous rounds
        uint256 currentBalance = rewardToken.balanceOf(address(this));
        require(currentBalance > unclaimedRewards, "ReputationSplitter: insufficient balance for new round");
        roundRewardPool[currentRound] = currentBalance - unclaimedRewards;

        for (uint256 i = 0; i < devs.length; i++) {
            address dev = devs[i];
            uint256 score = scores[i];

            require(isRegisteredInRound[currentRound][dev], "ReputationSplitter: dev not registered");
            require(score > 0, "ReputationSplitter: score must be > 0");

            // If dev already has a score, subtract it first
            if (roundDevScores[currentRound][dev] > 0) {
                roundTotalScore[currentRound] -= roundDevScores[currentRound][dev];
            }

            roundDevScores[currentRound][dev] = score;
            roundTotalScore[currentRound] += score;
        }

        emit ScoresLoaded(currentRound, devs.length, roundTotalScore[currentRound]);

        // Automatically transition to Distribution phase
        currentPhase = Phase.Distribution;
        emit PhaseChanged(Phase.Distribution, currentRound);
    }

    /**
     * @notice Admin transitions from Registration to Active phase
     * @dev Can only be called when in Registration phase
     */
    function startActivePhase() external onlyOwner {
        require(currentPhase == Phase.Registration, "ReputationSplitter: must be in registration phase");
        currentPhase = Phase.Active;
        emit PhaseChanged(Phase.Active, currentRound);
    }

    /**
     * @notice Admin starts a new round
     * @dev Can only be called when in Distribution phase. Previous round data is preserved.
     */
    function startNewRound() external onlyOwner {
        require(currentPhase == Phase.Distribution, "ReputationSplitter: must complete current round");

        // Increment round counter
        currentRound++;

        // Reset phase to Registration for new round
        currentPhase = Phase.Registration;

        emit NewRoundStarted(currentRound);
        emit PhaseChanged(Phase.Registration, currentRound);
    }

    /**
     * @notice Emergency withdraw function (only owner)
     * @param amount Amount of tokens to withdraw
     * @param to Recipient address
     */
    function emergencyWithdraw(uint256 amount, address to) external onlyOwner {
        require(to != address(0), "ReputationSplitter: invalid recipient");
        require(amount <= rewardToken.balanceOf(address(this)), "ReputationSplitter: insufficient balance");

        require(rewardToken.transfer(to, amount), "ReputationSplitter: token transfer failed");
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Calculate reward amount for a specific dev in current round
     * @param dev Dev address
     * @return Reward amount
     */
    function calculateReward(address dev) public view returns (uint256) {
        return calculateRewardForRound(dev, currentRound);
    }

    /**
     * @notice Calculate reward amount for a specific dev in a specific round
     * @param dev Dev address
     * @param roundId Round ID
     * @return Reward amount
     */
    function calculateRewardForRound(address dev, uint256 roundId) public view returns (uint256) {
        if (roundTotalScore[roundId] == 0 || roundDevScores[roundId][dev] == 0) {
            return 0;
        }

        // Proportional distribution: (devScore / totalScore) * totalRewardPool
        return (roundRewardPool[roundId] * roundDevScores[roundId][dev]) / roundTotalScore[roundId];
    }

    /**
     * @notice Get total claimable amount for a dev across all rounds
     * @param dev Dev address
     * @return Total claimable amount from all unclaimed rounds
     */
    function getTotalClaimableAmount(address dev) external view returns (uint256) {
        uint256 totalClaimable = 0;

        for (uint256 roundId = 1; roundId <= currentRound; roundId++) {
            // Skip if already claimed or not registered
            if (hasClaimedInRound[roundId][dev] || !isRegisteredInRound[roundId][dev]) {
                continue;
            }

            // Skip if no score assigned
            if (roundDevScores[roundId][dev] == 0) {
                continue;
            }

            uint256 roundReward = calculateRewardForRound(dev, roundId);
            totalClaimable += roundReward;
        }

        return totalClaimable;
    }

    /**
     * @notice Get claimable amount for a dev in current round only
     * @param dev Dev address
     * @return Claimable amount (0 if already claimed)
     */
    function getClaimableAmount(address dev) external view returns (uint256) {
        if (hasClaimedInRound[currentRound][dev]) {
            return 0;
        }
        return calculateReward(dev);
    }

    /**
     * @notice Get list of unclaimed rounds for a dev
     * @param dev Dev address
     * @return Array of round IDs where dev has unclaimed rewards
     */
    function getUnclaimedRounds(address dev) external view returns (uint256[] memory) {
        // First, count unclaimed rounds
        uint256 unclaimedCount = 0;
        for (uint256 roundId = 1; roundId <= currentRound; roundId++) {
            if (!hasClaimedInRound[roundId][dev] &&
                isRegisteredInRound[roundId][dev] &&
                roundDevScores[roundId][dev] > 0) {
                unclaimedCount++;
            }
        }

        // Create array with exact size
        uint256[] memory unclaimedRounds = new uint256[](unclaimedCount);
        uint256 index = 0;

        // Fill array
        for (uint256 roundId = 1; roundId <= currentRound; roundId++) {
            if (!hasClaimedInRound[roundId][dev] &&
                isRegisteredInRound[roundId][dev] &&
                roundDevScores[roundId][dev] > 0) {
                unclaimedRounds[index] = roundId;
                index++;
            }
        }

        return unclaimedRounds;
    }

    /**
     * @notice Get all registered devs for current round
     * @return Array of registered dev addresses
     */
    function getRegisteredDevs() external view returns (address[] memory) {
        return _roundRegisteredDevs[currentRound];
    }

    /**
     * @notice Get all registered devs for a specific round
     * @param roundId Round ID
     * @return Array of registered dev addresses
     */
    function getRegisteredDevsForRound(uint256 roundId) external view returns (address[] memory) {
        return _roundRegisteredDevs[roundId];
    }

    /**
     * @notice Get total number of registered devs in current round
     * @return Count of registered devs
     */
    function getRegisteredDevsCount() external view returns (uint256) {
        return _roundRegisteredDevs[currentRound].length;
    }

    /**
     * @notice Get dev info for current round
     * @param dev Dev address
     * @return registered Is dev registered
     * @return score Dev's score
     * @return claimed Has dev claimed
     * @return claimableAmount Amount dev can claim
     */
    function getDevInfo(address dev) external view returns (
        bool registered,
        uint256 score,
        bool claimed,
        uint256 claimableAmount
    ) {
        registered = isRegisteredInRound[currentRound][dev];
        score = roundDevScores[currentRound][dev];
        claimed = hasClaimedInRound[currentRound][dev];
        claimableAmount = claimed ? 0 : calculateReward(dev);
    }

    /**
     * @notice Get dev info for a specific round
     * @param dev Dev address
     * @param roundId Round ID
     * @return registered Is dev registered
     * @return score Dev's score
     * @return claimed Has dev claimed
     * @return rewardAmount Reward amount (regardless of claim status)
     */
    function getDevInfoForRound(address dev, uint256 roundId) external view returns (
        bool registered,
        uint256 score,
        bool claimed,
        uint256 rewardAmount
    ) {
        registered = isRegisteredInRound[roundId][dev];
        score = roundDevScores[roundId][dev];
        claimed = hasClaimedInRound[roundId][dev];
        rewardAmount = calculateRewardForRound(dev, roundId);
    }

    /**
     * @notice Get current round info
     * @return round Current round number
     * @return phase Current phase
     * @return devsCount Number of registered devs
     * @return totalScoreValue Total score sum
     * @return rewardPool Total reward pool
     */
    function getCurrentRoundInfo() external view returns (
        uint256 round,
        Phase phase,
        uint256 devsCount,
        uint256 totalScoreValue,
        uint256 rewardPool
    ) {
        round = currentRound;
        phase = currentPhase;
        devsCount = _roundRegisteredDevs[currentRound].length;
        totalScoreValue = roundTotalScore[currentRound];
        rewardPool = roundRewardPool[currentRound];
    }

    /**
     * @notice Get info for a specific round
     * @param roundId Round ID
     * @return devsCount Number of registered devs
     * @return totalScoreValue Total score sum
     * @return rewardPool Total reward pool
     */
    function getRoundInfo(uint256 roundId) external view returns (
        uint256 devsCount,
        uint256 totalScoreValue,
        uint256 rewardPool
    ) {
        devsCount = _roundRegisteredDevs[roundId].length;
        totalScoreValue = roundTotalScore[roundId];
        rewardPool = roundRewardPool[roundId];
    }
}
