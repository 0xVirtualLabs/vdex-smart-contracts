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
    address private _trustedSigner;
    address[] private supportedTokens;
    uint256 constant ONE = 1e9;
    address public supraStorageOracle;
    address public supraVerifier;
    // for adding LP
    mapping(address => mapping(address => uint256)) public depositedAmount; // address => token => amount
    address public lpProvider;

    uint256 public constant MAINTENANCE_MARGIN_PERCENT = 50;
    uint256 public constant BACKSTOP_LIQUIDATION_PERCENT = 6667;

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
        address trustedSigner,
        uint256 _signatureExpiryTime,
        address _lpProvider,
        address _supraStorageOracle,
        address _supraVerifier
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(_owner);
        __Pausable_init();
        _trustedSigner = trustedSigner;
        signatureExpiryTime = _signatureExpiryTime;
        lpProvider = _lpProvider;
        supraStorageOracle = _supraStorageOracle;
        supraVerifier = _supraVerifier;
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

    function challengeLiquidatedPosition(
        uint32 requestId,
        bytes[] calldata bytesProofs, // different timestamp, different bytesProof
        string[] memory positionIds, // positionIds and priceIndexs for mapping liquidated position with oracle price at the liquidated timestamp
        string[] memory priceIndexs
    ) external nonReentrant whenNotPaused {
        uint256 liquidatedLen = positionIds.length;
        require(liquidatedLen == priceIndexs.length, "Invalid input");

        Dispute storage dispute = _disputes[requestId];
        require(
            dispute.status == uint8(DisputeStatus.Opened),
            "Invalid dispute status"
        );
        require(
            block.timestamp < dispute.timestamp + 1800, // fake 30m
            "Dispute window closed"
        );

        uint256 proofLen = bytesProofs.length;
        uint256 paircnt = 0;
        for (uint256 i = 0; i < proofLen; i++) {
            SupraOracleDecoder.OracleProofV2 memory oracle = SupraOracleDecoder
                .decodeOracleProof(bytesProofs[i]);
            // verify oracle proof
            uint256 orcLen = oracle.data.length;
            for (uint256 j = 0; j < orcLen; j++) {
                requireRootVerified(
                    oracle.data[j].root,
                    oracle.data[j].sigs,
                    oracle.data[j].committee_id
                );
                paircnt += oracle.data[j].committee_data.committee_feeds.length;
            }
        }

        SupraOracleDecoder.CommitteeFeed[]
            memory allFeeds = new SupraOracleDecoder.CommitteeFeed[](paircnt);
        uint256 feedIndex = 0;
        for (uint256 i = 0; i < proofLen; i++) {
            SupraOracleDecoder.OracleProofV2 memory oracle = SupraOracleDecoder
                .decodeOracleProof(bytesProofs[i]);
            uint256 orcLen = oracle.data.length;
            for (uint256 j = 0; j < orcLen; j++) {
                SupraOracleDecoder.CommitteeFeed[] memory feeds = oracle
                    .data[j]
                    .committee_data
                    .committee_feeds;
                for (uint256 k = 0; k < feeds.length; k++) {
                    allFeeds[feedIndex] = feeds[k];
                    feedIndex++;
                }
            }
        }

        // we have feeds, we have positionIds, we have priceIndexs (positionIds and priceIndexs are mapping)
        // => loop all position, get feeds price from priceIndexs, remove liquidated positions
        for (uint i = 0; i < dispute.positions.length; i++) {
            // no leverage
            if (dispute.positions[i].leverageFactor == 1) {
                continue;
            }
            
            for (uint j = 0; j < liquidatedLen; j++) {
                if (
                    keccak256(bytes(dispute.positions[i].positionId)) !=
                    keccak256(bytes(positionIds[j]))
                ) {
                    continue;
                }
                if (
                    _checkLiquidatedPosition(dispute.positions[i], allFeeds, dispute.balances)
                ) {
                    dispute.positions[i].quantity = 0;
                    if (keccak256(abi.encodePacked(position.leverageType)) == keccak256(abi.encodePacked("cross"))) {
                        // update user balance if cross position is liquidated
                        for (uint256 k = 0; k < dispute.balances.length; k++) {
                            dispute.balances[k].balance = 0;
                        }
                    }
                }
                // // TODO: change the logic to remove liquidated position here
                // uint256 priceIndex = uint256(keccak256(bytes(priceIndexs[j])));
                // uint256 price = allFeeds[priceIndex].price;
                // if (dispute.positions[i].isLong) {
                //     if (
                //         _isPositionLiquidated(dispute.positions[i], price, true)
                //     ) {
                //         dispute.positions[i].quantity = 0;
                //     }
                // } else {
                //     if (
                //         _isPositionLiquidated(
                //             dispute.positions[i],
                //             price,
                //             false
                //         )
                //     ) {
                //         dispute.positions[i].quantity = 0;
                //     }
                // }
            }
        }
    }

    function _getPriceByPairId(SupraOracleDecoder.CommitteeFeed[] memory allFeeds, uint32 pair)
        internal
        pure
        returns (uint128)
    {
        for (uint256 i = 0; i < allFeeds.length; i++) {
            if (allFeeds[i].pair == pair) {
                return allFeeds[i].price;
            }
        }
        
        revert("given pair not found");
    }

    function _getPositionLoss(
        Crypto.Position memory position,
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds
    ) internal pure returns (uint256) {
        uint256 totalPositionValue = position.quantity * _getPriceByPairId(allFeeds, position.oracleId);
        uint256 positionInitialValue = position.quantity * position.entryPrice;

        if (position.isLong) {
            if (totalPositionValue > positionInitialValue) {
                return 0;
            }
            return positionInitialValue - totalPositionValue;
        } else {
            if (totalPositionValue < positionInitialValue) {
                return 0;
            }
            return totalPositionValue - positionInitialValue;
        }
    }

    function _checkLiquidatedPosition(
        Crypto.Position memory position,
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds,
        Crypto.Balance[] memory balances
    ) internal pure returns (bool) {
        uint256 totalPositionLoss = 0;
        uint256 totalPositionInitialCollateral = 0;

        // position loss
        totalPositionLoss += _getPositionLoss(position, allFeeds);

        uint256 collateralCurrentValue = 0;
        for (uint256 j = 0; j < position.collaterals.length; j++) {
            collateralCurrentValue += position.collaterals[j].quantity * _getPriceByPairId(allFeeds, position.collaterals[j].oracleId);
            totalPositionInitialCollateral += position.collaterals[j].entryPrice * position.collaterals[j].quantity;
        }

        totalPositionLoss += totalPositionInitialCollateral - collateralCurrentValue;

        // cross position
        if (keccak256(abi.encodePacked(position.leverageType)) == keccak256(abi.encodePacked("cross"))) {
            for (uint256 i = 0; i < balances.length; i++) {
                totalPositionInitialCollateral += balances[i].balance * _getPriceByPairId(allFeeds, balances[i].oracleId);
            }
        }

        uint256 liquidationLevel = totalPositionInitialCollateral * MAINTENANCE_MARGIN_PERCENT / 100;
        uint256 backstopLiquidationLevel = totalPositionInitialCollateral * BACKSTOP_LIQUIDATION_PERCENT / 10000;

        // check backstop liquidation
        if (totalPositionLoss > backstopLiquidationLevel) {
            return true;
        }

        // check liquidation
        if (totalPositionLoss > liquidationLevel) {
            return true;
        }

        return false;
    }

    function _isPositionLiquidated(
        Crypto.Position memory position,
        uint256 price,
        bool isLong
    ) internal pure returns (bool) {
        // TODO: update this code
        return true;
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

    function setSignatureExpiryTime(uint256 _expiryTime) external onlyOwner {
        signatureExpiryTime = _expiryTime;
    }

    function setCombinedPublicKey(
        address _user,
        address _combinedPublicKey
    ) external onlyOwner {
        combinedPublicKey[_user] = _combinedPublicKey;
    }

    function requireRootVerified(
        bytes32 root,
        uint256[2] memory sigs,
        uint256 committee_id
    ) private view {
        (bool status, ) = address(supraVerifier).staticcall(
            abi.encodeCall(
                ISupraVerifier.requireHashVerified_V2,
                (root, sigs, committee_id)
            )
        );
        if (!status) {
            revert DataNotVerified();
        }
    }
}
