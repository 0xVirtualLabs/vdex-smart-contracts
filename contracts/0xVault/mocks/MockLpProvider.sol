// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {ILpProvider} from "../interfaces/ILpProvider.sol";

/// @dev Minimal LpProvider stub for tests: every token is supported and the
/// accounting hooks are no-ops. Only `isTokenSupported` is exercised by
/// `Vault.withdrawSchnorr`.
contract MockLpProvider is ILpProvider {
    function increaseLpProvidedAmount(address, uint256) external {}

    function decreaseLpProvidedAmount(address, uint256) external {}

    function isTokenSupported(address) external pure returns (bool) {
        return true;
    }
}
