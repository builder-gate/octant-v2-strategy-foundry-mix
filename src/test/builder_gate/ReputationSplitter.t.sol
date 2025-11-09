// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ReputationSplitter} from "../../builder_gate/ReputationSplitter.sol";

contract ReputationSplitterTest is Test {
    ReputationSplitter public splitter;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);

    event DevRegistered(address indexed dev, uint256 indexed round);
    event ScoresLoaded(uint256 indexed round, uint256 devsCount, uint256 totalScore);
    event RewardClaimed(address indexed dev, uint256 indexed round, uint256 amount);
    event PhaseChanged(ReputationSplitter.Phase newPhase, uint256 indexed round);
    event RewardsDeposited(uint256 indexed round, uint256 amount);
    event NewRoundStarted(uint256 indexed round);

    function setUp() public {
        // Deploy ReputationSplitter
        splitter = new ReputationSplitter();

        // Fund test contract with ETH for sending to splitter
        vm.deal(address(this), 1000 ether);

        // Label addresses for better traces
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dave, "Dave");
    }

    // Helper to send ETH to splitter
    function _depositETH(uint256 amount) internal {
        (bool success,) = address(splitter).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // ============================================
    // BASIC SETUP TESTS
    // ============================================

    function test_InitialState() public view {
        assertEq(uint256(splitter.currentPhase()), uint256(ReputationSplitter.Phase.Registration));
        assertEq(splitter.currentRound(), 1);
    }

    // ============================================
    // REGISTRATION PHASE TESTS
    // ============================================

    function test_Register() public {
        vm.expectEmit(true, true, false, true);
        emit DevRegistered(alice, 1);

        vm.prank(alice);
        splitter.register();

        assertTrue(splitter.isRegisteredInRound(1, alice));
        assertEq(splitter.getRegisteredDevsCount(), 1);
    }

    function test_RegisterMultipleDevs() public {
        vm.prank(alice);
        splitter.register();

        vm.prank(bob);
        splitter.register();

        vm.prank(charlie);
        splitter.register();

        assertEq(splitter.getRegisteredDevsCount(), 3);
        assertTrue(splitter.isRegisteredInRound(1, alice));
        assertTrue(splitter.isRegisteredInRound(1, bob));
        assertTrue(splitter.isRegisteredInRound(1, charlie));
    }

    function test_RevertRegisterTwice() public {
        vm.startPrank(alice);
        splitter.register();

        vm.expectRevert("ReputationSplitter: already registered");
        splitter.register();
        vm.stopPrank();
    }

    function test_RevertRegisterNotInRegistrationPhase() public {
        splitter.startActivePhase();

        vm.prank(alice);
        vm.expectRevert("ReputationSplitter: not in registration phase");
        splitter.register();
    }

    // ============================================
    // ACTIVE PHASE TESTS
    // ============================================

    function test_StartActivePhase() public {
        vm.expectEmit(false, true, false, true);
        emit PhaseChanged(ReputationSplitter.Phase.Active, 1);

        splitter.startActivePhase();

        assertEq(uint256(splitter.currentPhase()), uint256(ReputationSplitter.Phase.Active));
    }

    function test_RevertStartActivePhaseNotInRegistration() public {
        splitter.startActivePhase(); // Now in Active

        vm.expectRevert("ReputationSplitter: must be in registration phase");
        splitter.startActivePhase();
    }

    function test_DepositETH() public {
        uint256 depositAmount = 10 ether;

        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(1, depositAmount);

        _depositETH(depositAmount);

        assertEq(splitter.roundRewardPool(1), depositAmount);
        assertEq(address(splitter).balance, depositAmount);
    }

    function test_SetScores() public {
        // Registration
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();

        // Move to Active phase
        splitter.startActivePhase();

        // Deposit rewards
        uint256 rewardAmount = 10 ether;
        _depositETH(rewardAmount);

        // Set scores
        address[] memory devs = new address[](2);
        devs[0] = alice;
        devs[1] = bob;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 700;
        scores[1] = 300;

        vm.expectEmit(true, false, false, true);
        emit ScoresLoaded(1, 2, 1000);

        vm.expectEmit(false, true, false, true);
        emit PhaseChanged(ReputationSplitter.Phase.Distribution, 1);

        splitter.setScores(devs, scores);

        // Verify scores
        assertEq(splitter.roundDevScores(1, alice), 700);
        assertEq(splitter.roundDevScores(1, bob), 300);
        assertEq(splitter.roundTotalScore(1), 1000);

        // Verify automatic phase change
        assertEq(uint256(splitter.currentPhase()), uint256(ReputationSplitter.Phase.Distribution));
    }

    function test_RevertSetScoresNotActive() public {
        vm.prank(alice);
        splitter.register();

        address[] memory devs = new address[](1);
        devs[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.expectRevert("ReputationSplitter: not in active phase");
        splitter.setScores(devs, scores);
    }

    function test_RevertSetScoresDevNotRegistered() public {
        splitter.startActivePhase();

        address[] memory devs = new address[](1);
        devs[0] = alice; // Not registered
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.expectRevert("ReputationSplitter: dev not registered");
        splitter.setScores(devs, scores);
    }

    // ============================================
    // DISTRIBUTION PHASE TESTS
    // ============================================

    function test_ClaimRewards() public {
        // Setup: Registration
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();

        // Setup: Active phase
        splitter.startActivePhase();

        uint256 rewardAmount = 10 ether;
        _depositETH(rewardAmount);

        address[] memory devs = new address[](2);
        devs[0] = alice;
        devs[1] = bob;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 800;
        scores[1] = 200;

        splitter.setScores(devs, scores);

        // Alice claims
        uint256 aliceExpectedReward = 8 ether; // (800/1000) * 10

        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(alice, 1, aliceExpectedReward);

        vm.prank(alice);
        splitter.claim();

        assertEq(alice.balance, aliceExpectedReward);
        assertTrue(splitter.hasClaimedInRound(1, alice));
    }

    function test_CalculateReward() public {
        // Setup round
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();

        splitter.startActivePhase();

        uint256 rewardAmount = 10 ether;
        _depositETH(rewardAmount);

        address[] memory devs = new address[](2);
        devs[0] = alice;
        devs[1] = bob;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 600;
        scores[1] = 400;

        splitter.setScores(devs, scores);

        // Check calculations
        assertEq(splitter.calculateReward(alice), 6 ether);
        assertEq(splitter.calculateReward(bob), 4 ether);
    }

    function test_RevertClaimTwice() public {
        // Setup and claim once
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        uint256 rewardAmount = 10 ether;
        _depositETH(rewardAmount);

        address[] memory devs = new address[](1);
        devs[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        splitter.setScores(devs, scores);

        vm.startPrank(alice);
        splitter.claim();

        // Try to claim again
        vm.expectRevert("ReputationSplitter: no rewards to claim");
        splitter.claim();
        vm.stopPrank();
    }

    // ============================================
    // MULTI-ROUND TESTS
    // ============================================

    function test_CompleteMultiRoundFlow() public {
        // ===== ROUND 1 =====
        // Registration
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();

        // Active + Deposit + Scores
        splitter.startActivePhase();

        uint256 round1Reward = 10 ether;
        _depositETH(round1Reward);

        address[] memory devs1 = new address[](2);
        devs1[0] = alice;
        devs1[1] = bob;
        uint256[] memory scores1 = new uint256[](2);
        scores1[0] = 500;
        scores1[1] = 500;

        splitter.setScores(devs1, scores1);

        // Alice claims Round 1
        vm.prank(alice);
        splitter.claim();
        assertEq(alice.balance, 5 ether);

        // ===== ROUND 2 =====
        vm.expectEmit(true, false, false, true);
        emit NewRoundStarted(2);

        splitter.startNewRound();

        assertEq(splitter.currentRound(), 2);
        assertEq(uint256(splitter.currentPhase()), uint256(ReputationSplitter.Phase.Registration));

        // Registration Round 2
        vm.prank(bob);
        splitter.register();
        vm.prank(charlie);
        splitter.register();

        // Active + Deposit + Scores
        splitter.startActivePhase();

        uint256 round2Reward = 20 ether;
        _depositETH(round2Reward);

        address[] memory devs2 = new address[](2);
        devs2[0] = bob;
        devs2[1] = charlie;
        uint256[] memory scores2 = new uint256[](2);
        scores2[0] = 700;
        scores2[1] = 300;

        splitter.setScores(devs2, scores2);

        // Bob claims both rounds
        vm.prank(bob);
        splitter.claim();

        // Bob should have: Round 1 (5 ether) + Round 2 (14 ether) = 19 ether
        assertEq(bob.balance, 19 ether);
    }

    function test_ClaimMultipleRoundsAtOnce() public {
        // Setup Round 1
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        uint256 round1Reward = 10 ether;
        _depositETH(round1Reward);

        address[] memory devs1 = new address[](1);
        devs1[0] = alice;
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;

        splitter.setScores(devs1, scores1);

        // Setup Round 2
        splitter.startNewRound();

        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        uint256 round2Reward = 20 ether;
        _depositETH(round2Reward);

        address[] memory devs2 = new address[](1);
        devs2[0] = alice;
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;

        splitter.setScores(devs2, scores2);

        // Alice claims both rounds at once
        vm.prank(alice);
        splitter.claim();

        // Alice should receive: Round 1 (10 ether) + Round 2 (20 ether) = 30 ether
        assertEq(alice.balance, 30 ether);
        assertTrue(splitter.hasClaimedInRound(1, alice));
        assertTrue(splitter.hasClaimedInRound(2, alice));
    }

    function test_GetUnclaimedRounds() public {
        // Setup Round 1
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(10 ether);

        address[] memory devs = new address[](1);
        devs[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        splitter.setScores(devs, scores);

        // Setup Round 2
        splitter.startNewRound();
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(20 ether);

        splitter.setScores(devs, scores);

        // Check unclaimed rounds
        uint256[] memory unclaimed = splitter.getUnclaimedRounds(alice);
        assertEq(unclaimed.length, 2);
        assertEq(unclaimed[0], 1);
        assertEq(unclaimed[1], 2);

        // Claim Round 1
        vm.prank(alice);
        splitter.claim();

        // Check again - should be empty
        unclaimed = splitter.getUnclaimedRounds(alice);
        assertEq(unclaimed.length, 0);
    }

    function test_GetTotalClaimableAmount() public {
        // Setup Round 1
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(10 ether);

        address[] memory devs = new address[](1);
        devs[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        splitter.setScores(devs, scores);

        // Setup Round 2
        splitter.startNewRound();
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(15 ether);

        splitter.setScores(devs, scores);

        // Check total claimable
        assertEq(splitter.getTotalClaimableAmount(alice), 25 ether);
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_GetDevInfo() public {
        vm.prank(alice);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(10 ether);

        address[] memory devs = new address[](1);
        devs[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        splitter.setScores(devs, scores);

        (bool registered, uint256 score, bool claimed, uint256 claimableAmount) = splitter.getDevInfo(alice);

        assertTrue(registered);
        assertEq(score, 100);
        assertFalse(claimed);
        assertEq(claimableAmount, 10 ether);
    }

    function test_GetCurrentRoundInfo() public {
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();

        splitter.startActivePhase();

        _depositETH(10 ether);

        (
            uint256 round,
            ReputationSplitter.Phase phase,
            uint256 devsCount,
            uint256 totalScoreValue,
            uint256 rewardPool
        ) = splitter.getCurrentRoundInfo();

        assertEq(round, 1);
        assertEq(uint256(phase), uint256(ReputationSplitter.Phase.Active));
        assertEq(devsCount, 2);
        assertEq(totalScoreValue, 0); // No scores set yet
        assertEq(rewardPool, 10 ether);
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_RevertStartNewRoundNotInDistribution() public {
        vm.expectRevert("ReputationSplitter: must complete current round");
        splitter.startNewRound();
    }

    function test_EmergencyWithdraw() public {
        uint256 depositAmount = 10 ether;
        _depositETH(depositAmount);

        address recipient = address(0x999);
        splitter.emergencyWithdraw(depositAmount, recipient);

        assertEq(recipient.balance, depositAmount);
        assertEq(address(splitter).balance, 0);
    }

    function test_RevertDepositZeroETH() public {
        vm.expectRevert("ReputationSplitter: must send ETH");
        _depositETH(0);
    }

    function test_ProportionalDistribution() public {
        // Test exact proportional distribution
        vm.prank(alice);
        splitter.register();
        vm.prank(bob);
        splitter.register();
        vm.prank(charlie);
        splitter.register();

        splitter.startActivePhase();

        uint256 rewardAmount = 1000 ether;
        _depositETH(rewardAmount);

        address[] memory devs = new address[](3);
        devs[0] = alice;
        devs[1] = bob;
        devs[2] = charlie;

        uint256[] memory scores = new uint256[](3);
        scores[0] = 50;  // 50%
        scores[1] = 30;  // 30%
        scores[2] = 20;  // 20%

        splitter.setScores(devs, scores);

        assertEq(splitter.calculateReward(alice), 500 ether);
        assertEq(splitter.calculateReward(bob), 300 ether);
        assertEq(splitter.calculateReward(charlie), 200 ether);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
