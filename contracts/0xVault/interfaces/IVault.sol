// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IVault {
    function isTokenSupported(address token) external view returns (bool);
}