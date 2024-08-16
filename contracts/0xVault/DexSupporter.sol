// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {SupraOracleDecoder} from "./libs/SupraOracleDecoder.sol";
import {Crypto} from "./libs/Crypto.sol";
import {Dex} from "./libs/Dex.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ISupraVerifier} from "./interfaces/ISupraVerifier.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ILpProvider} from "./interfaces/ILpProvider.sol";

contract DexSupporter {
    IVault public vault;
    address public supraVerifier;
    address public supraStorageOracle;
    address public lpProvider;
    uint256 constant ONE = 1e9;

    constructor(
        address _vault,
        address _supraVerifier,
        address _supraStorageOracle,
        address _lpProvider
    ) {
        vault = IVault(_vault);
        supraVerifier = _supraVerifier;
        supraStorageOracle = _supraStorageOracle;
        lpProvider = _lpProvider;
    }

    function challengeLiquidatedPosition(
        uint32 requestId,
        Crypto.LiquidatedPosition[] memory positions
    ) external {
        uint256 liquidatedLen = positions.length;

        (
            bool isOpenDispute,
            uint64 disputeTimestamp,
            address _disputeUser
        ) = vault.getDisputeStatus(requestId);
        require(isOpenDispute, "Invalid dispute status");
        require(
            block.timestamp < disputeTimestamp + 1800, // fake 30m
            "Dispute window closed"
        );

        for (uint256 i = 0; i < liquidatedLen; i++) {
            SupraOracleDecoder.OracleProofV2 memory oracle = SupraOracleDecoder
                .decodeOracleProof(positions[i].proofBytes);
            // verify oracle proof
            uint256 orcLen = oracle.data.length;
            for (uint256 j = 0; j < orcLen; j++) {
                requireRootVerified(
                    oracle.data[j].root,
                    oracle.data[j].sigs,
                    oracle.data[j].committee_id
                );
            }
        }

        Crypto.Position[] memory disputePositions = vault.getDisputePositions(
            requestId
        );
        Crypto.Balance[] memory disputeBalances = vault.getDisputeBalances(
            requestId
        );

        uint256[] memory liquidatedIndexes = new uint256[](
            disputePositions.length
        );
        uint256 liquidatedCount = 0;
        bool isCrossLiquidated = false;

        for (uint i = 0; i < disputePositions.length; i++) {
            // no leverage
            if (disputePositions[i].leverageFactor == 1) {
                continue;
            }

            // loop over liquidated positions
            for (uint j = 0; j < liquidatedLen; j++) {
                if (
                    keccak256(bytes(disputePositions[i].positionId)) !=
                    keccak256(bytes(positions[j].positionId))
                ) {
                    continue;
                }

                // get priceFeeds for position
                SupraOracleDecoder.CommitteeFeed[] memory positionFeeds;
                SupraOracleDecoder.OracleProofV2
                    memory oracle = SupraOracleDecoder.decodeOracleProof(
                        positions[j].proofBytes
                    );
                uint256 feedIndex = 0;
                for (uint256 k = 0; k < oracle.data.length; k++) {
                    SupraOracleDecoder.CommitteeFeed[] memory feeds = oracle
                        .data[k]
                        .committee_data
                        .committee_feeds;
                    for (uint256 t = 0; t < feeds.length; t++) {
                        positionFeeds[feedIndex] = feeds[t];
                        feedIndex++;
                    }
                }
                if (
                    Dex._checkLiquidatedPosition(
                        disputePositions[i],
                        positionFeeds,
                        disputeBalances
                    )
                ) {
                    liquidatedIndexes[liquidatedCount] = i;
                    liquidatedCount++;
                    if (
                        keccak256(
                            abi.encodePacked(disputePositions[i].leverageType)
                        ) == keccak256(abi.encodePacked("cross"))
                    ) {
                        isCrossLiquidated = true;
                    }
                }
            }
        }

        // Update the dispute in the Vault contract
        vault.updateLiquidatedPositions(
            requestId,
            liquidatedIndexes,
            liquidatedCount,
            isCrossLiquidated
        );
    }

    function settleDispute(uint32 requestId) external {
        (
            bool isOpenedDispute,
            uint64 disputeTimestamp,
            address disputeUser
        ) = vault.getDisputeStatus(requestId);
        require(isOpenedDispute, "Invalid dispute status");
        require(
            block.timestamp > disputeTimestamp + 1800, // fake 30m
            "Dispute window not closed"
        );

        Crypto.Position[] memory positions = vault.getDisputePositions(
            requestId
        );
        Crypto.Balance[] memory balances = vault.getDisputeBalances(requestId);

        uint256[] memory updatedBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            updatedBalances[i] = balances[i].balance;
        }

        for (uint i = 0; i < positions.length; i++) {
            if (positions[i].quantity == 0) {
                continue;
            }
            IOracle.priceFeed memory oraclePrice = IOracle(supraStorageOracle)
                .getSvalue(positions[i].oracleId);

            int256 priceChange = (int256(oraclePrice.price) -
                int256(positions[i].entryPrice));
            if (!positions[i].isLong) {
                priceChange = -priceChange;
            }
            int256 multiplier = (1 +
                (priceChange * int256(positions[i].leverageFactor)) /
                int256(positions[i].entryPrice));
            if (multiplier < 0) {
                continue;
            }
            uint256 uMul = uint256(multiplier);

            for (uint256 j = 0; j < positions[i].collaterals.length; j++) {
                IOracle.priceFeed memory collateralOraclePrice = IOracle(
                    supraStorageOracle
                ).getSvalue(positions[i].collaterals[j].oracleId);

                uint256 transferAmount = (((positions[i]
                    .collaterals[j]
                    .quantity * uMul) / ONE) * collateralOraclePrice.price) /
                    collateralOraclePrice.decimals;

                // Update balance instead of transferring directly
                for (uint256 k = 0; k < balances.length; k++) {
                    if (balances[k].addr == positions[i].token) {
                        updatedBalances[k] += transferAmount;
                        break;
                    }
                }

                positions[i].collaterals[j].quantity = 0;
            }
        }

        uint256[] memory pnlValues = new uint256[](balances.length);
        bool[] memory isProfits = new bool[](balances.length);

        for (uint256 i = 0; i < balances.length; i++) {
            address token = balances[i].addr;
            uint256 amount = updatedBalances[i];
            uint256 depositedAmount = vault.getDepositedAmount(
                disputeUser,
                token
            );

            if (amount > depositedAmount) {
                pnlValues[i] = amount - depositedAmount;
                isProfits[i] = true;
            } else {
                pnlValues[i] = depositedAmount - amount;
                isProfits[i] = false;
            }
        }

        vault.settleDisputeResult(
            requestId,
            updatedBalances,
            pnlValues,
            isProfits
        );
    }

    function requireRootVerified(
        bytes32 root,
        uint256[2] memory sigs,
        uint256 committee_id
    ) private view {
        (bool status, ) = address(supraVerifier).staticcall(
            abi.encodeCall(
                ISupraVerifier.requireHashVerified_V2,
                (root, sigs, committee_id)
            )
        );
        require(status, "Data not verified");
    }
}
