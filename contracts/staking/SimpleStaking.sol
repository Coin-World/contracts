pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

/**
 * @title Simple ERC20 Staking Contract
 * @dev A contract for staking ERC20 tokens and earning rewards
 */
contract SimpleStaking is Ownable, ReentrancyGuard {
    // ============ State Variables ============

    // Token contracts
    IERC20 public stakingToken; // Token that users stake
    IERC20 public rewardToken; // Token distributed as rewards

    // Staking parameters
    uint256 public rewardStartBlock; // Block number when rewards distribution starts
    uint256 public rewardDuration; // The total number of blocks rewards will be paid for
    uint256 public rewardEndBlock; // The calculated end block (rewardStartBlock + rewardDuration)
    // uint256 public poolStartTime; // REMOVED: No longer needed, reward period is now fixed.
    uint256 public rewardPerBlock;

    // Pool state
    uint256 public totalStaked; // Total amount of tokens staked
    uint256 public lastRewardBlock; // Last block where rewards were calculated
    uint256 public accRewardPerShare; // Accumulated reward per share (scaled by 1e18)

    // User staking info
    struct UserInfo {
        uint256 amount; // Amount of tokens staked by user
        uint256 rewardDebt; // Reward debt for calculating pending rewards
        uint256 pendingRewards; // Unclaimed rewards
    }

    mapping(address => UserInfo) public userInfo;

    // ============ Events ============

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 reward);
    event RewardPerBlockUpdated(uint256 newRewardPerBlock);
    event RewardStartBlockUpdated(uint256 newStartBlock);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    // ============ Constructor ============

    /**
     * @dev Constructor to initialize the staking contract
     * @param _stakingToken Address of the token to be staked
     * @param _rewardToken Address of the reward token
     * @param _rewardStartBlock Block number when rewards start
     * @param _rewardDuration Block number when rewards start
     * @param _rewardPerBlock Reward tokens distributed per block
     */
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardStartBlock,
        uint256 _rewardDuration,
        uint256 _rewardPerBlock
    ) {
        require(_stakingToken != address(0), "Invalid staking token address");
        require(_rewardToken != address(0), "Invalid reward token address");
        require(
            _rewardStartBlock > block.number,
            "Start block must be in the future"
        );
        require(_rewardDuration > 0, "Reward duration must be greater than 0");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardStartBlock = _rewardStartBlock;
        rewardDuration = _rewardDuration;
        rewardPerBlock = _rewardPerBlock;

        // This decouples the reward period from user actions.
        rewardEndBlock = _rewardStartBlock + _rewardDuration;
        lastRewardBlock = _rewardStartBlock;
    }

    // ============ View Functions ============

    /**
     * @dev Get the current block number
     * @return Current block number
     */
    function getCurrentBlock() public view returns (uint256) {
        return block.number;
    }

    /**
     * @dev Calculate pending rewards for a user
     * @param _user Address of the user
     * @return Pending reward amount
     */
    function pendingReward(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;

        if (block.number > lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 reward = multiplier * rewardPerBlock;
            _accRewardPerShare =
                _accRewardPerShare +
                (reward * 1e18) /
                totalStaked;
        }

        return
            user.pendingRewards +
            (user.amount * _accRewardPerShare) /
            1e18 -
            user.rewardDebt;
    }

    /**
     * @dev Get user staking information
     * @param _user Address of the user
     * @return amount Amount staked by user
     * @return rewardDebt User's reward debt
     * @return pendingRewards User's pending rewards
     */
    function getUserInfo(
        address _user
    )
        public
        view
        returns (uint256 amount, uint256 rewardDebt, uint256 pendingRewards)
    {
        UserInfo storage user = userInfo[_user];
        return (user.amount, user.rewardDebt, user.pendingRewards);
    }

    /**
     * @dev Get pool information
     * @return totalStaked Total amount staked in pool
     * @return lastRewardBlock Last block where rewards were calculated
     * @return accRewardPerShare Accumulated reward per share
     */
    function getPoolInfo() public view returns (uint256, uint256, uint256) {
        return (totalStaked, lastRewardBlock, accRewardPerShare);
    }

    // ============ Internal Functions ============

    /**
     * @dev Get multiplier for reward calculation
     * @param _from From block
     * @param _to To block
     * @return multiplier Number of blocks to calculate rewards for
     */
    /**
     * @dev Get multiplier for reward calculation, respecting the reward period.
     * @param _from From block
     * @param _to To block
     * @return multiplier Number of blocks to calculate rewards for
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        // If the period to check is before the rewards start, return 0
        if (_to <= rewardStartBlock) {
            return 0;
        }

        // Cap the calculation at the rewardEndBlock
        uint256 toBlock = _to > rewardEndBlock ? rewardEndBlock : _to;

        // Ensure the calculation starts from the rewardStartBlock
        uint256 fromBlock = _from < rewardStartBlock ? rewardStartBlock : _from;

        if (fromBlock >= toBlock) {
            return 0;
        }

        return toBlock - fromBlock;
    }

    /**
     * @dev Update reward variables of the pool
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        // If no one is staked, there's nothing to distribute.
        // Just update lastRewardBlock to prevent rewards from being lost.
        if (totalStaked == 0) {
            // We only need to update the time if we are past the start block
            if (block.number > rewardStartBlock) {
                lastRewardBlock = block.number;
            }
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        if (multiplier > 0) {
            uint256 reward = multiplier * rewardPerBlock;
            accRewardPerShare =
                accRewardPerShare +
                (reward * 1e18) /
                totalStaked;
        }

        lastRewardBlock = block.number;
    }

    /**
     * @dev Update user's pending rewards
     * @param _user Address of the user
     */
    function _updateUserRewards(address _user) internal {
        UserInfo storage user = userInfo[_user];

        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) /
                1e18 -
                user.rewardDebt;
            user.pendingRewards = user.pendingRewards + pending;
        }

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
    }

    // ============ External Functions ============

    /**
     * @dev Stake tokens
     * @param _amount Amount of tokens to stake
     */
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Cannot stake 0 tokens");

        // MODIFIED: The check for rewardStartBlock is no longer needed here.
        // Users can stake before rewards begin.

        UserInfo storage user = userInfo[msg.sender];

        _updatePool();
        _updateUserRewards(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), _amount);

        user.amount = user.amount + _amount;
        totalStaked = totalStaked + _amount;

        // This update of rewardDebt is crucial for both new and existing stakers.
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;

        emit Stake(msg.sender, _amount);
    }

    /**
     * @dev Unstake tokens
     * @param _amount Amount of tokens to unstake
     */
    function unstake(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Cannot unstake more than staked");

        _updatePool();
        _updateUserRewards(msg.sender);

        user.amount = user.amount - _amount;
        totalStaked = totalStaked - _amount;

        stakingToken.transfer(msg.sender, _amount);

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;

        emit Unstake(msg.sender, _amount);
    }

    /**
     * @dev Claim accumulated rewards
     */
    function claimReward() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();
        _updateUserRewards(msg.sender);

        uint256 claimableReward = user.pendingRewards;

        if (claimableReward > 0) {
            require(
                rewardToken.balanceOf(address(this)) >= claimableReward,
                "Insufficient reward tokens in contract"
            );
            user.pendingRewards = 0;
            rewardToken.transfer(msg.sender, claimableReward);
            emit ClaimReward(msg.sender, claimableReward);
        }

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
    }

    /**
     * @dev Emergency withdraw without caring about rewards
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;

        require(amount > 0, "No tokens to withdraw");

        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
        totalStaked = totalStaked - amount;

        stakingToken.transfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    // ============ Owner Functions ============

    /**
     * @dev Update reward per block (only owner)
     * @param _rewardPerBlock New reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        _updatePool();
        rewardPerBlock = _rewardPerBlock;
        emit RewardPerBlockUpdated(_rewardPerBlock);
    }

    /**
     * @dev Update reward start block (only owner)
     * @param _rewardStartBlock New reward start block
     */
    function updateRewardStartBlock(
        uint256 _rewardStartBlock
    ) external onlyOwner {
        // ADDED: Prevent changing the start time after it has already passed.
        require(
            block.number < rewardStartBlock,
            "Reward period has already started"
        );
        require(
            _rewardStartBlock > block.number,
            "New start block must be in the future"
        );

        rewardStartBlock = _rewardStartBlock;
        // Also update the end block accordingly
        rewardEndBlock = _rewardStartBlock + rewardDuration;

        // The last reward block should align with the new start block.
        lastRewardBlock = _rewardStartBlock;

        emit RewardStartBlockUpdated(_rewardStartBlock);
    }

    /**
     * @dev Withdraw excess reward tokens (only owner)
     * @param _amount Amount of reward tokens to withdraw
     */
    function withdrawRewardTokens(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Cannot withdraw 0 tokens");
        require(
            rewardToken.balanceOf(address(this)) >= _amount,
            "Insufficient reward tokens"
        );

        rewardToken.transfer(msg.sender, _amount);
    }

    /**
     * @dev Emergency stop - withdraw all reward tokens (only owner)
     */
    function emergencyStop() external onlyOwner {
        uint256 balance = rewardToken.balanceOf(address(this));

        if (balance > 0) {
            rewardToken.transfer(msg.sender, balance);
        }

        rewardPerBlock = 0;
        emit RewardPerBlockUpdated(0);
    }
}
