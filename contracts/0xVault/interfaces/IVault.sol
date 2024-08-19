// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;
import {Crypto} from "../libs/Crypto.sol";

interface IVault {
    struct Dispute {
        address user;
        address challenger;
        uint64 timestamp;
        Crypto.Balance[] balances;
        Crypto.Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

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

    function depositedAmount(
        address user,
        address token
    ) external view returns (uint256);

    function settleDisputeResult(
        uint32 requestId,
        uint256[] memory updatedBalances,
        uint256[] memory pnlValues,
        bool[] memory isProfits
    ) external;

    function combinedPublicKey(address user) external view returns (address);

    function _disputes(uint32 reqId) external view returns (Dispute memory);

    function updatePartialLiquidation(
        address user,
        address[] memory tokens,
        uint256[] memory losses,
        uint256 totalLossCount
    ) external;
}
