pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SimpleStaking.sol";

/**
 * @title PoolGen - Simple Staking Pool Factory
 * @dev A factory contract for deploying SimpleStaking instances with tax mechanism
 */
contract PoolGen {
    // ============ Constants ============
    
    // Native token address that is exempt from tax
    address public constant NATIVE_TOKEN = 0x091b3aF925a38b786f9Db20E435C3880545134B4;
    
    // Tax recipient address
    address public constant TAX_RECIPIENT = 0x1411506967FF752318Cd07Ae0Af06dDDac0948aE;
    
    // Tax rate: 0.1% = 10 / 10000
    uint256 public constant TAX_RATE = 25;
    uint256 public constant TAX_DENOMINATOR = 10000;

    // ============ State Variables ============
    
    // No state variables needed - contract is stateless for maximum scalability

    // ============ Events ============
    
    event PoolDeployed(
        address indexed pool,
        address indexed deployer,
        address indexed stakingToken,
        address rewardToken,
        uint256 rewardStartBlock,
        uint256 rewardDuration,
        uint256 rewardPerBlock,
        uint256 totalRewards,
        uint256 taxAmount
    );
    
    event TaxCollected(
        address indexed rewardToken,
        uint256 taxAmount,
        address indexed recipient
    );

    // ============ View Functions ============
    
    /**
     * @dev Calculate the tax amount for a given reward amount and token
     * @param _rewardToken Address of the reward token
     * @param _rewardAmount Total reward amount
     * @return taxAmount Amount that will be taxed
     * @return netAmount Amount after tax deduction
     */
    function calculateTax(
        address _rewardToken,
        uint256 _rewardAmount
    ) public pure returns (uint256 taxAmount, uint256 netAmount) {
        if (_rewardToken == NATIVE_TOKEN) {
            return (0, _rewardAmount);
        }
        
        taxAmount = (_rewardAmount * TAX_RATE) / TAX_DENOMINATOR;
        netAmount = _rewardAmount - taxAmount;
    }
    
    /**
     * @dev Calculate reward per block based on net amount and duration
     * @param _netAmount Net reward amount after tax
     * @param _rewardDuration Duration in blocks
     * @return rewardPerBlock Calculated reward per block
     */
    function calculateRewardPerBlock(
        uint256 _netAmount,
        uint256 _rewardDuration
    ) public pure returns (uint256 rewardPerBlock) {
        require(_rewardDuration > 0, "Duration must be greater than 0");
        return _netAmount / _rewardDuration;
    }

    // ============ Main Functions ============
    
    /**
     * @dev Deploy a new SimpleStaking pool
     * @param _stakingToken Address of the token to be staked
     * @param _rewardToken Address of the reward token
     * @param _rewardStartBlock Block number when rewards start
     * @param _rewardDuration Duration of rewards in blocks
     * @param _rewardAmount Total amount of reward tokens to fund the pool
     * @return poolAddress Address of the newly deployed pool
     */
    function deployPool(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardStartBlock,
        uint256 _rewardDuration,
        uint256 _rewardAmount
    ) external returns (address poolAddress) {
        require(_stakingToken != address(0), "Invalid staking token address");
        require(_rewardToken != address(0), "Invalid reward token address");
        require(_rewardStartBlock > block.number, "Start block must be in the future");
        require(_rewardDuration > 0, "Duration must be greater than 0");
        require(_rewardAmount > 0, "Reward amount must be greater than 0");
        
        // Transfer reward tokens from user to this contract
        IERC20(_rewardToken).transferFrom(msg.sender, address(this), _rewardAmount);
        
        // Calculate tax and net amount
        (uint256 taxAmount, uint256 netAmount) = calculateTax(_rewardToken, _rewardAmount);
        
        // Send tax to tax recipient if applicable
        if (taxAmount > 0) {
            IERC20(_rewardToken).transfer(TAX_RECIPIENT, taxAmount);
            emit TaxCollected(_rewardToken, taxAmount, TAX_RECIPIENT);
        }
        
        // Calculate reward per block based on net amount
        uint256 rewardPerBlock = calculateRewardPerBlock(netAmount, _rewardDuration);
        
        // Deploy new SimpleStaking contract
        SimpleStaking newPool = new SimpleStaking(
            _stakingToken,
            _rewardToken,
            _rewardStartBlock,
            _rewardDuration,
            rewardPerBlock
        );
        
        poolAddress = address(newPool);
        
        // Transfer net reward amount to the new pool
        IERC20(_rewardToken).transfer(poolAddress, netAmount);
        
        emit PoolDeployed(
            poolAddress,
            msg.sender,
            _stakingToken,
            _rewardToken,
            _rewardStartBlock,
            _rewardDuration,
            rewardPerBlock,
            netAmount,
            taxAmount
        );
        
        return poolAddress;
    }
    
    /**
     * @dev Emergency function to recover stuck tokens (if any)
     * @param _token Token address to recover
     * @param _amount Amount to recover
     * @param _recipient Recipient address
     */
    function emergencyRecoverTokens(
        address _token,
        uint256 _amount,
        address _recipient
    ) external {
        require(msg.sender == TAX_RECIPIENT, "Only tax recipient can recover tokens");
        require(_recipient != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20(_token).transfer(_recipient, _amount);
    }
}