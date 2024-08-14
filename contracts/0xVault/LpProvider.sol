// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

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
 */
contract LpProvider is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // Constants
    uint256 public constant ONE = 10**18;

    // State variables
    address public vault;
    address private _trustedSigner;
    address public coldWallet;
    address public oracle;
    uint256 public startEpochTimestamp;
    uint256 public epochPeriod;
    uint256 public withdrawalDelayTime;

    // Mappings
    mapping(address => bool) public isLPProvider;
    mapping(address => uint256) public lpProvidedAmount;
    mapping(address => uint256) public fundAmount; // total token amount
    mapping(address => uint256) public totalNAVs; // total NAVs, 10^18 decimals
    mapping(address => mapping(address => uint256)) public userNAVs; // token => user => NAV, 10^18 decimals
    mapping(address => uint256) public navPrices; // token => NAV price in USD, 10^18 decimals
    mapping(address => mapping(address => ReqWithdraw)) public reqWithdraws; // token => user => ReqWithdraws

    // Structs
    struct ReqWithdraw {
        uint256 navAmount;
        uint256 timestamp;
    }

    // Events
    event LPProvided(address indexed user, address indexed token, uint256 amount);
    event LPWithdrawn(address indexed user, address indexed token, uint256 amount);
    event DepositFund(address indexed user, address indexed token, uint256 amount, uint256 fundAmount);
    event WithdrawFund(address indexed user, address indexed token, uint256 amount, uint256 fundAmount);
    event WithdrawRequested(address indexed user, address indexed token, uint256 navAmount, uint256 timestamp);
    event LPProviderStatusChanged(address indexed lpProvider, bool isProvider);
    event VaultChanged(address indexed newVault);
    event ColdWalletChanged(address indexed newColdWallet);
    event OracleChanged(address indexed newOracle);
    event EpochParametersChanged(uint256 newStartEpochTimestamp, uint256 newEpochPeriod);
    event WithdrawalDelayTimeChanged(uint256 newWithdrawalDelayTime);
    event RewardDepositedForMarketMaker(address indexed token, uint256 amount);
    event NAVPriceUpdated(address indexed token, uint256 newPrice);

    // Modifiers
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    // Initialization
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

        emit VaultChanged(_vault);
        emit OracleChanged(_oracle);
        emit EpochParametersChanged(_startEpochTimestamp, _epochPeriod);
        emit WithdrawalDelayTimeChanged(_withdrawalDelayTime);
        emit ColdWalletChanged(_coldWallet);
    }

    // Private functions
    function _calcNAVAmount(address token, uint256 amount) private view returns (uint256) {
        if (totalNAVs[token] == 0) {
            return amount * IOracle(oracle).getPrice(token) * ONE / navPrices[token];
        }
        uint256 usdAmount = amount * IOracle(oracle).getPrice(token);
        return (usdAmount * ONE / navPrices[token]);
    }

    function _depositFund(address token, uint256 amount) private {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, coldWallet, amount),
            "Transfer failed"
        );
        if (navPrices[token] == 0) {
            navPrices[token] = 1 * ONE; // for first time
        }

        uint256 navs = _calcNAVAmount(token, amount);
        userNAVs[token][msg.sender] += navs;
        fundAmount[token] += amount;
        totalNAVs[token] += navs;
        emit DepositFund(msg.sender, token, amount, fundAmount[token]);
    }

    function _withdrawFund(address token, uint256 navsAmount) private {
        require(navsAmount > 0, "Amount must be greater than zero");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");

        userNAVs[token][msg.sender] -= navsAmount;
        totalNAVs[token] -= navsAmount;
        uint256 tokenAmount = navsAmount * fundAmount[token] / totalNAVs[token];
        fundAmount[token] -= tokenAmount;

        require(
            IERC20(token).transfer(msg.sender, tokenAmount),
            "Transfer failed"
        );

        emit WithdrawFund(msg.sender, token, tokenAmount, fundAmount[token]);
    }

    // External functions
    function depositFund(address token, uint256 amount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        _depositFund(token, amount);
    }

    function requestWithdrawFund(address token, uint256 navsAmount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");
        uint256 withdrawTimestamp = block.timestamp + withdrawalDelayTime;
        reqWithdraws[token][msg.sender] = ReqWithdraw(navsAmount, withdrawTimestamp);
        emit WithdrawRequested(msg.sender, token, navsAmount, withdrawTimestamp);
    }

    function withdrawFund(address token) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        ReqWithdraw memory reqWithdraw = reqWithdraws[token][msg.sender];
        require(block.timestamp >= reqWithdraw.timestamp, "Withdrawal delay not met");
        _withdrawFund(token, reqWithdraw.navAmount);
        delete reqWithdraws[token][msg.sender];
    }

    function provideLiquidity(address token, uint256 amount) external nonReentrant {
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

    function withdrawAllLiquidity(address token) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(IVault(vault).isTokenSupported(token), "Token not supported");
        uint256 amount = lpProvidedAmount[token];
        require(amount > 0, "No liquidity to withdraw");
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );

        lpProvidedAmount[token] = 0;

        emit LPWithdrawn(msg.sender, token, amount);
    }

    // Vault-only functions
    function increaseLpProvidedAmount(address token, uint256 amount) external onlyVault {
        lpProvidedAmount[token] += amount;
        emit LPProvided(address(this), token, amount);
    }

    function decreaseLpProvidedAmount(address token, uint256 amount) external onlyVault {
        require(lpProvidedAmount[token] >= amount, "Insufficient LP amount");
        require(
            IERC20(token).transfer(vault, amount),
            "Transfer failed"
        );
        lpProvidedAmount[token] -= amount;
        emit LPWithdrawn(address(this), token, amount);
    }

    // Owner-only functions
    function setLPProvider(address[] calldata lpProvider, bool[] calldata isProvider) external onlyOwner {
        require(lpProvider.length == isProvider.length, "Invalid input");
        for (uint256 i = 0; i < lpProvider.length; i++) {
            isLPProvider[lpProvider[i]] = isProvider[i];
            emit LPProviderStatusChanged(lpProvider[i], isProvider[i]);
        }
    }

    function setNAVPrice(address[] calldata tokens, uint256[] calldata prices) external onlyOwner {
        require(tokens.length == prices.length, "Invalid input");
        for (uint256 i = 0; i < tokens.length; i++) {
            navPrices[tokens[i]] = prices[i];
            emit NAVPriceUpdated(tokens[i], prices[i]);
        }
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault address");
        vault = _vault;
        emit VaultChanged(_vault);
    }

    function setColdWallet(address _coldWallet) external onlyOwner {
        require(_coldWallet != address(0), "Invalid cold wallet address");
        coldWallet = _coldWallet;
        emit ColdWalletChanged(_coldWallet);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle address");
        oracle = _oracle;
        emit OracleChanged(_oracle);
    }

    function setEpochParameters(uint256 _startEpochTimestamp, uint256 _epochPeriod) external onlyOwner {
        startEpochTimestamp = _startEpochTimestamp;
        epochPeriod = _epochPeriod;
        emit EpochParametersChanged(_startEpochTimestamp, _epochPeriod);
    }

    function setWithdrawalDelayTime(uint256 _withdrawalDelayTime) external onlyOwner {
        withdrawalDelayTime = _withdrawalDelayTime;
        emit WithdrawalDelayTimeChanged(_withdrawalDelayTime);
    }

    function depositRewardForMarketMaker(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        fundAmount[token] += amount;
        emit RewardDepositedForMarketMaker(token, amount);
    }

    function updateNAVPrice(address token, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid NAV price");
        navPrices[token] = newPrice;
        emit NAVPriceUpdated(token, newPrice);
    }
}