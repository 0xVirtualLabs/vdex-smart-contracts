// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

contract MockOracle {
    uint256 public decimals = 6;
    // return prices withd decimals
    function getPrice(address token) external view returns (uint256) {
        return 3000 * (10 ** uint256(decimals));
    }
}