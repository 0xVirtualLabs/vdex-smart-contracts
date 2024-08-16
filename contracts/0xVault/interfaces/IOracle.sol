// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IOracle {
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    function getSvalue(address pairIndex) external view returns (priceFeed memory);
}
