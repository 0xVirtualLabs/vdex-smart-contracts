// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

library SupraOracleDecoder {
    struct CommitteeFeed {
        uint32 pair;
        uint128 price;
        uint64 timestamp;
        uint16 decimals;
        uint64 round;
    }

    struct CommitteeFeedWithProof {
        CommitteeFeed[] committee_feeds;
        bytes32[] proofs;
        bool[] flags;
    }

    struct PriceDetailsWithCommittee {
        uint64 committee_id;
        bytes32 root;
        uint256[2] sigs;
        CommitteeFeedWithProof committee_data;
    }

    struct OracleProofV2 {
        PriceDetailsWithCommittee[] data;
    }

    function decodeOracleProof(
        bytes calldata _bytesProof
    ) external pure returns (OracleProofV2 memory) {
        return abi.decode(_bytesProof, (OracleProofV2));
    }
}
