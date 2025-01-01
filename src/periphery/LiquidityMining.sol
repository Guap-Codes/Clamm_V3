// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/ICLAMM.sol";
//import "../interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title LiquidityMining
/// @notice A contract for managing liquidity mining rewards for CLAMM LP tokens
/// @dev Implements a MasterChef-style reward distribution system with the following features:
///      - Multiple pool support with customizable allocation points
///      - Automatic reward distribution based on block numbers
///      - Safe handling of reward transfers
///      - Integration with CLAMM for automatic staking on liquidity provision
contract LiquidityMining is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice User staking information for each pool
    /// @param amount Total amount of LP tokens staked by the user
    /// @param rewardDebt Tracks the number of rewards owed to the user. Used to calculate correct reward distributions
    ///        when a user stakes or withdraws tokens
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Pool information for each staking pool
    /// @param lpToken Address of the LP token that can be staked
    /// @param allocPoint Number of allocation points assigned to this pool. Determines the proportion of rewards this pool receives
    /// @param lastRewardBlock Last block number that rewards distribution occurred
    /// @param accRewardPerShare Accumulated rewards per share, scaled by 1e12. Used to calculate user rewards
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
    }

    /// @notice The token used for distributing rewards to stakers
    IERC20 public immutable rewardToken;

    /// @notice The amount of reward tokens distributed per block
    uint256 public rewardPerBlock;

    /// @notice Array of all staking pools
    PoolInfo[] public poolInfo;

    /// @notice Mapping of pool ID => user address => staking information
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Total allocation points across all pools. Must be the sum of all pools' allocPoint
    uint256 public totalAllocPoint;

    /// @notice Block number when reward distribution starts
    uint256 public startBlock;

    /// @notice Block number when reward distribution ends
    uint256 public endBlock;

    /// @notice Maximum allowed liquidity amount to prevent overflow
    uint256 private constant MAX_LIQUIDITY_AMOUNT = 2 ** 128 - 1;

    /// @notice CLAMM interface reference
    ICLAMM public clamm;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event LiquidityAdded(address indexed user, uint256 amount);
    event LiquidityRemoved(address indexed user, uint256 amount);

    mapping(address => uint256) private _userLiquidity;

    function userLiquidity(address user) public view returns (uint256) {
        return _userLiquidity[user];
    }

    /// @notice Constructor initializes the reward token and distribution parameters
    /// @param _rewardToken Address of the token to be distributed as rewards
    /// @param _rewardPerBlock Number of reward tokens distributed per block
    /// @param _startBlock Block number at which reward distribution starts
    /// @param _clamm CLAMM contract address
    /// @dev The endBlock is initially set to startBlock and should be updated via admin function
    constructor(
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        ICLAMM _clamm
    ) {
        require(address(_clamm) != address(0), "Invalid CLAMM address");
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _startBlock;
        clamm = _clamm;
    }

    /// @notice Returns the number of staking pools
    /// @return Number of pools created
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Add a new LP token to the pool
    /// @param _allocPoint Allocation points assigned to this pool. Higher points = higher reward share
    /// @param _lpToken Address of the LP token that can be staked
    /// @dev Updates all pools before adding new one to ensure proper reward accounting
    function add(uint256 _allocPoint, IERC20 _lpToken) external {
        massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0
            })
        );
    }

    /// @notice Update the allocation points of a pool
    /// @param _pid Pool ID to update
    /// @param _allocPoint New allocation points for the pool
    function set(uint256 _pid, uint256 _allocPoint) external {
        massUpdatePools();
        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /// @notice Update reward variables for all pools
    /// @dev Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool
    /// @param _pid Pool ID to update
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - pool.lastRewardBlock;
        uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) /
            totalAllocPoint;
        pool.accRewardPerShare =
            pool.accRewardPerShare +
            ((reward * 1e12) / lpSupply);
        pool.lastRewardBlock = block.number;
    }

    /// @notice Deposit LP tokens to earn rewards
    /// @param _pid Pool ID to deposit to
    /// @param _amount Amount of LP tokens to deposit
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            int256 pending = int256(
                (user.amount * pool.accRewardPerShare) /
                    1e12 -
                    uint256(user.rewardDebt)
            );
            if (pending > 0) {
                safeRewardTransfer(msg.sender, uint256(pending));
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = int256((user.amount * pool.accRewardPerShare) / 1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw LP tokens from the pool
    /// @param _pid Pool ID to withdraw from
    /// @param _amount Amount of LP tokens to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        int256 pending = int256(
            (user.amount * pool.accRewardPerShare) /
                1e12 -
                uint256(user.rewardDebt)
        );
        if (pending > 0) {
            safeRewardTransfer(msg.sender, uint256(pending));
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = int256((user.amount * pool.accRewardPerShare) / 1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Emergency withdraw LP tokens without caring about rewards
    /// @param _pid Pool ID to withdraw from
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @notice Safe transfer of reward tokens
    /// @dev Will transfer the minimum of _amount or the contract's balance to prevent failed transfers
    /// @param _to Address to transfer rewards to
    /// @param _amount Desired amount of reward tokens to transfer
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (_amount > rewardBal) {
            rewardToken.transfer(_to, rewardBal);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    /// @notice Called by CLAMM when liquidity is added
    /// @param user Address of the user who added liquidity
    /// @param amount Amount of LP tokens added
    function notifyLiquidityAdded(address user, uint256 amount) external {
        require(msg.sender == address(clamm), "Only CLAMM can call this");
        require(user != address(0), "Invalid user address");
        require(amount > 0 && amount <= MAX_LIQUIDITY_AMOUNT, "Invalid amount");
        uint256 pid = 0; // CLAMM pool ID
        require(pid < poolInfo.length, "Invalid pool ID");
        updatePool(pid);
        UserInfo storage userInfoLocal = userInfo[pid][user];

        // Update user's staked amount
        userInfoLocal.amount = userInfoLocal.amount + amount;

        // Update reward debt
        userInfoLocal.rewardDebt = int256(
            (userInfoLocal.amount * poolInfo[pid].accRewardPerShare) / 1e12
        );

        emit LiquidityAdded(user, amount);
    }

    /// @notice Called by CLAMM when liquidity is removed
    /// @param user Address of the user who removed liquidity
    /// @param amount Amount of LP tokens removed
    function notifyLiquidityRemoved(address user, uint256 amount) external {
        require(msg.sender == address(clamm), "Only CLAMM can call this");
        require(user != address(0), "Invalid user address");
        require(amount > 0 && amount <= MAX_LIQUIDITY_AMOUNT, "Invalid amount");

        uint256 pid = 0; // CLAMM pool ID
        require(pid < poolInfo.length, "Invalid pool ID");

        updatePool(pid);
        UserInfo storage userInfoLocal = userInfo[pid][user];

        // Ensure user has enough liquidity
        require(userInfoLocal.amount >= amount, "Insufficient liquidity");

        // Calculate pending rewards before updating state
        int256 pending = int256(
            (userInfoLocal.amount * poolInfo[pid].accRewardPerShare) /
                1e12 -
                uint256(userInfoLocal.rewardDebt)
        );

        // Update user's staked amount
        userInfoLocal.amount = userInfoLocal.amount - amount;

        // Update reward debt
        userInfoLocal.rewardDebt = int256(
            (userInfoLocal.amount * poolInfo[pid].accRewardPerShare) / 1e12
        );

        // Transfer pending rewards if any
        if (pending > 0) {
            safeRewardTransfer(user, uint256(pending));
        }

        emit LiquidityRemoved(user, amount);
    }

    /// @notice Updates the CLAMM contract address
    /// @param _clamm New CLAMM contract address
    /// @dev Can only be called once to set the initial CLAMM address
    function setCLAMM(address _clamm) external {
        require(address(clamm) == address(1), "CLAMM already set");
        require(_clamm != address(0), "Invalid CLAMM address");
        clamm = ICLAMM(_clamm);
    }
}
