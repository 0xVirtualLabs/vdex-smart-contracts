// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Crypto} from "./Crypto.sol";
import {SupraOracleDecoder} from "./SupraOracleDecoder.sol";

// Start of Selection

/**
 * @title Dex
 * @dev Library for handling Dex operations
 */
library Dex {
    /**
     * @dev Constant for maintenance margin percentage
     */
    uint256 public constant MAINTENANCE_MARGIN_PERCENT = 50;
    /**
     * @dev Constant for backstop liquidation percentage
     */
    uint256 public constant BACKSTOP_LIQUIDATION_PERCENT = 6667;

    /**
     * @dev Get the price by pair ID
     * @param allFeeds Array of all feeds
     * @param pair Pair ID to retrieve price for
     * @return Price of the pair
     */
    function _getPriceByPairId(
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds,
        uint256 pair
    ) public pure returns (uint128) {
        for (uint256 i = 0; i < allFeeds.length; i++) {
            if (allFeeds[i].pair == pair) {
                // 3% discount for the oracle price and OB price variance
                return allFeeds[i].price * 97 / 100;
            }
        }

        revert("given pair not found");
    }

    /**
     * @dev Calculate the position loss
     * @param position Position data
     * @param allFeeds Array of all feeds
     * @return Loss amount of the position
     */
    function _getPositionLoss(
        Crypto.Position memory position,
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds
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

    /**
     * @dev Check if a position is liquidated
     * @param position Position data
     * @param allFeeds Array of all feeds
     * @param balances Array of balances
     * @return True if position is liquidated, false otherwise
     */
    function _checkLiquidatedPosition(
        Crypto.Position memory position,
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds,
        Crypto.Balance[] memory balances
    ) public pure returns (bool) {
        uint256 totalPositionLoss = 0;
        uint256 totalPositionInitialCollateral = 0;

        // position loss
        totalPositionLoss += _getPositionLoss(position, allFeeds);

        uint256 collateralCurrentValue = 0;
        for (uint256 j = 0; j < position.collaterals.length; j++) {
            collateralCurrentValue +=
                position.collaterals[j].quantity *
                _getPriceByPairId(allFeeds, position.collaterals[j].oracleId);
            totalPositionInitialCollateral +=
                position.collaterals[j].entryPrice *
                position.collaterals[j].quantity;
        }

        if (collateralCurrentValue > totalPositionInitialCollateral) {
            totalPositionLoss += 0;
        } else {
            totalPositionLoss +=
                totalPositionInitialCollateral -
                collateralCurrentValue;
        }

        // cross position
        if (
            keccak256(abi.encodePacked(position.leverageType)) ==
            keccak256(abi.encodePacked("cross"))
        ) {
            for (uint256 i = 0; i < balances.length; i++) {
                totalPositionInitialCollateral +=
                    balances[i].balance *
                    _getPriceByPairId(allFeeds, balances[i].oracleId);
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
