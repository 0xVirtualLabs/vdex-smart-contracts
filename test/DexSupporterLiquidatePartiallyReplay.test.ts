import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import {
  getAddress,
  encodeAbiParameters,
  zeroHash,
  type Hex,
  type Address,
} from "viem";
import { signSchnorr } from "./helpers/schnorr";

const SIGNER_PRIV = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

// ABI shape of Crypto.SchnorrData, matching
// abi.decode(data, (uint32, address, Balance[], Position[], string, uint256, uint256))
const balanceComponents = [
  { name: "oracleId", type: "bytes32" },
  { name: "addr", type: "address" },
  { name: "balance", type: "uint256" },
] as const;

const collateralComponents = [
  { name: "oracleId", type: "bytes32" },
  { name: "token", type: "address" },
  { name: "quantity", type: "uint256" },
  { name: "entryPrice", type: "uint256" },
] as const;

const positionComponents = [
  { name: "positionId", type: "string" },
  { name: "oracleId", type: "bytes32" },
  { name: "token", type: "address" },
  { name: "quantity", type: "uint256" },
  { name: "leverageFactor", type: "uint256" },
  { name: "leverageType", type: "string" },
  { name: "isLong", type: "bool" },
  { name: "collaterals", type: "tuple[]", components: collateralComponents },
  { name: "entryPrice", type: "uint256" },
  { name: "createdTimestamp", type: "uint256" },
] as const;

const schnorrDataParams = [
  { name: "signatureId", type: "uint32" },
  { name: "addr", type: "address" },
  { name: "balances", type: "tuple[]", components: balanceComponents },
  { name: "positions", type: "tuple[]", components: positionComponents },
  { name: "sigType", type: "string" },
  { name: "timestamp", type: "uint256" },
  { name: "chainId", type: "uint256" },
] as const;

function encodeSchnorrData(user: Address, chainId: bigint): Hex {
  // Minimal payload: one zero balance, no positions => no realized loss.
  return encodeAbiParameters(schnorrDataParams as any, [
    1, // signatureId
    user,
    [{ oracleId: zeroHash, addr: user, balance: 0n }],
    [],
    "partialLiquidate",
    0n,
    chainId,
  ]);
}

describe("DexSupporter.liquidatePartially replay guard", () => {
  async function deployFixture() {
    const [owner, user] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const crypto = await hre.viem.deployContract("contracts/0xVault/libs/Crypto.sol:Crypto");
    const dex = await hre.viem.deployContract("contracts/0xVault/libs/Dex.sol:Dex");

    const vault = await hre.viem.deployContract("Vault", [], {
      libraries: { Crypto: crypto.address },
    });

    const dummy = owner.account.address; // stand-in for pyth oracle / lp provider (unused on this path)
    await vault.write.initialize([owner.account.address, 10n ** 12n, dummy, dummy]);

    const dexSupporter = await hre.viem.deployContract(
      "DexSupporter",
      [vault.address, dummy, dummy],
      { libraries: { Crypto: crypto.address, Dex: dex.address } }
    );

    // Register the DexSupporter so vault.updatePartialLiquidation accepts its calls.
    await vault.write.setVaultParameters([10n ** 12n, dexSupporter.address, dummy]);

    return { owner, user, publicClient, vault, dexSupporter };
  }

  it("consumes a partial-liquidation signature once, then rejects its replay", async () => {
    const { user, publicClient, vault, dexSupporter } = await loadFixture(deployFixture);

    const userAddr = getAddress(user.account.address);
    const chainId = BigInt(await publicClient.getChainId());

    const data = encodeSchnorrData(userAddr, chainId);
    const sig = signSchnorr(SIGNER_PRIV, data);

    await vault.write.setCombinedPublicKey([userAddr, sig.combinedPublicKey]);

    const schnorr = {
      data: sig.data,
      signature: sig.signature,
      combinedPublicKey: sig.combinedPublicKey,
    };

    // First call succeeds (no deposit => zero loss, but the signature is now consumed).
    await dexSupporter.write.liquidatePartially([userAddr, schnorr]);

    // Replaying the identical signature must revert (guard: _schnorrSignatureUsed).
    await expect(
      dexSupporter.write.liquidatePartially([userAddr, schnorr])
    ).to.be.rejected;
  });
});
