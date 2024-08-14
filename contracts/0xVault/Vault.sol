// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ILpProvider} from "./interfaces/ILpProvider.sol";
import {Crypto} from "./libs/Crypto.sol";

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
    address private _trustedSigner;
    address[] private supportedTokens;
    address public oracle;
    uint256 constant ONE = 1e9;
    // for adding LP
    mapping(address => mapping(address => uint256)) public depositedAmount; // address => token => amount
    address public lpProvider;

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
        address trustedSigner,
        uint256 _signatureExpiryTime,
        address _lpProvider
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(_owner);
        __Pausable_init();
        _trustedSigner = trustedSigner;
        signatureExpiryTime = _signatureExpiryTime;
        lpProvider = _lpProvider;
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

    function withdraw(
        WithdrawParams memory withdrawParams,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
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

        Crypto._verifySignature(_digest, signature, _trustedSigner);

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
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        if (
            !Crypto._verifySchnorrSignature(
                _schnorr,
                combinedPublicKey[msg.sender]
            )
        ) {
            revert InvalidSchnorrSignature();
        }

        Crypto.SchnorrDataWithdraw memory schnorrData = Crypto
            .decodeSchnorrDataWithdraw(_schnorr.data);

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

    // function challengeClosePosition(
    //     uint32 requestId,
    //     OraclePrice[] memory oraclePrices,
    //     bytes calldata oracleEcdsaSignature
    // ) external nonReentrant whenNotPaused {
    //     ClosePositionDispute storage dispute = _positionDisputes[requestId];

    //     require(
    //         dispute.status == uint8(DisputeStatus.Opened),
    //         "Invalid dispute status"
    //     );
    //     require(
    //         block.timestamp < dispute.timestamp + 7 days,
    //         "Dispute window closed"
    //     );

    //     bytes memory encodedOraclePrices = "0x";
    //     for (uint i = 0; i < oraclePrices.length; i++) {
    //         encodedOraclePrices = abi.encodePacked(
    //             encodedOraclePrices,
    //             oraclePrices[i].positionId,
    //             oraclePrices[i].price,
    //             oraclePrices[i].timestamp
    //         );
    //     }
    //     // verify signature
    //     bytes32 _digest = keccak256(encodedOraclePrices);
    //     Crypto._verifySignature(_digest, oracleEcdsaSignature, _trustedSigner);

    //     // loop all position, remove liquidated positions
    //     for (uint i = 0; i < oraclePrices.length; i++) {
    //         for (uint j = 0; j < dispute.positions.length; j++) {
    //             if (
    //                 dispute.positions[j].createdTimestamp >
    //                 oraclePrices[i].timestamp
    //             ) {
    //                 continue;
    //             }
    //             if (
    //                 keccak256(bytes(dispute.positions[j].positionId)) ==
    //                 keccak256(bytes(oraclePrices[i].positionId))
    //             ) {
    //                 if (dispute.positions[j].isLong) {
    //                     if (
    //                         dispute.positions[j].entryPrice >
    //                         oraclePrices[i].price
    //                     ) {
    //                         dispute.positions[j].quantity = 0;
    //                     }
    //                 } else {
    //                     if (
    //                         dispute.positions[j].entryPrice <
    //                         oraclePrices[i].price
    //                     ) {
    //                         dispute.positions[j].quantity = 0;
    //                     }
    //                 }
    //             }
    //         }
    //     }

    //     dispute.status = uint8(DisputeStatus.Challenged);
    //     dispute.challenger = msg.sender;
    //     emit DisputeChallenged(requestId, msg.sender);
    // }

    // function settleClosePositionDispute(
    //     uint32 requestId
    // ) external nonReentrant {
    //     ClosePositionDispute storage dispute = _positionDisputes[requestId];

    //     require(
    //         dispute.status == uint8(DisputeStatus.Challenged),
    //         "Invalid dispute status"
    //     );
    //     require(
    //         block.timestamp > dispute.timestamp + 2 days,
    //         "Dispute window closed"
    //     );
    //     // loop all positions, fetch oracle price, and return token amount after closing position
    //     for (uint i = 0; i < dispute.positions.length; i++) {
    //         if (dispute.positions[i].quantity == 0) {
    //             continue;
    //         }
    //         uint256 price = IOracle(oracle).getPrice(
    //             dispute.positions[i].token
    //         );
    //         // close position
    //         int256 priceChange = int256(price) -
    //             int256(dispute.positions[i].entryPrice);
    //         uint256 pnl = 0;
    //         uint256 leverage = (dispute.positions[i].margin * ONE) /
    //             dispute.positions[i].quantity;
    //         if (priceChange > 0) {
    //             // win
    //             pnl =
    //                 (ONE +
    //                     ((leverage * uint256(priceChange) * ONE) /
    //                         dispute.positions[i].entryPrice) /
    //                     ONE) *
    //                 dispute.positions[i].quantity;
    //             dispute.positions[i].quantity += pnl / ONE;
    //         } else {
    //             // loss
    //             pnl =
    //                 (ONE -
    //                     ((leverage * uint256(priceChange) * ONE) /
    //                         dispute.positions[i].entryPrice) /
    //                     ONE) *
    //                 dispute.positions[i].quantity;
    //             dispute.positions[i].quantity -= pnl / ONE;
    //         }
    //         // transfer token
    //         IERC20(dispute.positions[0].token).transfer(
    //             dispute.user,
    //             dispute.positions[0].quantity
    //         );
    //         emit PositionClosed(dispute.positions[i].positionId, pnl / ONE);
    //     }

    //     dispute.status = uint8(DisputeStatus.Settled);
    //     emit DisputeSettled(requestId, msg.sender);
    // }

    function withdrawAndClosePositionTrustlessly(
        Crypto.SchnorrSignature calldata _schnorr
    ) external nonReentrant whenNotPaused {
        if (
            !Crypto._verifySchnorrSignature(
                _schnorr,
                combinedPublicKey[msg.sender]
            )
        ) {
            revert InvalidSchnorrSignature();
        }

        Crypto.SchnorrData memory schnorrData = Crypto.decodeSchnorrData(
            _schnorr.data
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

    function _openDispute(uint32 requestId, address user) internal {
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
            _schnorr.data
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

    function settleDispute(
        uint32 requestId
    ) external nonReentrant whenNotPaused {
        Dispute storage dispute = _disputes[requestId];
        // require(
        //     dispute.status == uint8(DisputeStatus.Challenged),
        //     "Invalid dispute status"
        // );
        require(
            block.timestamp > dispute.timestamp + 1800, // fake 30m
            "Dispute window closed"
        );

        // ClosePositionDispute storage posDispute = _positionDisputes[requestId];

        // TODO: wait oracle loop all positions, fetch oracle price, and return token amount after closing position
        // for (uint i = 0; i < posDispute.positions.length; i++) {
        //     if (posDispute.positions[i].quantity == 0) {
        //         continue;
        //     }
        //     uint256 price = IOracle(oracle).getPrice(
        //         posDispute.positions[i].token
        //     );
        //     // close position
        //     int256 priceChange = int256(price) -
        //         int256(posDispute.positions[i].entryPrice);
        //     uint256 pnl = 0;
        //     uint256 leverage = (posDispute.positions[i].margin * ONE) /
        //         posDispute.positions[i].quantity;
        //     if (priceChange > 0) {
        //         // win
        //         pnl =
        //             (ONE +
        //                 ((leverage * uint256(priceChange) * ONE) /
        //                     posDispute.positions[i].entryPrice) /
        //                 ONE) *
        //             posDispute.positions[i].quantity;
        //         posDispute.positions[i].quantity += pnl / ONE;
        //     } else {
        //         // loss
        //         pnl =
        //             (ONE -
        //                 ((leverage * uint256(priceChange) * ONE) /
        //                     posDispute.positions[i].entryPrice) /
        //                 ONE) *
        //             posDispute.positions[i].quantity;
        //         posDispute.positions[i].quantity -= pnl / ONE;
        //     }

        //     // transfer token
        //     IERC20(posDispute.positions[i].token).transfer(
        //         posDispute.user,
        //         posDispute.positions[i].quantity
        //     );
        //     emit PositionClosed(posDispute.positions[i].positionId, pnl / ONE);
        // }

        uint256 len = dispute.balances.length;

        for (uint256 i = 0; i < len; i++) {
            address token = dispute.balances[i].addr;
            uint256 amount = dispute.balances[i].balance;
            if (
                amount > depositedAmount[dispute.user][dispute.balances[0].addr]
            ) {
                uint256 pnl = amount -
                    depositedAmount[dispute.user][dispute.balances[0].addr];
                ILpProvider(lpProvider).decreaseLpProvidedAmount(token, pnl);
            } else {
                uint256 pnl = depositedAmount[dispute.user][
                    dispute.balances[0].addr
                ] - amount;
                IERC20(token).transfer(lpProvider, pnl);
                ILpProvider(lpProvider).increaseLpProvidedAmount(token, pnl);
            }

            depositedAmount[dispute.user][dispute.balances[0].addr] = 0;
            IERC20(token).transfer(dispute.user, amount);
            emit Withdrawn(msg.sender, token, amount);
        }

        dispute.status = uint8(DisputeStatus.Settled);
        emit DisputeSettled(requestId, msg.sender);
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

    function setLpProvider(address _lpProvider) external onlyOwner {
        if (_lpProvider == address(0)) {
            revert InvalidAddress();
        }
        lpProvider = _lpProvider;
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
