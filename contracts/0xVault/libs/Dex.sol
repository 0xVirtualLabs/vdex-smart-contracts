// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {Crypto} from "./Crypto.sol";
import {IPythOracle} from "../interfaces/IOracle.sol";

library Dex {
    uint256 public constant MAINTENANCE_MARGIN_PERCENT = 50;
    uint256 public constant BACKSTOP_LIQUIDATION_PERCENT = 6667;

    function _getPriceByPairId(
        IPythOracle.PriceFeed[] memory allFeeds,
        bytes32 pair
    ) public pure returns (uint128) {
        for (uint256 i = 0; i < allFeeds.length; i++) {
            if (allFeeds[i].id == pair) {
                int64 price = allFeeds[i].price.price;
                // int32 expo = allFeeds[i].price.expo;

                // Convert price to positive if it's negative
                if (price < 0) {
                    revert("Negative price");
                }

                // Adjust the price based on the exponent
                // return uint128(uint64(price) * 10 ** uint32(expo));
                return uint128(uint64(price));
            }
        }

        revert("Given pair not found");
    }

    function _getPriceFeedByPairId(
        IPythOracle.PriceFeed[] memory allFeeds,
        bytes32 pair
    ) public pure returns (IPythOracle.Price memory feed) {
        for (uint256 i = 0; i < allFeeds.length; i++) {
            if (allFeeds[i].id == pair) {
                if (allFeeds[i].price.price < 0) {
                    revert("Negative price");
                }
                return allFeeds[i].price;
            }
        }

        revert("Given pair not found");
    }

    function _getPositionLoss(
        Crypto.Position memory position,
        IPythOracle.PriceFeed[] memory allFeeds
    ) public pure returns (uint256) {
        uint256 totalPositionValue = position.quantity *
            _getPriceByPairId(allFeeds, position.oracleId);
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
        IPythOracle.PriceFeed[] memory allFeeds,
        Crypto.Balance[] memory balances
    ) public pure returns (bool) {
        uint256 totalPositionLoss = 0;
        uint256 totalPositionInitialCollateral = 0;

        // position loss
        totalPositionLoss += _getPositionLoss(position, allFeeds);

        uint256 collateralCurrentValue = 0;
        for (uint256 j = 0; j < position.collaterals.length; j++) {
            IPythOracle.Price memory feed = _getPriceFeedByPairId(
                allFeeds,
                position.collaterals[j].oracleId
            );
            uint256 u256Price = uint256(uint64(feed.price));
            uint256 beAddedCollateralCurrentValue = position
                .collaterals[j]
                .quantity * u256Price;
            if (feed.expo > 0) {
                beAddedCollateralCurrentValue *= 10 ** uint32(feed.expo);
            } else {
                beAddedCollateralCurrentValue /= 10 ** uint32(-feed.expo);
            }
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
                IPythOracle.Price memory feed = _getPriceFeedByPairId(
                    allFeeds,
                    balances[i].oracleId
                );
                uint256 u256Price = uint256(uint64(feed.price));
                uint256 beAddedTotalPositionInitialCollateral =
                    balances[i].balance *
                    u256Price;
                if (feed.expo > 0) {
                    beAddedTotalPositionInitialCollateral *= 10 ** uint32(feed.expo);
                } else {
                    beAddedTotalPositionInitialCollateral /= 10 ** uint32(-feed.expo);
                }
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
