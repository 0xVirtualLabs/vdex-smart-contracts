// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface ILpProvider {
    function increaseLpProvidedAmount(address token, uint256 amount) external;

    function decreaseLpProvidedAmount(address token, uint256 amount) external;

    function isTokenSupported(address token) external view returns (bool);
}
