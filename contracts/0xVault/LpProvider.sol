// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Crypto} from "./libs/Crypto.sol";

contract LpProvider is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public vault;
    address private _trustedSigner;
    address public coldWallet;

    mapping(address => bool) public isLPProvider;
    mapping(address => uint256) public lpProvidedAmount;

    mapping(address => uint256) public fundAmount;
    mapping(address => mapping(uint32 => bool)) public usedRn;

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
    event TrustedSignerChanged(
        address indexed prevSigner,
        address indexed newSigner
    );

    struct WithdrawParams {
        address lpProvider;
        address token;
        uint256 amount;
        uint32 rn;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    function initialize(
        address _owner,
        address _vault,
        address _newTrustedSigner,
        address _coldWallet
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        vault = _vault;
        _trustedSigner = _newTrustedSigner;
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

        fundAmount[token] += amount;
    }

    function depositFund(address token, uint256 amount) external nonReentrant {
        require(isLPProvider[msg.sender], "Not LP provider");
        _depositFund(token, amount);
        emit DepositFund(msg.sender, token, amount, fundAmount[token]);
    }

    function addTotalFund(address token, uint256 amount) external nonReentrant onlyOwner {
        _depositFund(token, amount);
        emit DepositFund(msg.sender, token, amount, fundAmount[token]);
    }

    function withdrawFund(
        WithdrawParams memory withdrawParams,
        bytes calldata signature
    ) external nonReentrant {
        require(withdrawParams.amount > 0, "Amount must be greater than zero");
        require(withdrawParams.lpProvider == msg.sender, "Caller not correct");
        require(
            IVault(vault).isTokenSupported(withdrawParams.token),
            "Token not supported"
        );

        require(
            usedRn[withdrawParams.lpProvider][withdrawParams.rn] == false,
            "Invalid RN"
        );

        bytes32 _digest = keccak256(
            abi.encode(
                withdrawParams.lpProvider,
                withdrawParams.token,
                withdrawParams.amount,
                withdrawParams.rn
            )
        );

        _verifySignature(_digest, signature);

        require(
            IERC20(withdrawParams.token).transfer(
                msg.sender,
                withdrawParams.amount
            ),
            "Transfer failed"
        );

        usedRn[withdrawParams.lpProvider][withdrawParams.rn] = true;
        fundAmount[withdrawParams.token] -= withdrawParams.amount;

        emit WithdrawFund(
            withdrawParams.lpProvider,
            withdrawParams.token,
            withdrawParams.amount,
            fundAmount[withdrawParams.token]
        );
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

    function setTrustedSigner(address _newSigner) public onlyOwner {
        require(_newSigner != address(0), "Invalid address");
        address prevSigner = _trustedSigner;
        _trustedSigner = _newSigner;

        emit TrustedSignerChanged(prevSigner, _newSigner);
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setColdWallet(address _coldWallet) external onlyOwner {
        coldWallet = _coldWallet;
    }

    //  /**
    //  * @dev Internal function to check the validity of a signature against a digest and mark the signature as used.
    //  *
    //  * @param _digest (bytes32) The digest to be signed.
    //  * @param _signature (bytes) The signature to be verified.
    //  */
    function _verifySignature(
        bytes32 _digest,
        bytes calldata _signature
    ) internal view {
        bytes32 _ethSignedMessage = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _digest)
        );

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);

        address signer = ecrecover(_ethSignedMessage, v, r, s);

        require(signer == _trustedSigner, "Invalid signature");
    }

    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
