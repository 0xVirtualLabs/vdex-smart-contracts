// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

// Import necessary OpenZeppelin contracts and interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Crypto} from "./libs/Crypto.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title LpProvider
 * @dev A contract for managing liquidity provision and fund management
 * This contract allows LP providers to deposit funds, request withdrawals,
 * and manage liquidity for different tokens.
 */
contract LpProvider is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // Constants
    uint256 public constant NAV_DECIMALS = 18; // Used for precision in calculations

    // State variables
    address public vault; // Address of the associated vault contract
    address public coldWallet; // Address of the cold wallet for fund storage
    address public oracle; // Address of the price oracle contract
    uint256 public startEpochTimestamp; // Timestamp of the start of the epoch
    uint256 public epochPeriod; // Duration of each epoch
    uint256 public withdrawalDelayTime; // Delay time for withdrawals
    uint256 public navPrice; // Number of epochs

    uint256 public totalNAV; // Total NAVs for all tokens (10^18 decimals)
    
    struct Epoch {
        uint256 startTimestamp; // Start timestamp of the epoch
        uint256 initialNavQuantity; // Initial NAV quantity at the start of the epoch
        uint256 navInitialPrice; // NAV price at the start of the epoch
        mapping(address => uint256) tokensDeposited; // NAV quantity for each token
        mapping(address => uint256) withdrawRequested; // NAV quantity withdrawn for each token
    }

    uint265 public currentEpoch; // Current epoch number
    mapping(uint256 => Epoch) public epochs; // Mapping of epoch number to epoch data

    // Mappings
    mapping(address => bool) public isLPProvider; // Tracks whether an address is an LP provider
    mapping(address => uint256) public lpProvidedAmount; // Amount of liquidity provided by each LP provider
    mapping(address => uint256) public fundAmount; // Total token amount for each token
    mapping(address => uint256) public totalNAVs; // Total NAVs for each token (10^18 decimals)
    mapping(address => mapping(address => uint256)) public userNAVs; // NAVs for each user and token (10^18 decimals)
    mapping(address => uint256) public navPrices; // NAV price in USD for each token (10^18 decimals)
    //Why there is a separate nav price in USD for each token. There should be only one nav price in USD for all tokens.?
    mapping(address => mapping(address => ReqWithdraw)) public reqWithdraws; // Withdrawal requests for each user and token

    // Structs
    struct ReqWithdraw {
        uint256 navAmount; // Amount of NAVs requested for withdrawal
        uint256 timestamp; // Timestamp when the withdrawal can be executed
    }

    // Events
    event LPProvided(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event LPWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event DepositFund(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fundAmount
    );
    event WithdrawFund(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fundAmount
    );
    event WithdrawRequested(
        address indexed user,
        address indexed token,
        uint256 navAmount,
        uint256 timestamp
    );
    event LPProviderStatusChanged(address indexed lpProvider, bool isProvider);
    event VaultChanged(address indexed newVault);
    event ColdWalletChanged(address indexed newColdWallet);
    event OracleChanged(address indexed newOracle);
    event EpochParametersChanged(
        uint256 newStartEpochTimestamp,
        uint256 newEpochPeriod
    );
    event WithdrawalDelayTimeChanged(uint256 newWithdrawalDelayTime);
    event RewardDepositedForMarketMaker(address indexed token, uint256 amount);
    event NAVPriceUpdated(address indexed token, uint256 newPrice);

    // Modifiers
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    // Initialization function
    function initialize(
        address _owner,
        address _vault,
        address _oracle,
        uint256 _epochPeriod,
        uint256 _startEpochTimestamp,
        uint256 _withdrawalDelayTime,
        address _coldWallet
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        vault = _vault;
        oracle = _oracle;
        epochPeriod = _epochPeriod;
        startEpochTimestamp = _startEpochTimestamp;
        withdrawalDelayTime = _withdrawalDelayTime;
        coldWallet = _coldWallet;

        // Emit events for initial parameter settings
        emit VaultChanged(_vault);
        emit OracleChanged(_oracle);
        emit EpochParametersChanged(_startEpochTimestamp, _epochPeriod);
        emit WithdrawalDelayTimeChanged(_withdrawalDelayTime);
        emit ColdWalletChanged(_coldWallet);
    }

    // Private functions

    /**
     * @dev Calculates the NAV amount based on the token amount
     * @param token The address of the token
     * @param amount The amount of tokens
     * @return The calculated NAV amount
     */
    function _calcNAVAmount(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        uint256 priceDecimals = IOracle(oracle).decimals();
        uint256 usdAmount = amount * IOracle(oracle).getPrice(token);
        if (NAV_DECIMALS >= priceDecimals) {
            return
                (usdAmount * (10 ** (NAV_DECIMALS - priceDecimals))) /
                navPrices[token];
        } else {
            return
                (usdAmount / (10 ** (priceDecimals - NAV_DECIMALS))) /
                navPrices[token];
        }
    }

    /**
     * @dev Calculates the token amount based on the NAV amount
     * @param token The address of the token
     * @param navAmount The navAmount of tokens
     * @return The calculated amount
     */
    function _calcAmountFromNAV(
        address token,
        uint256 navAmount
    ) private view returns (uint256) {
        uint256 priceDecimals = IOracle(oracle).decimals();
        if (NAV_DECIMALS >= priceDecimals) {
            return
                ((navAmount * navPrices[token]) /
                    (10 ** (NAV_DECIMALS - priceDecimals))) /
                IOracle(oracle).getPrice(token);
        } else {
            return
                ((navAmount * navPrices[token]) *
                    (10 ** (priceDecimals - NAV_DECIMALS))) /
                IOracle(oracle).getPrice(token);
        }
    }

    /**
     * @dev Deposits funds into the contract
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     */
    function _depositFund(address token, uint256 amount) private {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, coldWallet, amount),
            "Transfer failed"
        );
        if (navPrices[token] == 0) {
            navPrices[token] = 1 * (10 ** NAV_DECIMALS); // Set initial NAV price to 1 for first time
        }

        uint256 navs = _calcNAVAmount(token, amount);
        userNAVs[token][msg.sender] += navs;
        fundAmount[token] += amount;
        totalNAVs[token] += navs;
        emit DepositFund(msg.sender, token, amount, fundAmount[token]);
    }

    /**
     * @dev Withdraws funds from the contract
     * @param token The address of the token to withdraw
     * @param navsAmount The amount of NAVs to withdraw
     */
    function _withdrawFund(address token, uint256 navsAmount) private {
        require(navsAmount > 0, "Amount must be greater than zero");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");

        uint256 tokenAmount = _calcAmountFromNAV(token, navsAmount);
        userNAVs[token][msg.sender] -= navsAmount;
        totalNAVs[token] -= navsAmount;
        fundAmount[token] -= tokenAmount;

        require(
            IERC20(token).transfer(msg.sender, tokenAmount),
            "Transfer failed"
        );

        emit WithdrawFund(msg.sender, token, tokenAmount, fundAmount[token]);
    }

    // External functions

    /**
     * @dev Allows LP providers to deposit funds
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     */
    function depositFund(address token, uint256 amount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        _depositFund(token, amount);
    }

    /**
     * @dev Allows LP providers to request a withdrawal
     * @param token The address of the token to withdraw
     * @param navsAmount The amount of NAVs to withdraw
     */
    function requestWithdrawFund(
        address token,
        uint256 navsAmount
    ) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");
        uint256 withdrawTimestamp = block.timestamp + withdrawalDelayTime;
        reqWithdraws[token][msg.sender] = ReqWithdraw(
            navsAmount,
            withdrawTimestamp
        );
        emit WithdrawRequested(
            msg.sender,
            token,
            navsAmount,
            withdrawTimestamp
        );
    }

    /**
     * @dev Allows LP providers to withdraw funds after the delay period
     * @param token The address of the token to withdraw
     */
    function withdrawFund(address token) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        ReqWithdraw memory reqWithdraw = reqWithdraws[token][msg.sender];
        require(
            block.timestamp >= reqWithdraw.timestamp,
            "Withdrawal delay not met"
        );
        _withdrawFund(token, reqWithdraw.navAmount);
        delete reqWithdraws[token][msg.sender];
    }

    /**
     * @dev Allows LP providers to provide liquidity
     * @param token The address of the token to provide liquidity for
     * @param amount The amount of tokens to provide as liquidity
     */
    function provideLiquidity(
        address token,
        uint256 amount
    ) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        lpProvidedAmount[token] += amount;
        emit LPProvided(msg.sender, token, lpProvidedAmount[token]);
    }

    /**
     * @dev Allows LP providers to withdraw all their provided liquidity
     * @param token The address of the token to withdraw liquidity from
     */
    function withdrawAllLiquidity(address token) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(IVault(vault).isTokenSupported(token), "Token not supported");
        uint256 amount = lpProvidedAmount[token];
        require(amount > 0, "No liquidity to withdraw");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");

        lpProvidedAmount[token] = 0;

        emit LPWithdrawn(msg.sender, token, amount);
    }

    // Vault-only functions

    /**
     * @dev Increases the LP provided amount (can only be called by the vault)
     * @param token The address of the token
     * @param amount The amount to increase
     */
    function increaseLpProvidedAmount(
        address token,
        uint256 amount
    ) external onlyVault {
        lpProvidedAmount[token] += amount;
        emit LPProvided(address(this), token, amount);
    }

    /**
     * @dev Decreases the LP provided amount (can only be called by the vault)
     * @param token The address of the token
     * @param amount The amount to decrease
     */
    function decreaseLpProvidedAmount(
        address token,
        uint256 amount
    ) external onlyVault {
        require(lpProvidedAmount[token] >= amount, "Insufficient LP amount");
        require(IERC20(token).transfer(vault, amount), "Transfer failed");
        lpProvidedAmount[token] -= amount;
        emit LPWithdrawn(address(this), token, amount);
    }

    // Owner-only functions

    /**
     * @dev Sets the LP provider status for multiple addresses
     * @param lpProvider Array of LP provider addresses
     * @param isProvider Array of boolean values indicating LP provider status
     */
    function setLPProvider(
        address[] calldata lpProvider,
        bool[] calldata isProvider
    ) external onlyOwner {
        require(lpProvider.length == isProvider.length, "Invalid input");
        for (uint256 i = 0; i < lpProvider.length; i++) {
            isLPProvider[lpProvider[i]] = isProvider[i];
            emit LPProviderStatusChanged(lpProvider[i], isProvider[i]);
        }
    }

    /**
     * @dev Updates the NAV price for a token
     * @param token The address of the token
     * @param newPrice The new NAV price
     */
    function setNAVPrice(address token, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid NAV price");
        navPrices[token] = newPrice;
        emit NAVPriceUpdated(token, newPrice);
    }

    /**
     * @dev Sets the NAV prices for multiple tokens
     * @param tokens Array of token addresses
     * @param prices Array of NAV prices
     */
    function setNAVPrices(
        address[] calldata tokens,
        uint256[] calldata prices
    ) external onlyOwner {
        require(tokens.length == prices.length, "Invalid input");
        for (uint256 i = 0; i < tokens.length; i++) {
            navPrices[tokens[i]] = prices[i];
            emit NAVPriceUpdated(tokens[i], prices[i]);
        }
    }

    /**
     * @dev Sets the vault address
     * @param _vault The new vault address
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault address");
        vault = _vault;
        emit VaultChanged(_vault);
    }

    /**
     * @dev Sets the cold wallet address
     * @param _coldWallet The new cold wallet address
     */
    function setColdWallet(address _coldWallet) external onlyOwner {
        require(_coldWallet != address(0), "Invalid cold wallet address");
        coldWallet = _coldWallet;
        emit ColdWalletChanged(_coldWallet);
    }

    /**
     * @dev Sets the oracle address
     * @param _oracle The new oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle address");
        oracle = _oracle;
        emit OracleChanged(_oracle);
    }

    /**
     * @dev Sets the epoch parameters
     * @param _startEpochTimestamp The new start epoch timestamp
     * @param _epochPeriod The new epoch period
     */
    function setEpochParameters(
        uint256 _startEpochTimestamp,
        uint256 _epochPeriod
    ) external onlyOwner {
        startEpochTimestamp = _startEpochTimestamp;
        epochPeriod = _epochPeriod;
        emit EpochParametersChanged(_startEpochTimestamp, _epochPeriod);
    }

    /**
     * @dev Sets the withdrawal delay time
     * @param _withdrawalDelayTime The new withdrawal delay time
     */
    function setWithdrawalDelayTime(
        uint256 _withdrawalDelayTime
    ) external onlyOwner {
        withdrawalDelayTime = _withdrawalDelayTime;
        emit WithdrawalDelayTimeChanged(_withdrawalDelayTime);
    }

    /**
     * @dev Deposits rewards for market makers
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     */
    function depositRewardForMarketMaker(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        fundAmount[token] += amount;
        emit RewardDepositedForMarketMaker(token, amount);
    }
}
