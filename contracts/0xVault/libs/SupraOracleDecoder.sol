// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

/**
 * @title SupraOracleDecoder
 * @dev Library for decoding Oracle proofs in the Supra system.
 */
library SupraOracleDecoder {
    /**
     * @dev Struct representing a feed from a committee.
     */
    struct CommitteeFeed {
        uint32 pair;
        uint128 price;
        uint64 timestamp;
        uint16 decimals;
        uint64 round;
    }

    /**
     * @dev Struct representing a feed from a committee with proof.
     */
    struct CommitteeFeedWithProof {
        CommitteeFeed[] committee_feeds;
        bytes32[] proofs;
        bool[] flags;
    }

    /**
     * @dev Struct representing price details with committee information.
     */
    struct PriceDetailsWithCommittee {
        uint64 committee_id;
        bytes32 root;
        uint256[2] sigs;
        CommitteeFeedWithProof committee_data;
    }

    /**
     * @dev Struct representing an Oracle proof in version 2.
     */
    struct OracleProofV2 {
        PriceDetailsWithCommittee[] data;
    }

    /**
     * @notice Decode the Oracle proof from bytes.
     * @param _bytesProof The Oracle proof in bytes.
     * @return Decoded Oracle proof in version 2.
     */
    function decodeOracleProof(
        bytes calldata _bytesProof
    ) external pure returns (OracleProofV2 memory) {
        return abi.decode(_bytesProof, (OracleProofV2));
    }
}
