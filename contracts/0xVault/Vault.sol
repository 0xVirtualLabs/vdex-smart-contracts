// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IOracle} from "./IOracle.sol";

/**
 * @custom:oz-upgrades-from Vault
 */
contract Vault is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public signatureExpiryTime;
    uint256 private constant SECP256K1_CURVE_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    uint32 private _requestIdCounter;

    mapping(uint32 => Dispute) public _disputes;
    mapping(uint32 => ClosePositionDispute) private _positionDisputes;
    mapping(bytes => bool) private _signatureUsed;
    mapping(bytes => bool) private _schnorrSignatureUsed;
    mapping(uint32 => uint32) private _latestSchnorrSignatureId;

    mapping(address => address) public combinedPublicKey;
    address private _trustedSigner;
    address[] private supportedTokens;
    address public oracle;
    uint256 constant ONE = 1e9;

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
    event PositionClosed(uint256 positionId, uint256 tokenAmount);
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

    struct WithdrawParams {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    struct SchnorrDataWithdraw {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    // for liquidation case
    struct OraclePrice {
        uint256 positionId;
        address token;
        uint256 price;
        uint64 timestamp;
    }

    struct Balance {
        address addr;
        uint256 balance;
    }

    struct Position {
        uint256 positionId;
        address token;
        uint256 quantity;
        bool isLong;
        uint256 margin;
        uint256 entryPrice;
        uint256 createdTimestamp;
    }

    struct SchnorrData {
        uint32 signatureId;
        address addr;
        Balance[] balances;
        string sigType;
        uint256 timestamp;
    }

    struct ClosePositionSchnorrData {
        uint32 signatureId;
        address addr;
        Position[] positions;
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

    struct ClosePositionDispute {
        address user;
        address challenger;
        uint64 timestamp;
        Position[] positions;
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

    function deposit(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(
        WithdrawParams memory withdrawParams,
        bytes calldata signature
    ) external nonReentrant {
        require(withdrawParams.amount > 0, "Amount must be greater than zero");
        require(withdrawParams.trader == msg.sender, "Caller not correct");
        require(isTokenSupported(withdrawParams.token), "Token not supported");

        require(
            block.timestamp - withdrawParams.timestamp < signatureExpiryTime,
            "Signature Expired"
        );

        bytes32 _digest = keccak256(
            abi.encode(
                withdrawParams.trader,
                withdrawParams.token,
                withdrawParams.amount,
                withdrawParams.timestamp
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

        emit Withdrawn(msg.sender, withdrawParams.token, withdrawParams.amount);
    }

    function withdrawSchnorr(
        address _combinedPublicKey,
        SchnorrSignature calldata _schnorr
    ) external nonReentrant {
        if (!_verifySchnorrSignature(_schnorr, combinedPublicKey[msg.sender])) {
            revert InvalidSchnorrSignature();
        }

        SchnorrDataWithdraw memory schnorrData = decodeSchnorrDataWithdraw(
            _schnorr.data
        );

        require(schnorrData.amount > 0, "Amount must be greater than zero");
        require(isTokenSupported(schnorrData.token), "Token not supported");

        require(
            block.timestamp - schnorrData.timestamp < signatureExpiryTime,
            "Signature Expired"
        );

        if (schnorrData.trader != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        combinedPublicKey[msg.sender] = _combinedPublicKey;

        require(
            IERC20(schnorrData.token).transfer(msg.sender, schnorrData.amount),
            "Transfer failed"
        );

        emit Withdrawn(msg.sender, schnorrData.token, schnorrData.amount);
    }

    function setOracle(address newOracle) external onlyOwner {
        oracle = newOracle;
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

    function openClosePositionRequest(
        SchnorrSignature calldata _schnorr
    ) external nonReentrant {
        if (!_verifySchnorrSignature(_schnorr, combinedPublicKey[msg.sender])) {
            revert InvalidSchnorrSignature();
        }

        ClosePositionSchnorrData
            memory schnorrData = decodeClosePositionSchnorrData(_schnorr.data);

        if (schnorrData.addr != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        _requestIdCounter = _requestIdCounter + 1;
        uint32 requestId = _requestIdCounter;
        _positionDisputes[requestId].timestamp = uint64(block.timestamp);
        uint256 len = schnorrData.positions.length;
        for (uint256 i = 0; i < len; i++) {
            _positionDisputes[requestId].positions.push(
                schnorrData.positions[i]
            );
        }

        uint32 signatureId = schnorrData.signatureId;
        _latestSchnorrSignatureId[requestId] = signatureId;

        _openDispute(requestId, msg.sender);
    }

    function challengeClosePosition(
        uint32 requestId,
        OraclePrice[] memory oraclePrices,
        bytes calldata oracleEcdsaSignature
    ) external nonReentrant {
        ClosePositionDispute storage dispute = _positionDisputes[requestId];

        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );
        require(
            block.timestamp < dispute.timestamp + 2 days,
            "Dispute window closed"
        );

        bytes memory encodedOraclePrices = "0x";
        for (uint i = 0; i < oraclePrices.length; i++) {
            encodedOraclePrices = abi.encodePacked(
                encodedOraclePrices,
                oraclePrices[i].positionId
            );
            encodedOraclePrices = abi.encodePacked(
                encodedOraclePrices,
                oraclePrices[i].price
            );
            encodedOraclePrices = abi.encodePacked(
                encodedOraclePrices,
                oraclePrices[i].timestamp
            );
        }
        // verify signature
        bytes32 _digest = keccak256(encodedOraclePrices);
        _verifySignature(_digest, oracleEcdsaSignature);

        // loop all position, remove liquidated positions
        for (uint i = 0; i < oraclePrices.length; i++) {
            for (uint j = 0; j < dispute.positions.length; j++) {
                if (
                    dispute.positions[j].createdTimestamp >
                    oraclePrices[i].timestamp
                ) {
                    continue;
                }
                if (
                    dispute.positions[j].positionId ==
                    oraclePrices[i].positionId
                ) {
                    if (dispute.positions[j].isLong) {
                        if (
                            dispute.positions[j].entryPrice >
                            oraclePrices[i].price
                        ) {
                            dispute.positions[j].quantity = 0;
                        }
                    } else {
                        if (
                            dispute.positions[j].entryPrice <
                            oraclePrices[i].price
                        ) {
                            dispute.positions[j].quantity = 0;
                        }
                    }
                }
            }
        }

        dispute.status = uint8(DisputeStatus.Challenged);
        dispute.challenger = msg.sender;
        emit DisputeChallenged(requestId, msg.sender);
    }

    function settleClosePositionDispute(
        uint32 requestId
    ) external nonReentrant {
        ClosePositionDispute storage dispute = _positionDisputes[requestId];

        require(
            dispute.status == uint8(DisputeStatus.Challenged),
            "Invalid dispute status"
        );
        require(
            block.timestamp > dispute.timestamp + 2 days,
            "Dispute window closed"
        );
        // loop all positions, fetch oracle price, and return token amount after closing position
        for (uint i = 0; i < dispute.positions.length; i++) {
            if (dispute.positions[i].quantity == 0) {
                continue;
            }
            uint256 price = IOracle(oracle).getPrice(
                dispute.positions[i].token
            );
            // close position
            int256 priceChange = int256(price) -
                int256(dispute.positions[i].entryPrice);
            uint256 pnl = 0;
            uint256 leverage = (dispute.positions[i].margin * ONE) /
                dispute.positions[i].quantity;
            if (priceChange > 0) {
                // win
                pnl =
                    (ONE +
                        ((leverage * uint256(priceChange) * ONE) /
                            dispute.positions[i].entryPrice) /
                        ONE) *
                    dispute.positions[i].quantity;
                dispute.positions[i].quantity += pnl / ONE;
            } else {
                // loss
                pnl =
                    (ONE -
                        ((leverage * uint256(priceChange) * ONE) /
                            dispute.positions[i].entryPrice) /
                        ONE) *
                    dispute.positions[i].quantity;
                dispute.positions[i].quantity -= pnl / ONE;
            }
            // transfer token
            IERC20(dispute.positions[0].token).transfer(
                dispute.user,
                dispute.positions[0].quantity
            );
            emit PositionClosed(dispute.positions[i].positionId, pnl / ONE);
        }

        dispute.status = uint8(DisputeStatus.Settled);
        emit DisputeSettled(requestId, msg.sender);
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

    function decodeClosePositionSchnorrData(
        bytes memory _data
    ) public pure returns (ClosePositionSchnorrData memory) {
        (
            uint32 signatureId,
            address addr,
            Position[] memory positions,
            string memory sigType,
            uint256 timestamp
        ) = abi.decode(_data, (uint32, address, Position[], string, uint256));
        return
            ClosePositionSchnorrData(
                signatureId,
                addr,
                positions,
                sigType,
                timestamp
            );
    }

    /**
     * @dev Decodes bytes into Schnorr data.
     *
     * @param _data (bytes) The encoded Schnorr data.
     * @return (SchnorrData) The decoded Schnorr data.
     */
    function decodeSchnorrDataWithdraw(
        bytes memory _data
    ) public pure returns (SchnorrDataWithdraw memory) {
        (address trader, address token, uint256 amount, uint64 timestamp) = abi
            .decode(_data, (address, address, uint256, uint64));
        return SchnorrDataWithdraw(trader, token, amount, timestamp);
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
    ) internal {
        if (_signatureUsed[_signature]) {
            revert InvalidUsedSignature();
        }

        bytes32 _ethSignedMessage = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _digest)
        );

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);

        address signer = ecrecover(_ethSignedMessage, v, r, s);

        if (signer != _trustedSigner) {
            revert InvalidSignature();
        }
        _signatureUsed[_signature] = true;
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
