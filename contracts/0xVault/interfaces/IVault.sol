// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;
import {Crypto} from "../libs/Crypto.sol";

interface IVault {
    function isTokenSupported(address token) external view returns (bool);

    function updateLiquidatedPositions(
        uint32 requestId,
        uint256[] memory liquidatedIndexes,
        uint256 liquidatedCount,
        bool isCrossLiquidated
    ) external;

    function getDisputeStatus(
        uint32 requestId
    )
        external
        view
        returns (bool isOpenDispute, uint64 timestamp, address user);

    function getDisputePositions(
        uint32 requestId
    ) external view returns (Crypto.Position[] memory);

    function getDisputeBalances(
        uint32 requestId
    ) external view returns (Crypto.Balance[] memory);

    function getDepositedAmount(
        address user,
        address token
    ) external view returns (uint256);

    function settleDisputeResult(
        uint32 requestId,
        uint256[] memory updatedBalances,
        uint256[] memory pnlValues,
        bool[] memory isProfits
    ) external;
}
