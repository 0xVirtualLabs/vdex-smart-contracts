// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// Import necessary OpenZeppelin contracts and interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Crypto} from "./libs/Crypto.sol";

/**
 * @title LpProvider
 * @dev A contract for managing liquidity provision and fund management
 * This contract allows LP providers to deposit funds, request withdrawals,
 * and manage liquidity for different tokens.
 */
contract LpProvider is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    // State variables
    address public vault; // Address of the associated vault contract
    address public signer; // Address of the signer
    mapping(address => uint256) public pairId; // token => pairId

    // Mappings
    mapping(address => bool) public isLPProvider; // Tracks whether an address is an LP provider
    mapping(address => uint256) public lpProvidedAmount; // Amount of liquidity provided by each LP provider
    mapping(address => mapping(address => uint256)) public claimableAmount; // after withdraw, user can claim profit,user => token => amount
    mapping(bytes => bool) private _signatureUsed; // Tracks used signatures

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256(
            "WithdrawRequest(uint256 requestId,address user,address token,uint256 amount)"
        );
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
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
        uint256 amount,
        uint256 reqId
    );
    event LPProviderStatusChanged(address indexed lpProvider, bool isProvider);
    event VaultChanged(address indexed newVault);
    event RewardDepositedForMarketMaker(address indexed token, uint256 amount);

    // Modifiers
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    // Initialization function
    function initialize(address _owner, address _vault) public initializer {
        __Ownable_init(_owner);
        __EIP712_init("VDEXLP", "1.0.0");
        __ReentrancyGuard_init();
        vault = _vault;
        signer = _owner;

        // Emit events for initial parameter settings
        emit VaultChanged(_vault);
    }

    // External functions

    /**
     * @dev Allows the owner to withdraw a specific amount of tokens from the contract.
     * @param token The address of the token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Token transfer failed"
        );
    }

    /**
     * @dev Allows LP providers to deposit funds
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     */
    function depositFund(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(IVault(vault).isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        emit DepositFund(msg.sender, token, amount);
    }
    /**
     * @dev Withdraws funds with signature verification
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @param requestId Unique identifier for the withdrawal request
     * @param signature EIP712 signature from backend
     */
    function withdrawFund(
        address token,
        uint256 amount,
        uint256 requestId,
        bytes calldata signature
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        // Verify signature
        _verifyWithdrawProof(msg.sender, token, amount, requestId, signature);

        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");

        emit WithdrawFund(msg.sender, token, amount, requestId);
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
     * @dev Sets the signer address
     * @param _signer The new signer address
     */
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
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

    function _withdrawHash(
        address _user,
        address _token,
        uint256 _amount,
        uint256 _reqId
    ) private view returns (bytes32 hash) {
        hash = _hashTypedDataV4(
            keccak256(
                abi.encode(WITHDRAW_TYPEHASH, _reqId, _user, _token, _amount)
            )
        );
    }

    function _verifyWithdrawProof(
        address _user,
        address _token,
        uint256 _amount,
        uint256 _reqId,
        bytes memory _signature
    ) private {
        require(!_signatureUsed[_signature], "Signature already used");
        require(
            _verify(_withdrawHash(_user, _token, _amount, _reqId), _signature),
            "Not approval by system!"
        );
        _signatureUsed[_signature] = true;
    }

    function _verify(
        bytes32 _digest,
        bytes memory _signature
    ) private view returns (bool) {
        return signer == ECDSA.recover(_digest, _signature);
    }
}
