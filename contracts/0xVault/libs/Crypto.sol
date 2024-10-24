// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

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
    error InvalidChainId();

    struct TokenBalance {
        address token;
        uint256 balance;
    }

    struct WithdrawTrustlesslyParams {
        TokenBalance[] tokenBalances;
        uint64 timestamp;
        SchnorrSignature schnorr;
    }

    struct SchnorrSignature {
        bytes data;
        bytes signature;
        address combinedPublicKey;
    }

    struct WithdrawParams {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
    }

    struct SchnorrDataWithdraw {
        address trader;
        address token;
        uint256 amount;
        uint64 timestamp;
        uint256 chainId;
    }

    // for liquidation case
    struct OraclePrice {
        uint256 positionId;
        address token;
        uint256 price;
        uint64 timestamp;
    }

    struct Balance {
        bytes32 oracleId;
        address addr;
        uint256 balance;
    }

    struct Collateral {
        bytes32 oracleId;
        address token;
        uint256 quantity;
        uint256 entryPrice;
    }

    struct LiquidatedPosition {
        string positionId;
        bytes[] updateData;
        bytes32[] priceIds;
        uint64 minPublishTime;
        uint64 maxPublishTime;
    }

    struct UpdateDispute {
        uint32 disputeId;
        
    }

    struct Position {
        string positionId;
        bytes32 oracleId;
        address token;
        uint256 quantity;
        uint256 leverageFactor;
        string leverageType;
        bool isLong;
        Collateral[] collaterals;
        uint256 entryPrice;
        uint256 createdTimestamp;
    }

    struct SchnorrData {
        uint32 signatureId;
        address addr;
        Balance[] balances;
        Position[] positions;
        string sigType;
        uint256 timestamp;
        uint256 chainId;
    }

    struct ClosePositionSchnorrData {
        uint32 signatureId;
        address addr;
        Position[] positions;
        string sigType;
        uint256 timestamp;
    }

    enum DisputeStatus {
        None,
        Opened,
        Challenged,
        Settled
    }

    struct Dispute {
        address user;
        address challenger;
        uint64 timestamp;
        Balance[] balances;
        uint8 status;
        uint32 sessionId;
    }

    struct ClosePositionDispute {
        address user;
        address challenger;
        uint64 timestamp;
        Position[] positions;
        uint8 status;
        uint32 sessionId;
    }

    function decodeSchnorrData(
        Crypto.SchnorrSignature calldata _schnorr
    ) external view returns (SchnorrData memory) {
        // if (!_verifySchnorrSignature(_schnorr, combinedPublicKey)) {
        //     revert InvalidSchnorrSignature();
        // }
        (
            uint32 signatureId,
            address addr,
            Balance[] memory balances,
            Position[] memory positions,
            string memory sigType,
            uint256 timestamp,
            uint256 chainId
        ) = abi.decode(
                _schnorr.data,
                (uint32, address, Balance[], Position[], string, uint256, uint256)
            );
        if (chainId != block.chainid) {
            revert InvalidChainId();
        }
        return
            SchnorrData(
                signatureId,
                addr,
                balances,
                positions,
                sigType,
                timestamp,
                chainId
            );
    }

    function decodeSchnorrDataWithdraw(
        Crypto.SchnorrSignature calldata _schnorr,
        address combinedPublicKey
    ) external view returns (SchnorrDataWithdraw memory) {
        if (!_verifySchnorrSignature(_schnorr, combinedPublicKey)) {
            revert InvalidSchnorrSignature();
        }
        (address trader, address token, uint256 amount, uint64 timestamp, uint256 chainId) = abi
            .decode(_schnorr.data, (address, address, uint256, uint64, uint256));
        if (chainId != block.chainid) {
            revert InvalidChainId();
        }
        return SchnorrDataWithdraw(trader, token, amount, timestamp, chainId);
    }

    //  /**
    //  * @dev Internal function to check the validity of a signature against a digest and mark the signature as used.
    //  *
    //  * @param _digest (bytes32) The digest to be signed.
    //  * @param _signature (bytes) The signature to be verified.
    //  */
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
     * @dev Internal function to verify a Schnorr signature.
     *
     * @param _schnorr (SchnorrSignature) The Schnorr signature to be verified.
     *
     * @return (bool) True if the Schnorr signature is valid, otherwise false.
     */
    function _verifySchnorrSignature(
        SchnorrSignature memory _schnorr,
        address _combinedPublicKey
    ) public pure returns (bool) {
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
                abi.encodePacked(R, uint8(parity), px, keccak256(_schnorr.data))
            ) &&
            address(uint160(uint256(px))) == _schnorr.combinedPublicKey
        ) {
            // _schnorrSignatureUsed[_schnorr.signature] = true;

            return true;
        }

        return false;
    }
}
