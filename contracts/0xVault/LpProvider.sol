// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// Import necessary OpenZeppelin contracts and interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
  ECDSAUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/cryptography/.sol";

import {IVault} from "./interfaces/IVault.sol";
import {Crypto} from "./libs/Crypto.sol";

/**
 * @title LpProvider
 * @dev A contract for managing liquidity provision and fund management
 * This contract allows LP providers to deposit funds, request withdrawals,
 * and manage liquidity for different tokens.
 */
contract LpProvider is OwnableUpgradeable, ReentrancyGuardUpgradeable, EIP712Upgradeable {
    // Constants
    uint256 public constant NAV_DECIMALS = 18; // Used for precision in calculations

    // State variables
    address public vault; // Address of the associated vault contract
    address public coldWallet; // Address of the cold wallet for fund storage
    uint256 public startEpochTimestamp; // Timestamp of the start of the epoch
    uint256 public epochPeriod; // Duration of each epoch
    uint256 public withdrawalDelayTime; // Delay time for withdrawals
    mapping(address => uint256) public pairId; // token => pairId

    // Mappings
    mapping(address => bool) public isLPProvider; // Tracks whether an address is an LP provider
    mapping(address => uint256) public lpProvidedAmount; // Amount of liquidity provided by each LP provider
    mapping(address => mapping(address => uint256)) public claimableAmount; // after withdraw, user can claim profit,user => token => amount

    // Structs
    struct ReqWithdraw {
        uint256 navAmount; // Amount of NAVs requested for withdrawal
        uint256 timestamp; // Timestamp when the withdrawal can be executed
    }

    // Add this struct for EIP712 signature verification
    struct WithdrawRequest {
        uint256 requestId;
        address user;
        address token;
        uint256 amount;
        uint256 deadline;
    }

    // Add EIP712 domain separator and type hash constants
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256(
        "WithdrawRequest(uint256 requestId,address user,address token,uint256 amount,uint256 deadline)"
    );
    bytes32 public immutable DOMAIN_SEPARATOR;

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
        uint256 amount
    );
    event WithdrawFund(
        address indexed user,
        address indexed token,
        uint256 amount
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
        uint256 _epochPeriod,
        uint256 _startEpochTimestamp,
        uint256 _withdrawalDelayTime,
        address _coldWallet
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        vault = _vault;
        epochPeriod = _epochPeriod;
        startEpochTimestamp = _startEpochTimestamp;
        withdrawalDelayTime = _withdrawalDelayTime;
        coldWallet = _coldWallet;

        // Emit events for initial parameter settings
        emit VaultChanged(_vault);
        emit EpochParametersChanged(_startEpochTimestamp, _epochPeriod);
        emit WithdrawalDelayTimeChanged(_withdrawalDelayTime);
        emit ColdWalletChanged(_coldWallet);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("LpProvider"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    // External functions

    /**
     * @dev Allows LP providers to deposit funds
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     */
    function depositFund(address token, uint256 amount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, coldWallet, amount),
            "Transfer failed"
        );

        emit DepositFund(msg.sender, token, amount);
    }

    /**
     * @dev Withdraws funds with signature verification
     * @param requestId Unique identifier for the withdrawal request
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @param deadline Timestamp after which the signature is invalid
     * @param signature EIP712 signature from backend
     */
    function withdrawFund(
        uint256 requestId,
        address token,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(amount > 0, "Amount must be greater than zero");

        // Verify signature
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAW_TYPEHASH,
                requestId,
                msg.sender,
                token,
                amount,
                deadline
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        address signer = ECDSAUpgradeable.recover(hash, signature);
        require(signer == owner(), "Invalid signature");

        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );

        emit WithdrawFund(msg.sender, token, amount);
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
        address user,
        address token,
        uint256 amount
    ) external onlyVault {
        claimableAmount[user][token] += amount;
    }

    /**
     * @dev Allows the vault to claim profits for a specific token
     * @param token The address of the token
     * @param amount The amount of tokens to claim as profit
     */
    function claimProfit(
        address token,
        uint256 amount
    ) external onlyVault {
        require(IERC20(token).transfer(vault, amount), "Transfer failed");
        lpProvidedAmount[token] -= amount;
        claimableAmount[msg.sender][token] -= amount;
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
    ) external {
        require(lpProvider.length == isProvider.length, "Invalid input");
        for (uint256 i = 0; i < lpProvider.length; i++) {
            isLPProvider[lpProvider[i]] = isProvider[i];
            emit LPProviderStatusChanged(lpProvider[i], isProvider[i]);
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
     * @dev Sets the pair ID for tokens
     * @param tokens Array of token addresses
     * @param ids Array of corresponding pair IDs
     */
    function setPairIDForTokens(
        address[] calldata tokens,
        uint256[] calldata ids
    ) external onlyOwner {
        require(tokens.length == ids.length, "Invalid input");
        for (uint256 i = 0; i < tokens.length; i++) {
            pairId[tokens[i]] = ids[i];
        }
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

     function _withdrawHash(
        address _user,
        uint256 _amount,
        uint256 _nonce
    ) private view returns (bytes32 hash) {
        hash = _hashTypedDataV4(
            keccak256(abi.encode(CLAIM_TYPEHASH, _user, _amount, _nonce))
        );
    }
}
