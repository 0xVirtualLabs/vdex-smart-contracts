// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface ILpProvider {
        function increaseLpProvidedAmount(address token, uint256 amount) external;

        function decreaseLpProvidedAmount(address user, address token, uint256 amount) external;
}