// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @custom:oz-upgrades-from Vault
 */
contract VaultV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public signatureExpiryTime;
    uint256 private constant SECP256K1_CURVE_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    uint32 private _requestIdCounter;

    mapping(uint32 => Dispute) public _disputes;
    mapping(bytes => bool) private _signatureUsed;
    mapping(bytes => bool) private _schnorrSignatureUsed;
    mapping(uint32 => uint32) private _latestSchnorrSignatureId;

    mapping(address => address) public combinedPublicKey;
    address private _trustedSigner;
    address[] private supportedTokens;

    // CHECKTHIS
    // for adding LP
    mapping(address => mapping(address => uint256)) public depositedAmount; // address => token => amount
    mapping(address => bool) public isLPProvider;
    mapping(address => uint256) public lpProvidedAmount; // token => amount

    struct TokenBalance {
        address token;
        uint256 balance;
    }

    struct WithdrawTrustlesslyParams {
        TokenBalance[] tokenBalances;
        uint64 timestamp;
        SchnorrSignature schnorr;
    }

    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event TrustedSignerChanged(
        address indexed prevSigner,
        address indexed newSigner
    );
    event WithdrawalRequested(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint32 requestId
    );
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    error InvalidSignature();
    error InvalidUsedSignature();
    error InvalidSchnorrSignature();
    error InvalidSP();
    error ECRecoverFailed();
    error InvalidAddress();
    error DisputeChallengeFailed();
    error SettleDisputeFailed();

    struct SchnorrSignature {
        bytes data;
        bytes signature;
        address combinedPublicKey;
    }

    struct Balance {
        address addr;
        uint256 balance;
    }

    struct SchnorrData {
        uint32 signatureId;
        address addr;
        Balance[] balances;
        string sigType;
        uint256 timestamp;
    }

    enum DisputeStatus {
        None,
        Opened,
        Challenged,
        Settled
    }

    struct Dispute {
        address user;
        address challenger;
        uint64 timestamp;
        Balance[] balances;
        uint8 status;
        uint32 sessionId;
    }

    event DisputeOpened(uint32 requestId, address indexed user);
    event DisputeChallenged(uint32 requestId, address indexed user);
    event DisputeSettled(uint32 requestId, address indexed user);

    function initialize(
        address _owner,
        address trustedSigner,
        uint256 _signatureExpiryTime
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(_owner);
        _trustedSigner = trustedSigner;
        signatureExpiryTime = _signatureExpiryTime;
    }

    // CHECKTHIS
    function setLPProvider(address[] calldata lpProvider, bool[] calldata isProvider) external {
        require(lpProvider.length == isProvider.length, "Invalid input");
        for (uint256 i = 0; i < lpProvider.length; i++) {
            isLPProvider[lpProvider[i]] = isProvider[i];
        }
    }

    // CHECKTHIS
    function provideLiquidity(address token, uint256 amount) external {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(amount > 0, "Amount must be greater than zero");
        require(isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        lpProvidedAmount[token] += amount;
    }

    // CHECKTHIS
    function withdrawAllLiquidity(address token) external {
        require(isLPProvider[msg.sender], "Not LP provider");
        require(isTokenSupported(token), "Token not supported");
        require(
            IERC20(token).transfer(msg.sender, lpProvidedAmount[token]),
            "Transfer failed"
        );

        lpProvidedAmount[token] = 0;

        // TODO: emit event
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // CHECKTHIS
        depositedAmount[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function addToken(address token) external onlyOwner {
        supportedTokens.push(token);
        emit TokenAdded(token);
    }

    function removeToken(address token) external onlyOwner {
        for (uint i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                if (i != supportedTokens.length - 1) {
                    supportedTokens[i] = supportedTokens[
                        supportedTokens.length - 1
                    ];
                }
                supportedTokens.pop();
                emit TokenRemoved(token);
                return;
            }
        }
    }

    function isTokenSupported(address token) public view returns (bool) {
        for (uint i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function withdrawTrustlessly(
        SchnorrSignature calldata _schnorr
    ) external nonReentrant {
        if (!_verifySchnorrSignature(_schnorr, combinedPublicKey[msg.sender])) {
            revert InvalidSchnorrSignature();
        }

        SchnorrData memory schnorrData = decodeSchnorrData(_schnorr.data);

        if (schnorrData.addr != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        _requestIdCounter = _requestIdCounter + 1;
        uint32 withdrawalId = _requestIdCounter;
        _disputes[withdrawalId].timestamp = uint64(block.timestamp);
        uint256 len = schnorrData.balances.length;
        for (uint256 i = 0; i < len; i++) {
            _disputes[withdrawalId].balances.push(schnorrData.balances[i]);
        }

        uint32 signatureId = schnorrData.signatureId;
        _latestSchnorrSignatureId[withdrawalId] = signatureId;

        _openDispute(withdrawalId, msg.sender);
    }

    function _openDispute(uint32 withdrawalId, address user) internal {
        Dispute storage dispute = _disputes[withdrawalId];

        dispute.status = uint8(DisputeStatus.Opened);
        dispute.user = user;

        emit DisputeOpened(withdrawalId, user);
    }

    function challengeDispute(
        uint32 withdrawalId,
        SchnorrSignature calldata _schnorr
    ) external nonReentrant {
        Dispute storage dispute = _disputes[withdrawalId];
        SchnorrData memory schnorrData = decodeSchnorrData(_schnorr.data);

        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );
        require(
            block.timestamp < dispute.timestamp + 7 days,
            "Dispute window closed"
        );

        if (
            !_verifySchnorrSignature(
                _schnorr,
                combinedPublicKey[schnorrData.addr]
            )
        ) {
            revert InvalidSchnorrSignature();
        }

        uint32 signatureId = schnorrData.signatureId;

        if (_latestSchnorrSignatureId[withdrawalId] < schnorrData.signatureId) {
            _latestSchnorrSignatureId[withdrawalId] = signatureId;

            dispute.challenger = msg.sender;
            delete dispute.balances;
            uint256 len = schnorrData.balances.length;
            for (uint256 i = 0; i < len; i++) {
                dispute.balances.push(schnorrData.balances[i]);
            }
            dispute.status = uint8(DisputeStatus.Challenged);

            emit DisputeChallenged(withdrawalId, schnorrData.addr);
        } else {
            revert DisputeChallengeFailed();
        }
    }

    function settleDispute(uint32 withdrawalId) external nonReentrant {
        Dispute storage dispute = _disputes[withdrawalId];
        if (block.timestamp < dispute.timestamp + 1800) { // fake 30p
            require(
                dispute.status != uint8(DisputeStatus.Challenged),
                "Invalid dispute status"
            );
        }
        require(
            dispute.status != uint8(DisputeStatus.Settled),
            "Invalid dispute status"
        );

        dispute.status = uint8(DisputeStatus.Settled);

        uint256 len = dispute.balances.length;

        for (uint256 i = 0; i < len; i++) {
            address token = dispute.balances[i].addr;
            uint256 amount = dispute.balances[i].balance;
            IERC20(token).transfer(dispute.user, amount);
            depositedAmount[dispute.user][dispute.balances[0].addr] = 0; // CHECKTHIS
            emit Withdrawn(msg.sender, token, amount);
        }


        emit DisputeSettled(withdrawalId, msg.sender);
    }

    /**
     * @dev Sets the trusted signer's address for validating Session and Participants information.
     *
     * Emits a {TrustedSignerChanged} event indicating the previous signer and the newly set signer.
     *
     * Requirements:
     * - The provided address must not be the zero address.
     *
     * @param _newSigner (address) The address of the trusted signer.
     */
    function setTrustedSigner(address _newSigner) public onlyOwner {
        if (_newSigner == address(0)) {
            revert InvalidAddress();
        }
        address prevSigner = _trustedSigner;
        _trustedSigner = _newSigner;

        emit TrustedSignerChanged(prevSigner, _newSigner);
    }

    function setSignatureExpiryTime(uint256 _expiryTime) external onlyOwner {
        signatureExpiryTime = _expiryTime;
    }

    function setCombinedPublicKey(
        address _user,
        address _combinedPublicKey
    ) external onlyOwner {
        combinedPublicKey[_user] = _combinedPublicKey;
    }

    /**
     * @dev Decodes bytes into Schnorr data.
     *
     * @param _data (bytes) The encoded Schnorr data.
     * @return (SchnorrData) The decoded Schnorr data.
     */
    function decodeSchnorrData(
        bytes memory _data
    ) public pure returns (SchnorrData memory) {
        (
            uint32 signatureId,
            address addr,
            Balance[] memory balances,
            string memory sigType,
            uint256 timestamp
        ) = abi.decode(_data, (uint32, address, Balance[], string, uint256));
        return SchnorrData(signatureId, addr, balances, sigType, timestamp);
    }

    /**
     * @dev Internal function to verify a Schnorr signature.
     *
     * @param _schnorr (SchnorrSignature) The Schnorr signature to be verified.
     *
     * @return (bool) True if the Schnorr signature is valid, otherwise false.
     */
    function _verifySchnorrSignature(
        SchnorrSignature memory _schnorr,
        address _combinedPublicKey
    ) internal returns (bool) {
        if (_schnorrSignatureUsed[_schnorr.signature]) {
            revert InvalidSchnorrSignature();
        }

        if (_schnorr.combinedPublicKey != _combinedPublicKey) {
            revert InvalidSchnorrSignature();
        }

        if (_schnorr.signature.length != 128) {
            revert InvalidSchnorrSignature();
        }

        (bytes32 px, bytes32 e, bytes32 s, uint8 parity) = abi.decode(
            _schnorr.signature,
            (bytes32, bytes32, bytes32, uint8)
        );
        bytes32 sp = bytes32(
            SECP256K1_CURVE_N -
                mulmod(uint256(s), uint256(px), SECP256K1_CURVE_N)
        );
        bytes32 ep = bytes32(
            SECP256K1_CURVE_N -
                mulmod(uint256(e), uint256(px), SECP256K1_CURVE_N)
        );

        if (sp == 0) {
            revert InvalidSP();
        }

        address R = ecrecover(sp, parity, px, ep);
        if (R == address(0)) {
            revert ECRecoverFailed();
        }

        if (
            e ==
            keccak256(
                abi.encodePacked(R, uint8(parity), px, keccak256(_schnorr.data))
            ) &&
            address(uint160(uint256(px))) == _schnorr.combinedPublicKey
        ) {
            _schnorrSignatureUsed[_schnorr.signature] = true;

            return true;
        }

        return false;
    }
}
