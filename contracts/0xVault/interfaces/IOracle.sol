// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IOracle {
    function decimals() external view returns (uint8);
    function getPrice(address token) external view returns (uint256);
}