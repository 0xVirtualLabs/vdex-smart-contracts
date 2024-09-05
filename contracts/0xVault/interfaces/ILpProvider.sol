// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface ILpProvider {
    /**
     * @dev Increases the amount of liquidity provided for a specific token.
     * @param token The address of the token for which liquidity is being increased.
     * @param amount The amount by which liquidity is being increased.
     */
    function increaseLpProvidedAmount(address token, uint256 amount) external;

    /**
     * @dev Decreases the amount of liquidity provided by a specific user for a specific token.
     * @param user The address of the user whose liquidity is being decreased.
     * @param token The address of the token for which liquidity is being decreased.
     * @param amount The amount by which liquidity is being decreased.
     */
    function decreaseLpProvidedAmount(
        address user,
        address token,
        uint256 amount
    ) external;
}
