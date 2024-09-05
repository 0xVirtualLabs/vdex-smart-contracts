// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

/**
 * @title IOracle
 * @dev Interface for interacting with the Oracle contract.
 */
interface IOracle {
    /**
     * @dev Struct representing price feed data.
     */
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    /**
     * @dev Retrieves the price feed data for a specific pair index.
     * @param pairIndex The index of the pair to retrieve data for.
     * @return The price feed data for the specified pair index.
     */
    function getSvalue(uint256 pairIndex) external view returns (priceFeed memory);
}
