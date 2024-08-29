// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {Crypto} from "./Crypto.sol";
import {IRedstoneOracle} from "../interfaces/IOracle.sol";

library Dex {
    uint256 public constant MAINTENANCE_MARGIN_PERCENT = 50;
    uint256 public constant BACKSTOP_LIQUIDATION_PERCENT = 6667;

    function _getPriceFeedByPairId(
        IRedstoneOracle.PriceFeed[] memory allFeeds,
        bytes32 pair
    ) public pure returns (IRedstoneOracle.Price memory feed) {
        for (uint256 i = 0; i < allFeeds.length; i++) {
            if (allFeeds[i].id == pair) {
                return IRedstoneOracle.Price(allFeeds[i].price);
            }
        }

        revert("Given pair not found");
    }

    function _getPositionLoss(
        Crypto.Position memory position,
        IRedstoneOracle.PriceFeed[] memory allFeeds
    ) public pure returns (uint256) {
        uint256 totalPositionValue = position.quantity *
            _getPriceFeedByPairId(allFeeds, position.oracleId).price;
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
        IRedstoneOracle.PriceFeed[] memory allFeeds,
        Crypto.Balance[] memory balances
    ) public pure returns (bool) {
        uint256 totalPositionLoss = 0;
        uint256 totalPositionInitialCollateral = 0;

        // position loss
        totalPositionLoss += _getPositionLoss(position, allFeeds);

        uint256 collateralCurrentValue = 0;
        for (uint256 j = 0; j < position.collaterals.length; j++) {
            IRedstoneOracle.Price memory feed = _getPriceFeedByPairId(
                allFeeds,
                position.collaterals[j].oracleId
            );
            uint256 u256Price = feed.price;
            uint256 beAddedCollateralCurrentValue = position
                .collaterals[j]
                .quantity * u256Price;
            beAddedCollateralCurrentValue /= 10 ** 8;
            collateralCurrentValue +=
                position.collaterals[j].quantity *
                u256Price;
            totalPositionInitialCollateral +=
                position.collaterals[j].entryPrice *
                position.collaterals[j].quantity;
        }

        totalPositionLoss +=
            totalPositionInitialCollateral -
            collateralCurrentValue;

        // cross position
        if (
            keccak256(abi.encodePacked(position.leverageType)) ==
            keccak256(abi.encodePacked("cross"))
        ) {
            for (uint256 i = 0; i < balances.length; i++) {
                IRedstoneOracle.Price memory feed = _getPriceFeedByPairId(
                    allFeeds,
                    balances[i].oracleId
                );
                uint256 u256Price = feed.price;
                uint256 beAddedTotalPositionInitialCollateral = balances[i]
                    .balance * u256Price;
                beAddedTotalPositionInitialCollateral /= 10 ** 8;
                totalPositionInitialCollateral += beAddedTotalPositionInitialCollateral;
            }
        }

        uint256 liquidationLevel = (totalPositionInitialCollateral *
            MAINTENANCE_MARGIN_PERCENT) / 100;
        uint256 backstopLiquidationLevel = (totalPositionInitialCollateral *
            BACKSTOP_LIQUIDATION_PERCENT) / 10000;

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
}
