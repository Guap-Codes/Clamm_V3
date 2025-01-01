// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Staking Rewards Contract
/// @notice A contract that allows users to stake tokens and earn rewards over time
/// @dev Implementation of a staking rewards distribution system with fixed duration periods
contract StakingRewards is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice The token that users can stake
    IERC20 public immutable stakingToken;
    /// @notice The token that users receive as rewards
    IERC20 public immutable rewardsToken;

    /// @notice Role identifier for contract owner
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @notice Duration of rewards to be paid out (in seconds)
    uint256 public duration;
    /// @notice Timestamp of when the rewards finish
    uint256 public finishAt;
    /// @notice Last time the reward was updated
    uint256 public updatedAt;
    /// @notice Reward to be paid out per second
    uint256 public rewardRate;
    /// @notice Sum of (reward rate * dt * 1e18 / total supply)
    uint256 public rewardPerTokenStored;
    /// @notice User address => rewardPerToken snapshot
    mapping(address => uint256) public userRewardPerTokenPaid;
    /// @notice User address => rewards to be claimed
    mapping(address => uint256) public rewards;

    /// @notice Total staked tokens
    uint256 public totalSupply;
    /// @notice User address => staked amount
    mapping(address => uint256) public balanceOf;

    constructor(address _stakingToken, address _rewardToken) {
        _grantRole(OWNER_ROLE, msg.sender);
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardToken);
    }

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "not authorized");
        _;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    /// @notice Sets the duration for the rewards distribution
    /// @param _duration Duration in seconds
    /// @dev Can only be called by owner and when previous reward period has finished
    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
    }

    /// @notice Notifies the contract of reward amount to distribute
    /// @param _amount Amount of reward tokens to distribute
    /// @dev Requires reward tokens to be pre-sent to this contract
    function notifyRewardAmount(uint256 _amount) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint256 remainingRewards = rewardRate * (finishAt - block.timestamp);
            rewardRate = (_amount + remainingRewards) / duration;
        }

        require(rewardRate > 0, "reward rate = 0");
        require(rewardRate * duration <= rewardsToken.balanceOf(address(this)), "reward amount > balance");

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    /// @notice Allows users to stake tokens
    /// @param _amount Amount of tokens to stake
    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        balanceOf[msg.sender] = balanceOf[msg.sender] + _amount;
        totalSupply = totalSupply + _amount;
    }

    /// @notice Allows users to withdraw their staked tokens
    /// @param _amount Amount of tokens to withdraw
    function withdraw(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
        balanceOf[msg.sender] = balanceOf[msg.sender] - _amount;
        totalSupply = totalSupply - _amount;
        stakingToken.safeTransfer(msg.sender, _amount);
    }

    /// @notice Returns the last timestamp where rewards are applicable
    /// @return uint256 The lesser of current timestamp or rewards finish time
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, finishAt);
    }

    /// @notice Calculates the reward per token stored
    /// @return uint256 The reward amount per token
    /// @dev Uses precision factor of 1e18
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + (((lastTimeRewardApplicable() - updatedAt) * rewardRate * 1e18) / totalSupply);
    }

    /// @notice Calculates the earned rewards for an account
    /// @param _account Address of the account to check
    /// @return uint256 The amount of rewards earned
    function earned(address _account) public view returns (uint256) {
        return (balanceOf[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18 + rewards[_account];
    }

    /// @notice Allows users to claim their earned rewards
    function getReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
        }
    }
}
