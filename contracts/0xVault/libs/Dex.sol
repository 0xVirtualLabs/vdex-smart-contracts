// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {Crypto} from "./Crypto.sol";
import {SupraOracleDecoder} from "./SupraOracleDecoder.sol";

library Dex {
    uint256 public constant MAINTENANCE_MARGIN_PERCENT = 50;
    uint256 public constant BACKSTOP_LIQUIDATION_PERCENT = 6667;

    function _getPriceByPairId(
        SupraOracleDecoder.CommitteeFeed[] memory allFeeds,
        uint32 pair
    ) public pure returns (uint128) {
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

        totalPositionLoss +=
            totalPositionInitialCollateral -
            collateralCurrentValue;

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