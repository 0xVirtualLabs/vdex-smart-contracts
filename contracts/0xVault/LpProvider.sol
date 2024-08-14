// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Crypto} from "./libs/Crypto.sol";
import {IOracle} from "./interfaces/IOracle.sol";

contract LpProvider is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public constant ONE = 10**18;
    address public vault;
    address private _trustedSigner;
    address public coldWallet;
    address public oracle;
    uint256 public startEpochTimestamp;
    uint256 public epochPeriod;
    uint256 public withdrawalDelayTime;

    mapping(address => bool) public isLPProvider;
    mapping(address => uint256) public lpProvidedAmount;

    mapping(address => uint256) public fundAmount;
    mapping(address => mapping(address => uint256)) public userNAVs; // token => user => NAV
    mapping(address => uint256) public navPrices; // token => NAV price in USD
    mapping(address => mapping(address => ReqWithdraw)) public reqWithdraws; // token => user => ReqWithdraws

    struct ReqWithdraw {
        uint256 navAmount;
        uint256 timestamp;
    }

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

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

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
    }

    function _depositFund (
        address token,
        uint256 amount
    ) internal {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, coldWallet, amount),
            "Transfer failed"
        );

        uint256 navs = _calcNAVAmount(token, amount);
        userNAVs[token][msg.sender] += navs;
        fundAmount[token] += navs;
        emit DepositFund(msg.sender, token, amount, fundAmount[token]);
    }

    function _calcNAVAmount(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        uint256 usdAmount = amount * IOracle(oracle).getPrice(token);
        return usdAmount * ONE / navPrices[token];
    }

    function depositFund(address token, uint256 amount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        _depositFund(token, amount);
    }

    function _withdrawFund(
        address token,
        uint256 navsAmount
    ) private {
        require(navsAmount > 0, "Amount must be greater than zero");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");

        userNAVs[token][msg.sender] -= navsAmount;
        fundAmount[token] -= navsAmount;
        uint256 tokenAmount = navsAmount / IOracle(oracle).getPrice(token) / ONE;

        require(
            IERC20(token).transfer(msg.sender, tokenAmount),
            "Transfer failed"
        );

        emit WithdrawFund(msg.sender, token, tokenAmount, fundAmount[token]);
    }

    // new request will override old request
    function requestWithdrawFund(
        address token, uint256 navsAmount
    ) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(userNAVs[token][msg.sender] >= navsAmount, "Insufficient fund");
        reqWithdraws[token][msg.sender] = ReqWithdraw(navsAmount, block.timestamp + withdrawalDelayTime);
    }

    function withdrawFund(
        address token
    ) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        ReqWithdraw memory reqWithdraw = reqWithdraws[token][msg.sender];
        _withdrawFund(token, reqWithdraw.navAmount);
    }

    function setLPProvider(
        address[] calldata lpProvider,
        bool[] calldata isProvider
    ) external onlyOwner {
        require(lpProvider.length == isProvider.length, "Invalid input");
        for (uint256 i = 0; i < lpProvider.length; i++) {
            isLPProvider[lpProvider[i]] = isProvider[i];
        }
    }

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

    function withdrawAllLiquidity(address token) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(IVault(vault).isTokenSupported(token), "Token not supported");
        require(
            IERC20(token).transfer(msg.sender, lpProvidedAmount[token]),
            "Transfer failed"
        );

        lpProvidedAmount[token] = 0;

        emit LPWithdrawn(msg.sender, token, lpProvidedAmount[token]);
    }

    function increaseLpProvidedAmount(
        address token,
        uint256 amount
    ) external onlyVault {
        lpProvidedAmount[token] += amount;
    }

    function decreaseLpProvidedAmount(
        address token,
        uint256 amount
    ) external onlyVault {
        require(
            IERC20(token).transfer(vault, amount),
            "Transfer failed"
        );
        lpProvidedAmount[token] -= amount;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setColdWallet(address _coldWallet) external onlyOwner {
        coldWallet = _coldWallet;
    }

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
    }
}
