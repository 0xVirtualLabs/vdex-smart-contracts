// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;
import {Crypto} from "../libs/Crypto.sol";

/**
 * @title IVault
 * @dev Interface for interacting with the Vault contract.
 */
interface IVault {
    /**
     * @dev Struct representing a dispute in the Vault.
     */
    struct Dispute {
        address user;
        address challenger;
        uint64 timestamp;
        Crypto.Balance[] balances;
        Crypto.Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

    /**
     * @dev Checks if a token is supported by the Vault.
     */
    function isTokenSupported(address token) external view returns (bool);

    /**
     * @dev Updates the positions that have been liquidated in the Vault.
     */
    function updateLiquidatedPositions(
        uint32 requestId,
        uint256[] memory liquidatedIndexes,
        uint256 liquidatedCount,
        bool isCrossLiquidated
    ) external;

    /**
     * @dev Retrieves the status of a dispute in the Vault.
     */
    function getDisputeStatus(
        uint32 requestId
    )
        external
        view
        returns (bool isOpenDispute, uint64 timestamp, address user);

    /**
     * @dev Retrieves the positions involved in a dispute in the Vault.
     */
    function getDisputePositions(
        uint32 requestId
    ) external view returns (Crypto.Position[] memory);

    /**
     * @dev Retrieves the balances involved in a dispute in the Vault.
     */
    function getDisputeBalances(
        uint32 requestId
    ) external view returns (Crypto.Balance[] memory);

    /**
     * @dev Retrieves the amount deposited by a user for a specific token in the Vault.
     */
    function depositedAmount(
        address user,
        address token
    ) external view returns (uint256);

    /**
     * @dev Settles the result of a dispute in the Vault.
     */
    function settleDisputeResult(
        uint32 requestId,
        uint256[] memory updatedBalances,
        uint256[] memory pnlValues,
        bool[] memory isProfits
    ) external;

    /**
     * @dev Retrieves the combined public key of a user in the Vault.
     */
    function combinedPublicKey(address user) external view returns (address);

    /**
     * @dev Retrieves a specific dispute in the Vault.
     */
    function _disputes(uint32 reqId) external view returns (Dispute memory);

    /**
     * @dev Updates the partial liquidation of a user in the Vault.
     */
    function updatePartialLiquidation(
        address user,
        address[] memory tokens,
        uint256[] memory losses,
        uint256 totalLossCount
    ) external;

    /**
     * @dev Sets a Schnorr signature as used in the Vault.
     */
    function setSchnorrSignatureUsed(bytes calldata signature) external;

    /**
     * @dev Checks if a Schnorr signature has been used in the Vault.
     */
    function isSchnorrSignatureUsed(
        bytes calldata signature
    ) external view returns (bool);
}
