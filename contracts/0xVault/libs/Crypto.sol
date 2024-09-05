// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

library Crypto {
    uint256 private constant SECP256K1_CURVE_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    error InvalidSignature();
    error InvalidUsedSignature();
    error InvalidSchnorrSignature();
    error InvalidSP();
    error ECRecoverFailed();
    error InvalidAddress();
    error DisputeChallengeFailed();
    error SettleDisputeFailed();

    /**
     * @dev Struct representing the balance of a token.
     */
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    /**
     * @dev Struct representing parameters for trustless withdrawal.
     */
    struct WithdrawTrustlesslyParams {
        TokenBalance[] tokenBalances;
        uint64 timestamp;
        SchnorrSignature schnorr;
    }

    /**
     * @dev Struct representing a Schnorr signature.
     */
    struct SchnorrSignature {
        bytes data;
        bytes signature;
        address combinedPublicKey;
    }

    /**
     * @dev Struct representing parameters for withdrawal.
     */
    struct WithdrawParams {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    /**
     * @dev Struct representing data for a Schnorr withdrawal.
     */
    struct SchnorrDataWithdraw {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    // for liquidation case
    /**
     * @dev Struct representing the price of an asset in an Oracle.
     */
    struct OraclePrice {
        uint256 positionId;
        address token;
        uint256 price;
        uint64 timestamp;
    }

    /**
     * @dev Struct representing a user's balance.
     */
    struct Balance {
        uint256 oracleId;
        address addr;
        uint256 balance;
    }

    /**
     * @dev Struct representing collateral for a position.
     */
    struct Collateral {
        uint256 oracleId;
        address token;
        uint256 quantity;
        uint256 entryPrice;
    }

    /**
     * @dev Struct representing a liquidated position.
     */
    struct LiquidatedPosition {
        string positionId;
        bytes proofBytes;
    }

    /**
     * @dev Struct representing an update to a dispute.
     */
    struct UpdateDispute {
        uint32 disputeId;
    }

    /**
     * @dev Struct representing a trading position.
     */
    struct Position {
        string positionId;
        uint256 oracleId;
        address token;
        uint256 quantity;
        uint256 leverageFactor;
        string leverageType;
        bool isLong;
        Collateral[] collaterals;
        uint256 entryPrice;
        uint256 createdTimestamp;
    }

    /**
     * @dev Struct representing Schnorr signature data.
     */
    struct SchnorrData {
        uint32 signatureId;
        address addr;
        Balance[] balances;
        Position[] positions;
        string sigType;
        uint256 timestamp;
    }

    /**
     * @dev Struct representing Schnorr data for closing a position.
     */
    struct ClosePositionSchnorrData {
        uint32 signatureId;
        address addr;
        Position[] positions;
        string sigType;
        uint256 timestamp;
    }

    /**
     * @dev Enum representing the status of a dispute.
     */
    enum DisputeStatus {
        None,
        Opened,
        Challenged,
        Settled
    }

    /**
     * @dev Struct representing a dispute.
     */
    struct Dispute {
        address user;
        address challenger;
        uint64 timestamp;
        Balance[] balances;
        uint8 status;
        uint32 sessionId;
    }

    /**
     * @dev Struct representing a dispute for closing a position.
     */
    struct ClosePositionDispute {
        address user;
        address challenger;
        uint64 timestamp;
        Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

    /**
     * @dev Decodes Schnorr data from a Schnorr signature.
     * @param _schnorr The Schnorr signature to decode.
     * @return The decoded Schnorr data.
     */
    function decodeSchnorrData(
        Crypto.SchnorrSignature calldata _schnorr
    ) external pure returns (SchnorrData memory) {
        // if (!_verifySchnorrSignature(_schnorr, combinedPublicKey)) {
        //     revert InvalidSchnorrSignature();
        // }
        (
            uint32 signatureId,
            address addr,
            Balance[] memory balances,
            Position[] memory positions,
            string memory sigType,
            uint256 timestamp
        ) = abi.decode(
                _schnorr.data,
                (uint32, address, Balance[], Position[], string, uint256)
            );
        return
            SchnorrData(
                signatureId,
                addr,
                balances,
                positions,
                sigType,
                timestamp
            );
    }

    /**
     * @dev Decodes Schnorr data from a Schnorr signature for withdrawal.
     * @param _schnorr The Schnorr signature to decode.
     * @param combinedPublicKey The combined public key to verify the signature.
     * @return The decoded Schnorr data for withdrawal.
     */
    function decodeSchnorrDataWithdraw(
        Crypto.SchnorrSignature calldata _schnorr,
        address combinedPublicKey
    ) external view returns (SchnorrDataWithdraw memory) {
        if (!_verifySchnorrSignature(_schnorr, combinedPublicKey)) {
            revert InvalidSchnorrSignature();
        }
        (address trader, address token, uint256 amount, uint64 timestamp) = abi
            .decode(_schnorr.data, (address, address, uint256, uint64));
        return SchnorrDataWithdraw(trader, token, amount, timestamp);
    }

    /**
     * @dev Verifies an ECDSA signature.
     * @param _digest The digest to be signed.
     * @param _signature The signature to be verified.
     * @param _trustedSigner The address of the trusted signer.
     */
    function _verifySignature(
        bytes32 _digest,
        bytes calldata _signature,
        address _trustedSigner
    ) external pure {
        // if (_signatureUsed[_signature]) {
        //     revert InvalidUsedSignature();
        // }

        bytes32 _ethSignedMessage = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _digest)
        );

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);

        address signer = ecrecover(_ethSignedMessage, v, r, s);

        if (signer != _trustedSigner) {
            revert InvalidSignature();
        }
        // _signatureUsed[_signature] = true;
    }

    /**
     * @dev Splits a signature into its components.
     * @param sig The signature to split.
     * @return r The R component of the signature.
     * @return s The S component of the signature.
     * @return v The V component of the signature.
     */
    function _splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /**
     * @dev Verifies a Schnorr signature.
     * @param _schnorr The Schnorr signature to verify.
     * @param _combinedPublicKey The combined public key to verify the signature.
     * @return True if the signature is valid, otherwise false.
     */
    function _verifySchnorrSignature(
        SchnorrSignature memory _schnorr,
        address _combinedPublicKey
    ) public view returns (bool) {
        // if (_schnorrSignatureUsed[_schnorr.signature]) {
        //     revert InvalidSchnorrSignature();
        // }

        if (_schnorr.combinedPublicKey != _combinedPublicKey) {
            revert InvalidSchnorrSignature();
        }

        if (_schnorr.signature.length != 128) {
            revert InvalidSchnorrSignature();
        }

        (bytes32 px, bytes32 e, bytes32 s, uint8 parity) = abi.decode(
            _schnorr.signature,
            (bytes32, bytes32, bytes32, uint8)
        );
        bytes32 sp = bytes32(
            SECP256K1_CURVE_N -
                mulmod(uint256(s), uint256(px), SECP256K1_CURVE_N)
        );
        bytes32 ep = bytes32(
            SECP256K1_CURVE_N -
                mulmod(uint256(e), uint256(px), SECP256K1_CURVE_N)
        );

        if (sp == 0) {
            revert InvalidSP();
        }

        address R = ecrecover(sp, parity, px, ep);
        if (R == address(0)) {
            revert ECRecoverFailed();
        }

        if (
            e ==
            keccak256(
                abi.encodePacked(R, uint8(parity), px, keccak256(_schnorr.data), block.chainid)
            ) &&
            address(uint160(uint256(px))) == _schnorr.combinedPublicKey
        ) {
            // _schnorrSignatureUsed[_schnorr.signature] = true;

            return true;
        }

        return false;
    }
}
