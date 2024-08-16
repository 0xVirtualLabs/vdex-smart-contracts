// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ISupraVerifier} from "./interfaces/ISupraVerifier.sol";
import {ILpProvider} from "./interfaces/ILpProvider.sol";
import {Crypto} from "./libs/Crypto.sol";
import {Dex} from "./libs/Dex.sol";
import {SupraOracleDecoder} from "./libs/SupraOracleDecoder.sol";

/**
 * @custom:oz-upgrades-from Vault
 */
contract Vault is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    uint256 public signatureExpiryTime;
    uint256 private constant SECP256K1_CURVE_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    uint32 private _requestIdCounter;

    mapping(uint32 => Dispute) public _disputes;
    // mapping(uint32 => ClosePositionDispute) private _positionDisputes;
    mapping(bytes => bool) private _signatureUsed;
    mapping(bytes => bool) private _schnorrSignatureUsed;
    mapping(uint32 => uint32) private _latestSchnorrSignatureId;

    mapping(address => address) public combinedPublicKey;
    address[] private supportedTokens;
    uint256 constant ONE = 1e9;
    address public supraStorageOracle;
    address public supraVerifier;
    // for adding LP
    mapping(address => mapping(address => uint256)) public depositedAmount; // address => token => amount
    address public lpProvider;
    address public dexSupporter;

    struct TokenBalance {
        address token;
        uint256 balance;
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
    event WithdrawalRequested(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint32 requestId
    );
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
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

    error InvalidSignature();
    error InvalidUsedSignature();
    error InvalidSchnorrSignature();
    error InvalidSP();
    error ECRecoverFailed();
    error InvalidAddress();
    error DisputeChallengeFailed();
    error SettleDisputeFailed();
    error DataNotVerified();

    struct WithdrawParams {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    // for liquidation case
    struct OraclePrice {
        string positionId;
        address token;
        uint256 price;
        uint64 timestamp;
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
        Crypto.Balance[] balances;
        Crypto.Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

    struct ClosePositionDispute {
        address user;
        address challenger;
        uint64 timestamp;
        Crypto.Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

    event DisputeOpened(uint32 requestId, address indexed user);
    event DisputeChallenged(uint32 requestId, address indexed user);
    event PositionDisputeChallenged(uint32 requestId, address indexed user);
    event DisputeSettled(uint32 requestId, address indexed user);

    function initialize(
        address _owner,
        uint256 _signatureExpiryTime,
        address _lpProvider,
        address _dexSupporter,
        address _supraStorageOracle,
        address _supraVerifier
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(_owner);
        __Pausable_init();
        signatureExpiryTime = _signatureExpiryTime;
        lpProvider = _lpProvider;
        supraStorageOracle = _supraStorageOracle;
        supraVerifier = _supraVerifier;
        dexSupporter = _dexSupporter;
    }

    function deposit(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        require(isTokenSupported(token), "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        depositedAmount[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function withdrawSchnorr(
        address _combinedPublicKey,
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        Crypto.SchnorrDataWithdraw memory schnorrData = Crypto
            .decodeSchnorrDataWithdraw(_schnorr, combinedPublicKey[msg.sender]);

        require(schnorrData.amount > 0, "Amount must byese greater than zero");
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

    function setOracle(address _supraStorageOracle) external onlyOwner {
        supraStorageOracle = _supraStorageOracle;
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

    function withdrawAndClosePositionTrustlessly(
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        Crypto.SchnorrData memory schnorrData = Crypto.decodeSchnorrData(
            _schnorr,
            combinedPublicKey[msg.sender]
        );

        if (schnorrData.addr != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        if (_schnorrSignatureUsed[_schnorr.signature]) {
            revert InvalidSchnorrSignature();
        }

        _requestIdCounter = _requestIdCounter + 1;
        uint32 requestId = _requestIdCounter;
        _disputes[requestId].timestamp = uint64(block.timestamp);
        uint256 len = schnorrData.balances.length;
        uint256 posLen = schnorrData.positions.length;
        for (uint256 i = 0; i < posLen; i++) {
            Crypto.Position storage newPosition = _disputes[requestId]
                .positions
                .push();

            newPosition.positionId = schnorrData.positions[i].positionId;
            newPosition.token = schnorrData.positions[i].token;
            newPosition.quantity = schnorrData.positions[i].quantity;
            newPosition.isLong = schnorrData.positions[i].isLong;
            newPosition.entryPrice = schnorrData.positions[i].entryPrice;
            newPosition.createdTimestamp = schnorrData
                .positions[i]
                .createdTimestamp;

            uint256 colLen = schnorrData.positions[i].collaterals.length;
            for (uint256 j = 0; j < colLen; j++) {
                newPosition.collaterals.push(
                    Crypto.Collateral({
                        token: schnorrData.positions[i].collaterals[j].token,
                        oracleId: schnorrData
                            .positions[i]
                            .collaterals[j]
                            .oracleId,
                        quantity: schnorrData
                            .positions[i]
                            .collaterals[j]
                            .quantity,
                        entryPrice: schnorrData
                            .positions[i]
                            .collaterals[j]
                            .entryPrice
                    })
                );
            }
        }
        for (uint256 i = 0; i < len; i++) {
            _disputes[requestId].balances.push(schnorrData.balances[i]);
        }

        uint32 signatureId = schnorrData.signatureId;
        _latestSchnorrSignatureId[requestId] = signatureId;
        _schnorrSignatureUsed[_schnorr.signature] = true;

        _openDispute(requestId, msg.sender);
    }

    function _openDispute(uint32 requestId, address user) private {
        Dispute storage dispute = _disputes[requestId];
        dispute.status = uint8(DisputeStatus.Opened);
        dispute.user = user;

        emit DisputeOpened(requestId, user);
    }

    function challengeDispute(
        uint32 requestId,
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        Dispute storage dispute = _disputes[requestId];
        Crypto.SchnorrData memory schnorrData = Crypto.decodeSchnorrData(
            _schnorr,
            combinedPublicKey[msg.sender]
        );
        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );
        require(
            block.timestamp < dispute.timestamp + 1800, // fake 30m
            "Dispute window closed"
        );

        if (
            !Crypto._verifySchnorrSignature(
                _schnorr,
                combinedPublicKey[schnorrData.addr]
            )
        ) {
            revert InvalidSchnorrSignature();
        }

        uint32 signatureId = schnorrData.signatureId;

        if (_latestSchnorrSignatureId[requestId] < schnorrData.signatureId) {
            _latestSchnorrSignatureId[requestId] = signatureId;

            dispute.challenger = msg.sender;
            delete dispute.balances;
            delete dispute.positions;
            uint256 len = schnorrData.balances.length;
            uint256 posLen = schnorrData.positions.length;
            for (uint256 i = 0; i < len; i++) {
                dispute.balances.push(schnorrData.balances[i]);
            }
            for (uint256 i = 0; i < posLen; i++) {
                Crypto.Position storage newPosition = _disputes[requestId]
                    .positions
                    .push();

                newPosition.positionId = schnorrData.positions[i].positionId;
                newPosition.token = schnorrData.positions[i].token;
                newPosition.quantity = schnorrData.positions[i].quantity;
                newPosition.isLong = schnorrData.positions[i].isLong;
                newPosition.entryPrice = schnorrData.positions[i].entryPrice;
                newPosition.createdTimestamp = schnorrData
                    .positions[i]
                    .createdTimestamp;

                uint256 colLen = schnorrData.positions[i].collaterals.length;
                for (uint256 j = 0; j < colLen; j++) {
                    newPosition.collaterals.push(
                        Crypto.Collateral({
                            oracleId: schnorrData
                                .positions[i]
                                .collaterals[j]
                                .oracleId,
                            token: schnorrData
                                .positions[i]
                                .collaterals[j]
                                .token,
                            quantity: schnorrData
                                .positions[i]
                                .collaterals[j]
                                .quantity,
                            entryPrice: schnorrData
                                .positions[i]
                                .collaterals[j]
                                .entryPrice
                        })
                    );
                }
            }

            emit DisputeChallenged(requestId, schnorrData.addr);
        } else {
            revert DisputeChallengeFailed();
        }
    }

    function getDisputeStatus(uint32 requestId) external view returns (bool isOpenDispute, uint64 timestamp, address user) {
        Dispute storage dispute = _disputes[requestId];
        isOpenDispute = dispute.status == uint8(DisputeStatus.Opened);
        timestamp = dispute.timestamp;
        user = dispute.user;
    }

    function getDisputePositions(uint32 requestId) external view returns (Crypto.Position[] memory) {
        return _disputes[requestId].positions;
    }

    function getDisputeBalances(uint32 requestId) external view returns (Crypto.Balance[] memory) {
        return _disputes[requestId].balances;
    }

    function updateLiquidatedPositions(
        uint32 requestId,
        uint256[] memory liquidatedIndexes,
        uint256 liquidatedCount,
        bool isCrossLiquidated
    ) external {
        require(msg.sender == dexSupporter, "Require Dex Supporter");
        
        Dispute storage dispute = _disputes[requestId];
        require(dispute.status == uint8(DisputeStatus.Opened), "Invalid dispute status");

        // Update liquidated positions
        for (uint256 i = 0; i < liquidatedCount; i++) {
            uint256 index = liquidatedIndexes[i];
            dispute.positions[index].quantity = 0;
        }

        // If cross position is liquidated, update user balance
        if (isCrossLiquidated) {
            for (uint256 i = 0; i < dispute.balances.length; i++) {
                dispute.balances[i].balance = 0;
            }
        }
    }


    function liquidatePartially(
        Crypto.SchnorrSignature calldata _schnorr
    ) external onlyOwner {
        Crypto.SchnorrData memory data = Crypto.decodeSchnorrData(
            _schnorr,
            combinedPublicKey[msg.sender]
        );

        if (data.addr != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        // Initialize availableBalance
        uint256 len = data.balances.length;
        Crypto.Balance[] memory availableBalance = new Crypto.Balance[](len);
        for (uint i = 0; i < len; i++) {
            availableBalance[i] = Crypto.Balance(
                data.balances[i].oracleId,
                data.balances[i].addr,
                0
            );
        }

        // Calculate available balance from SchnorrData balances
        for (uint i = 0; i < len; i++) {
            for (uint j = 0; j < availableBalance.length; j++) {
                if (data.balances[i].addr == availableBalance[j].addr) {
                    availableBalance[j].balance += data.balances[i].balance;
                    break;
                }
            }
        }

        // Add initial margins to available balance from SchnorrData positions
        uint256 posLen = data.positions.length;
        for (uint i = 0; i < posLen; i++) {
            for (uint j = 0; j < data.positions[i].collaterals.length; j++) {
                Crypto.Collateral memory im = data.positions[i].collaterals[j];
                for (uint k = 0; k < availableBalance.length; k++) {
                    if (im.token == availableBalance[k].addr) {
                        availableBalance[k].balance += im.quantity;
                        break;
                    }
                }
            }
        }

        // Initialize and calculate realized loss
        for (uint i = 0; i < len; i++) {
            address assetId = data.balances[i].addr;
            uint256 loss = 0;
            if (
                depositedAmount[data.addr][assetId] >
                availableBalance[i].balance
            ) {
                loss =
                    depositedAmount[data.addr][assetId] -
                    availableBalance[i].balance;
            }
            // Transfer realized loss to insurance pool
            if (loss > 0) {
                ILpProvider(lpProvider).increaseLpProvidedAmount(assetId, loss);
            }
        }
    }

    function settleDisputeResult(
        uint32 requestId,
        uint256[] memory updatedBalances,
        uint256[] memory pnlValues,
        bool[] memory isProfits
    ) external nonReentrant {
        require(msg.sender == dexSupporter, "Unauthorized");
        
        Dispute storage dispute = _disputes[requestId];
        require(dispute.status == uint8(DisputeStatus.Opened), "Invalid dispute status");

        for (uint256 i = 0; i < dispute.balances.length; i++) {
            address token = dispute.balances[i].addr;
            uint256 amount = updatedBalances[i];

            if (isProfits[i]) {
                ILpProvider(lpProvider).decreaseLpProvidedAmount(token, pnlValues[i]);
            } else {
                IERC20(token).transfer(lpProvider, pnlValues[i]);
                ILpProvider(lpProvider).increaseLpProvidedAmount(token, pnlValues[i]);
            }

            depositedAmount[dispute.user][token] = 0;
            IERC20(token).transfer(dispute.user, amount);
            emit Withdrawn(dispute.user, token, amount);

            dispute.balances[i].balance = amount;
        }

        dispute.status = uint8(DisputeStatus.Settled);
        emit DisputeSettled(requestId, dispute.user);
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
}
