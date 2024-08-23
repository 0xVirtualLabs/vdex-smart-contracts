// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {SupraOracleDecoder} from "./libs/SupraOracleDecoder.sol";
import {Crypto} from "./libs/Crypto.sol";
import {Dex} from "./libs/Dex.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IOracle, IPythOracle} from "./interfaces/IOracle.sol";
import {ILpProvider} from "./interfaces/ILpProvider.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract DexSupporter is Ownable {
    error InvalidSchnorrSignature();

    IVault public vault;
    address public pythOracle;
    address public lpProvider;
    uint256 constant ONE = 10 ^ 18;

    struct DisputeInfo {
        bool isOpenDispute;
        uint64 disputeTimestamp;
        address disputeUser;
        Crypto.Position[] positions;
        Crypto.Balance[] balances;
    }

    constructor(address _vault, address _pythOracle, address _lpProvider) {
        vault = IVault(_vault);
        pythOracle = _pythOracle;
        lpProvider = _lpProvider;
    }

    // function challengeLiquidatedPosition(
    //     uint32 requestId,
    //     Crypto.LiquidatedPosition[] memory positions
    // ) external {
    //     uint256 liquidatedLen = positions.length;

    //     (
    //         bool isOpenDispute,
    //         uint64 disputeTimestamp,
    //         address _disputeUser
    //     ) = vault.getDisputeStatus(requestId);
    //     require(isOpenDispute, "Invalid dispute status");
    //     require(
    //         block.timestamp < disputeTimestamp + 1800, // fake 30m
    //         "Dispute window closed"
    //     );

    //     Crypto.Position[] memory disputePositions = vault.getDisputePositions(
    //         requestId
    //     );
    //     Crypto.Balance[] memory disputeBalances = vault.getDisputeBalances(
    //         requestId
    //     );

    //     uint256[] memory liquidatedIndexes = new uint256[](
    //         disputePositions.length
    //     );
    //     uint256 liquidatedCount = 0;
    //     bool isCrossLiquidated = false;

    //     for (uint i = 0; i < disputePositions.length; i++) {
    //         // no leverage
    //         if (disputePositions[i].leverageFactor == 1) {
    //             continue;
    //         }

    //         // loop over liquidated positions
    //         for (uint j = 0; j < liquidatedLen; j++) {
    //             if (
    //                 keccak256(bytes(disputePositions[i].positionId)) !=
    //                 keccak256(bytes(positions[j].positionId))
    //             ) {
    //                 continue;
    //             }

    //             // get priceFeeds for position
    //             IPythOracle.PriceFeed[] memory feeds = IPythOracle(
    //                 pythOracle
    //             ).parsePriceFeedUpdates(
    //                     positions[i].updateData,
    //                     positions[i].priceIds,
    //                     positions[i].minPublishTime,
    //                     positions[i].maxPublishTime
    //                 );
    //             if (
    //                 Dex._checkLiquidatedPosition(
    //                     disputePositions[i],
    //                     feeds,
    //                     disputeBalances
    //                 )
    //             ) {
    //                 liquidatedIndexes[liquidatedCount] = i;
    //                 liquidatedCount++;
    //                 if (
    //                     keccak256(
    //                         abi.encodePacked(disputePositions[i].leverageType)
    //                     ) == keccak256(abi.encodePacked("cross"))
    //                 ) {
    //                     isCrossLiquidated = true;
    //                 }
    //             }
    //         }
    //     }

    //     // Update the dispute in the Vault contract
    //     vault.updateLiquidatedPositions(
    //         requestId,
    //         liquidatedIndexes,
    //         liquidatedCount,
    //         isCrossLiquidated
    //     );
    // }

    function challengeLiquidatedPosition(
        uint32 requestId,
        Crypto.LiquidatedPosition[] memory positions
    ) external {
        DisputeInfo memory disputeInfo = getDisputeInfo(requestId);
        require(disputeInfo.isOpenDispute, "Invalid dispute status");
        require(
            block.timestamp < disputeInfo.disputeTimestamp + 1800, // 30 minutes
            "Dispute window closed"
        );

        (
            uint256[] memory liquidatedIndexes,
            bool isCrossLiquidated
        ) = processLiquidations(
                disputeInfo.positions,
                positions,
                disputeInfo.balances
            );

        // Update the dispute in the Vault contract
        vault.updateLiquidatedPositions(
            requestId,
            liquidatedIndexes,
            liquidatedIndexes.length,
            isCrossLiquidated
        );
    }

    function getDisputeInfo(
        uint32 requestId
    ) private view returns (DisputeInfo memory) {
        (
            bool isOpenDispute,
            uint64 disputeTimestamp,
            address disputeUser
        ) = vault.getDisputeStatus(requestId);

        return
            DisputeInfo({
                isOpenDispute: isOpenDispute,
                disputeTimestamp: disputeTimestamp,
                disputeUser: disputeUser,
                positions: vault.getDisputePositions(requestId),
                balances: vault.getDisputeBalances(requestId)
            });
    }

    function processLiquidations(
        Crypto.Position[] memory disputePositions,
        Crypto.LiquidatedPosition[] memory positions,
        Crypto.Balance[] memory disputeBalances
    ) private returns (uint256[] memory, bool) {
        uint256[] memory liquidatedIndexes = new uint256[](
            disputePositions.length
        );
        uint256 liquidatedCount = 0;
        bool isCrossLiquidated = false;

        for (uint i = 0; i < disputePositions.length; i++) {
            if (disputePositions[i].leverageFactor == 1) continue;

            for (uint j = 0; j < positions.length; j++) {
                if (
                    keccak256(bytes(disputePositions[i].positionId)) !=
                    keccak256(bytes(positions[j].positionId))
                ) {
                    continue;
                }

                if (
                    checkLiquidation(
                        disputePositions[i],
                        positions[j],
                        disputeBalances
                    )
                ) {
                    liquidatedIndexes[liquidatedCount++] = i;
                    if (
                        keccak256(
                            abi.encodePacked(disputePositions[i].leverageType)
                        ) == keccak256(abi.encodePacked("cross"))
                    ) {
                        isCrossLiquidated = true;
                    }
                    break;
                }
            }
        }

        // Resize liquidatedIndexes array to actual count
        assembly {
            mstore(liquidatedIndexes, liquidatedCount)
        }

        return (liquidatedIndexes, isCrossLiquidated);
    }

    function checkLiquidation(
        Crypto.Position memory position,
        Crypto.LiquidatedPosition memory liquidatedPosition,
        Crypto.Balance[] memory disputeBalances
    ) private returns (bool) {
        IPythOracle.PriceFeed[] memory feeds = IPythOracle(pythOracle)
            .parsePriceFeedUpdates(
            liquidatedPosition.updateData,
            liquidatedPosition.priceIds,
            liquidatedPosition.minPublishTime,
            liquidatedPosition.maxPublishTime
        );

        return Dex._checkLiquidatedPosition(position, feeds, disputeBalances);
    }

    function settleDispute(uint32 requestId) external {
        (
            bool isOpenedDispute,
            uint64 disputeTimestamp,
            address disputeUser
        ) = vault.getDisputeStatus(requestId);
        require(isOpenedDispute, "Invalid dispute status");
        require(
            block.timestamp > disputeTimestamp + 1800, // fake 30m
            "Dispute window not closed"
        );

        Crypto.Position[] memory positions = vault.getDisputePositions(
            requestId
        );
        Crypto.Balance[] memory balances = vault.getDisputeBalances(requestId);

        uint256[] memory updatedBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            updatedBalances[i] = balances[i].balance;
        }

        for (uint i = 0; i < positions.length; i++) {
            if (positions[i].quantity == 0) {
                continue;
            }
            IPythOracle.PriceFeed memory oraclePrice = IPythOracle(pythOracle)
                .queryPriceFeed(positions[i].oracleId);

            int256 priceChange = (int256(oraclePrice.price.price) -
                int256(positions[i].entryPrice));
            if (!positions[i].isLong) {
                priceChange = -priceChange;
            }
            int256 multiplier = (1 +
                (priceChange * int256(positions[i].leverageFactor)) /
                int256(positions[i].entryPrice));
            if (multiplier < 0) {
                continue;
            }
            uint256 uMul = uint256(multiplier);

            for (uint256 j = 0; j < positions[i].collaterals.length; j++) {
                IPythOracle.PriceFeed
                    memory collateralOraclePrice = IPythOracle(pythOracle)
                        .queryPriceFeed(positions[i].collaterals[j].oracleId);

                if (collateralOraclePrice.price.price <= 0) {
                    revert("Negative or zero price");
                }

                uint256 transferAmount = (((positions[i]
                    .collaterals[j]
                    .quantity * uMul) / ONE) *
                    uint256(uint64(collateralOraclePrice.price.price)));

                // Update balance instead of transferring directly
                for (uint256 k = 0; k < balances.length; k++) {
                    if (balances[k].addr == positions[i].token) {
                        updatedBalances[k] += transferAmount;
                        break;
                    }
                }

                positions[i].collaterals[j].quantity = 0;
            }
        }

        uint256[] memory pnlValues = new uint256[](balances.length);
        bool[] memory isProfits = new bool[](balances.length);

        for (uint256 i = 0; i < balances.length; i++) {
            address token = balances[i].addr;
            uint256 amount = updatedBalances[i];
            uint256 depositedAmount = vault.depositedAmount(disputeUser, token);

            if (amount > depositedAmount) {
                pnlValues[i] = amount - depositedAmount;
                isProfits[i] = true;
            } else {
                pnlValues[i] = depositedAmount - amount;
                isProfits[i] = false;
            }
        }

        vault.settleDisputeResult(
            requestId,
            updatedBalances,
            pnlValues,
            isProfits
        );
    }

    function liquidatePartially(
        address user,
        Crypto.SchnorrSignature calldata _schnorr
    ) external {
        Crypto.SchnorrData memory data = Crypto.decodeSchnorrData(_schnorr);

        if (data.addr != user) {
            revert InvalidSchnorrSignature();
        }

        if (
            !Crypto._verifySchnorrSignature(
                _schnorr,
                IVault(vault).combinedPublicKey(data.addr)
            )
        ) {
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

        // Initialize arrays for updating the Vault
        address[] memory tokens = new address[](len);
        uint256[] memory losses = new uint256[](len);
        uint256 totalLossCount = 0;

        // Calculate realized loss
        for (uint i = 0; i < len; i++) {
            address assetId = data.balances[i].addr;
            uint256 depositedAmount = vault.depositedAmount(data.addr, assetId);
            uint256 loss = 0;
            if (depositedAmount > availableBalance[i].balance) {
                loss = depositedAmount - availableBalance[i].balance;
                tokens[totalLossCount] = assetId;
                losses[totalLossCount] = loss;
                totalLossCount++;
            }
        }

        // Update the Vault and LpProvider
        vault.updatePartialLiquidation(
            data.addr,
            tokens,
            losses,
            totalLossCount
        );
    }

    function setVault(address _vault) external onlyOwner {
        vault = IVault(_vault);
    }
}
