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
    /**
     * @dev Public variable to store the signature expiry time.
     */
    uint256 public signatureExpiryTime;

    /**
     * @dev Private constant to store the SECP256K1 curve N value.
     */
    uint256 private constant SECP256K1_CURVE_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /**
     * @dev Private variable to store the request ID counter.
     */
    uint32 private _requestIdCounter;

    /**
     * @dev Public mapping to store disputes based on their IDs.
     */
    mapping(uint32 => Dispute) public _disputes;

    // mapping(uint32 => ClosePositionDispute) private _positionDisputes;

    /**
     * @dev Private mapping to track used signatures.
     */
    mapping(bytes => bool) private _signatureUsed;

    /**
     * @dev Private mapping to track used Schnorr signatures.
     */
    mapping(bytes => bool) private _schnorrSignatureUsed;

    /**
     * @dev Private mapping to store the latest Schnorr signature ID.
     */
    mapping(uint32 => uint32) private _latestSchnorrSignatureId;

    /**
     * @dev Public mapping to store combined public keys.
     */
    mapping(address => address) public combinedPublicKey;

    /**
     * @dev Public mapping to check if a token is supported.
     */
    mapping(address => bool) public isTokenSupported;

    /**
     * @dev Constant representing the value 1e9.
     */
    uint256 constant ONE = 1e9;

    /**
     * @dev Public mapping to store deposited amounts for LP.
     */
    mapping(address => mapping(address => uint256)) public depositedAmount; // address => token => amount

    /**
     * @dev Public variable to store the LP provider address.
     */
    address public lpProvider;

    /**
     * @dev Public variable to store the DEX supporter address.
     */
    address public dexSupporter;

    /**
     * @dev Struct to represent token balances.
     */
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
    event PartialLiquidation(
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

    /**
     * @dev Initialize the Vault contract.
     * @param _owner The owner of the Vault contract.
     * @param _signatureExpiryTime The expiry time for signatures.
     * @param _lpProvider The address of the LP provider.
     * @param _dexSupporter The address of the DEX supporter.
     */
    function initialize(
        address _owner,
        uint256 _signatureExpiryTime,
        address _lpProvider,
        address _dexSupporter
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();
        signatureExpiryTime = _signatureExpiryTime;
        lpProvider = _lpProvider;
        dexSupporter = _dexSupporter;
    }

    /**
     * @dev Deposit tokens into the Vault.
     * @param token The address of the token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        require(isTokenSupported[token], "Token not supported");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        depositedAmount[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    /**
     * @dev Withdraw tokens from the Vault using a Schnorr signature.
     * @param _combinedPublicKey The combined public key of the user.
     * @param _schnorr The Schnorr signature.
     */
    function withdrawSchnorr(
        address _combinedPublicKey,
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        require(!_schnorrSignatureUsed[_schnorr.signature], "Signature already used");
        Crypto.SchnorrDataWithdraw memory schnorrData = Crypto
            .decodeSchnorrDataWithdraw(_schnorr, combinedPublicKey[msg.sender]);

        require(schnorrData.amount > 0, "Amount must byese greater than zero");
        require(isTokenSupported[schnorrData.token], "Token not supported");

        require(
            block.timestamp - schnorrData.timestamp < signatureExpiryTime,
            "Signature Expired"
        );

        if (schnorrData.trader != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        _schnorrSignatureUsed[_schnorr.signature] = true;
        combinedPublicKey[msg.sender] = _combinedPublicKey;

        require(
            IERC20(schnorrData.token).transfer(msg.sender, schnorrData.amount),
            "Transfer failed"
        );

        emit Withdrawn(msg.sender, schnorrData.token, schnorrData.amount);
    }

    /**
     * @dev Set the supported status of a token.
     * @param token The address of the token.
     * @param isSupported Whether the token is supported.
     */
    function setSupportedToken(
        address token,
        bool isSupported
    ) external onlyOwner {
        isTokenSupported[token] = isSupported;
        if (isSupported) {
            emit TokenAdded(token);
        } else {
            emit TokenRemoved(token);
        }
    }

    /**
     * @dev Set the Schnorr signature as used.
     * @param signature The Schnorr signature.
     */
    function setSchnorrSignatureUsed(bytes calldata signature) external {
        require(msg.sender == dexSupporter, "Unauthorized");
        _schnorrSignatureUsed[signature] = true;
    }

    /**
     * @dev Check if a Schnorr signature has been used.
     * @param signature The Schnorr signature.
     * @return Whether the signature has been used.
     */
    function isSchnorrSignatureUsed(bytes calldata signature)
        external
        view
        returns (bool)
    {
        return _schnorrSignatureUsed[signature];
    }

    /**
     * @dev Withdraw tokens and close positions trustlessly using a Schnorr signature.
     * @param _schnorr The Schnorr signature.
     */
    function withdrawAndClosePositionTrustlessly(
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        Crypto.SchnorrData memory schnorrData = Crypto.decodeSchnorrData(
            _schnorr
        );

        if (schnorrData.addr != msg.sender) {
            revert InvalidSchnorrSignature();
        }

        if (
            !Crypto._verifySchnorrSignature(
                _schnorr,
                combinedPublicKey[schnorrData.addr]
            )
        ) {
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

            newPosition.oracleId = schnorrData.positions[i].oracleId;
            newPosition.leverageFactor = schnorrData.positions[i].leverageFactor;
            newPosition.leverageType = schnorrData.positions[i].leverageType;

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

    /**
     * @dev Open a dispute.
     * @param requestId The request ID of the dispute.
     * @param user The user who opened the dispute.
     */
    function _openDispute(uint32 requestId, address user) private {
        Dispute storage dispute = _disputes[requestId];
        dispute.status = uint8(DisputeStatus.Opened);
        dispute.user = user;

        emit DisputeOpened(requestId, user);
    }

    /**
     * @dev Challenge a dispute.
     * @param requestId The request ID of the dispute.
     * @param _schnorr The Schnorr signature.
     */
    function challengeDispute(
        uint32 requestId,
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        require(!_schnorrSignatureUsed[_schnorr.signature], "Signature already used");
        Dispute storage dispute = _disputes[requestId];
        Crypto.SchnorrData memory schnorrData = Crypto.decodeSchnorrData(
            _schnorr
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
        _schnorrSignatureUsed[_schnorr.signature] = true;

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
                newPosition.oracleId = schnorrData.positions[i].oracleId;
                newPosition.leverageFactor = schnorrData.positions[i].leverageFactor;
                newPosition.leverageType = schnorrData.positions[i].leverageType;

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

    /**
     * @dev Get the status of a dispute.
     * @param requestId The request ID of the dispute.
     * @return isOpenDispute Whether the dispute is open.
     * @return timestamp The timestamp of the dispute.
     * @return user The user who opened the dispute.
     */
    function getDisputeStatus(
        uint32 requestId
    )
        external
        view
        returns (bool isOpenDispute, uint64 timestamp, address user)
    {
        Dispute storage dispute = _disputes[requestId];
        isOpenDispute = dispute.status == uint8(DisputeStatus.Opened);
        timestamp = dispute.timestamp;
        user = dispute.user;
    }

    /**
     * @dev Get the positions of a dispute.
     * @param requestId The request ID of the dispute.
     * @return The positions of the dispute.
     */
    function getDisputePositions(
        uint32 requestId
    ) external view returns (Crypto.Position[] memory) {
        return _disputes[requestId].positions;
    }

    /**
     * @dev Get the balances of a dispute.
     * @param requestId The request ID of the dispute.
     * @return The balances of the dispute.
     */
    function getDisputeBalances(
        uint32 requestId
    ) external view returns (Crypto.Balance[] memory) {
        return _disputes[requestId].balances;
    }

    /**
     * @dev Update the liquidated positions of a dispute.
     * @param requestId The request ID of the dispute.
     * @param liquidatedIndexes The indexes of the liquidated positions.
     * @param liquidatedCount The number of liquidated positions.
     * @param isCrossLiquidated Whether the liquidation is cross-liquidated.
     */
    function updateLiquidatedPositions(
        uint32 requestId,
        uint256[] memory liquidatedIndexes,
        uint256 liquidatedCount,
        bool isCrossLiquidated
    ) external {
        require(msg.sender == dexSupporter, "Require Dex Supporter");

        Dispute storage dispute = _disputes[requestId];
        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );

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

    // function liquidatePartially(
    //     address user,
    //     Crypto.SchnorrSignature calldata _schnorr
    // ) external onlyOwner {
    //     Crypto.SchnorrData memory data = Crypto.decodeSchnorrData(
    //         _schnorr,
    //         combinedPublicKey[user]
    //     );

    //     if (data.addr != user) {
    //         revert InvalidSchnorrSignature();
    //     }

    //     // Initialize availableBalance
    //     uint256 len = data.balances.length;
    //     Crypto.Balance[] memory availableBalance = new Crypto.Balance[](len);
    //     for (uint i = 0; i < len; i++) {
    //         availableBalance[i] = Crypto.Balance(
    //             data.balances[i].oracleId,
    //             data.balances[i].addr,
    //             0
    //         );
    //     }

    //     // Calculate available balance from SchnorrData balances
    //     for (uint i = 0; i < len; i++) {
    //         for (uint j = 0; j < availableBalance.length; j++) {
    //             if (data.balances[i].addr == availableBalance[j].addr) {
    //                 availableBalance[j].balance += data.balances[i].balance;
    //                 break;
    //             }
    //         }
    //     }

    //     // Add initial margins to available balance from SchnorrData positions
    //     uint256 posLen = data.positions.length;
    //     for (uint i = 0; i < posLen; i++) {
    //         for (uint j = 0; j < data.positions[i].collaterals.length; j++) {
    //             Crypto.Collateral memory im = data.positions[i].collaterals[j];
    //             for (uint k = 0; k < availableBalance.length; k++) {
    //                 if (im.token == availableBalance[k].addr) {
    //                     availableBalance[k].balance += im.quantity;
    //                     break;
    //                 }
    //             }
    //         }
    //     }

    //     // Initialize and calculate realized loss
    //     for (uint i = 0; i < len; i++) {
    //         address assetId = data.balances[i].addr;
    //         uint256 loss = 0;
    //         if (
    //             depositedAmount[data.addr][assetId] >
    //             availableBalance[i].balance
    //         ) {
    //             loss =
    //                 depositedAmount[data.addr][assetId] -
    //                 availableBalance[i].balance;
    //         }
    //         // Transfer realized loss to insurance pool
    //         if (loss > 0) {
    //             ILpProvider(lpProvider).increaseLpProvidedAmount(assetId, loss);
    //         }
    //     }
    // }

    /**
     * @dev Update the partial liquidation of a user.
     * @param user The address of the user.
     * @param tokens The addresses of the tokens.
     * @param losses The amounts of the losses.
     * @param totalLossCount The total number of losses.
     */
    function updatePartialLiquidation(
        address user,
        address[] memory tokens,
        uint256[] memory losses,
        uint256 totalLossCount
    ) external nonReentrant {
        require(msg.sender == dexSupporter, "Unauthorized");
        require(tokens.length == losses.length, "Array length mismatch");
        require(totalLossCount <= tokens.length, "Invalid total loss count");

        for (uint256 i = 0; i < totalLossCount; i++) {
            address token = tokens[i];
            uint256 loss = losses[i];

            // Update deposited amount
            require(
                depositedAmount[user][token] >= loss,
                "Insufficient deposited amount"
            );
            depositedAmount[user][token] -= loss;

            // Transfer realized loss to insurance pool
            IERC20(token).transfer(lpProvider, loss);
            ILpProvider(lpProvider).increaseLpProvidedAmount(token, loss);

            emit PartialLiquidation(user, token, loss);
        }
    }

    /**
     * @dev Settle the result of a dispute.
     * @param requestId The request ID of the dispute.
     * @param updatedBalances The updated balances of the user.
     * @param pnlValues The PNL values of the user.
     * @param isProfits Whether the PNL values are profits.
     */
    function settleDisputeResult(
        uint32 requestId,
        uint256[] memory updatedBalances,
        uint256[] memory pnlValues,
        bool[] memory isProfits
    ) external nonReentrant {
        require(msg.sender == dexSupporter, "Unauthorized");

        Dispute storage dispute = _disputes[requestId];
        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );

        for (uint256 i = 0; i < dispute.balances.length; i++) {
            address token = dispute.balances[i].addr;
            uint256 amount = updatedBalances[i];

            if (isProfits[i]) {
                ILpProvider(lpProvider).decreaseLpProvidedAmount(
                    dispute.user,
                    token,
                    pnlValues[i]
                );
            } else {
                IERC20(token).transfer(lpProvider, pnlValues[i]);
                ILpProvider(lpProvider).increaseLpProvidedAmount(
                    token,
                    pnlValues[i]
                );
            }

            depositedAmount[dispute.user][token] = 0;
            IERC20(token).transfer(dispute.user, amount);
            emit Withdrawn(dispute.user, token, amount);

            dispute.balances[i].balance = amount;
        }

        dispute.status = uint8(DisputeStatus.Settled);
        emit DisputeSettled(requestId, dispute.user);
    }

    /**
     * @dev Set the signature expiry time.
     * @param _expiryTime The new signature expiry time.
     */
    function setSignatureExpiryTime(uint256 _expiryTime) external onlyOwner {
        signatureExpiryTime = _expiryTime;
    }

    /**
     * @dev Set the DEX supporter address.
     * @param _dexSupporter The new DEX supporter address.
     */
    function setDexSupporter(address _dexSupporter) external onlyOwner {
        dexSupporter = _dexSupporter;
    }

    /**
     * @dev Set the LP provider address.
     * @param _lpProvider The new LP provider address.
     */
    function setLpProvider(address _lpProvider) external onlyOwner {
        lpProvider = _lpProvider;
    }

    /**
     * @dev Set the combined public key of a user.
     * @param _user The address of the user.
     * @param _combinedPublicKey The combined public key of the user.
     */
    function setCombinedPublicKey(
        address _user,
        address _combinedPublicKey
    ) external onlyOwner {
        combinedPublicKey[_user] = _combinedPublicKey;
    }
}
