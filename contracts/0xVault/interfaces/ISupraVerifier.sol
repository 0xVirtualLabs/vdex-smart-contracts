// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

/**
 * @title ISupraVerifier
 * @dev Interface for Supra Verifier contract
 */
interface ISupraVerifier {
    /**
     * @notice Checks if a pair is already added for HCC
     * @param _pairIndexes Array of pair indexes to check
     * @return Whether the pair is already added
     */
    function isPairAlreadyAddedForHCC(uint256[] calldata _pairIndexes) external view returns (bool);

    /**
     * @notice Checks if a pair is already added for HCC
     * @param _pairId The pair ID to check
     * @return Whether the pair is already added
     */
    function isPairAlreadyAddedForHCC(uint256 _pairId) external view returns (bool);

    /**
     * @notice Requires hash verification for version 2
     * @param message The message hash to verify
     * @param signature The signature to verify
     * @param committee_id The committee ID
     */
    function requireHashVerified_V2(bytes32 message, uint256[2] memory signature, uint256 committee_id) external view;

    /**
     * @notice Requires hash verification for version 1
     * @param message The message to verify
     * @param signature The signature to verify
     */
    function requireHashVerified_V1(bytes memory message, uint256[2] memory signature) external view;
}
