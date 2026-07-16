import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { getAddress, parseUnits } from "viem";
import { buildWithdrawSchnorr } from "./helpers/schnorr";

// Operator "combined public key" signing key (any valid secp256k1 scalar;
// this is hardhat dev account #1's key). It is independent of the trader
// account — it stands in for the off-chain MPC combined key.
const SIGNER_PRIV = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

describe("Vault.withdrawSchnorr replay guard", () => {
  async function deployFixture() {
    const [owner, trader] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const crypto = await hre.viem.deployContract(
      "contracts/0xVault/libs/Crypto.sol:Crypto"
    );
    const lp = await hre.viem.deployContract("MockLpProvider");
    const token = await hre.viem.deployContract("MockERC20");

    const vault = await hre.viem.deployContract("Vault", [], {
      libraries: { Crypto: crypto.address },
    });

    const expiry = 10n ** 12n; // effectively no time limit for the test
    await vault.write.initialize([
      owner.account.address,
      expiry,
      lp.address,
      owner.account.address, // dexSupporter (unused here)
    ]);

    return { owner, trader, publicClient, vault, token };
  }

  it("processes a valid withdrawal once, then rejects replay of the same signature", async () => {
    const { trader, publicClient, vault, token } = await loadFixture(deployFixture);

    const traderAddr = getAddress(trader.account.address);
    const tokenAddr = getAddress(token.address);
    const amount = parseUnits("100", 18);

    await token.write.mint([vault.address, parseUnits("1000", 18)]);

    const ts = (await publicClient.getBlock()).timestamp;
    const chainId = BigInt(await publicClient.getChainId());

    const sig = buildWithdrawSchnorr(SIGNER_PRIV, {
      trader: traderAddr,
      token: tokenAddr,
      amount,
      timestamp: ts,
      chainId,
    });

    // owner registers the operator combined key for the trader
    await vault.write.setCombinedPublicKey([traderAddr, sig.combinedPublicKey]);

    const schnorr = {
      data: sig.data,
      signature: sig.signature,
      combinedPublicKey: sig.combinedPublicKey,
    };

    const vaultAsTrader = await hre.viem.getContractAt("Vault", vault.address, {
      client: { wallet: trader },
    });

    // First withdrawal succeeds and moves `amount` to the trader.
    const before = await token.read.balanceOf([traderAddr]);
    await vaultAsTrader.write.withdrawSchnorr([sig.combinedPublicKey, schnorr]);
    const after = await token.read.balanceOf([traderAddr]);
    expect(after - before).to.equal(amount);

    // Replaying the identical signature must revert (guard: _schnorrSignatureUsed).
    // Before the fix this second call succeeded and drained another `amount`.
    await expect(
      vaultAsTrader.write.withdrawSchnorr([sig.combinedPublicKey, schnorr])
    ).to.be.rejected;

    // The trader received exactly one payout, not two.
    const final = await token.read.balanceOf([traderAddr]);
    expect(final - before).to.equal(amount);
  });

  it("still accepts a second, distinct valid signature (guard does not block fresh withdrawals)", async () => {
    const { trader, publicClient, vault, token } = await loadFixture(deployFixture);

    const traderAddr = getAddress(trader.account.address);
    const tokenAddr = getAddress(token.address);

    await token.write.mint([vault.address, parseUnits("1000", 18)]);

    const ts = (await publicClient.getBlock()).timestamp;
    const chainId = BigInt(await publicClient.getChainId());

    const sigA = buildWithdrawSchnorr(SIGNER_PRIV, {
      trader: traderAddr,
      token: tokenAddr,
      amount: parseUnits("100", 18),
      timestamp: ts,
      chainId,
    });
    // Distinct payload (different amount) => distinct signature.
    const sigB = buildWithdrawSchnorr(SIGNER_PRIV, {
      trader: traderAddr,
      token: tokenAddr,
      amount: parseUnits("101", 18),
      timestamp: ts,
      chainId,
    });

    await vault.write.setCombinedPublicKey([traderAddr, sigA.combinedPublicKey]);

    const vaultAsTrader = await hre.viem.getContractAt("Vault", vault.address, {
      client: { wallet: trader },
    });

    const before = await token.read.balanceOf([traderAddr]);
    await vaultAsTrader.write.withdrawSchnorr([
      sigA.combinedPublicKey,
      { data: sigA.data, signature: sigA.signature, combinedPublicKey: sigA.combinedPublicKey },
    ]);
    await vaultAsTrader.write.withdrawSchnorr([
      sigB.combinedPublicKey,
      { data: sigB.data, signature: sigB.signature, combinedPublicKey: sigB.combinedPublicKey },
    ]);
    const after = await token.read.balanceOf([traderAddr]);
    expect(after - before).to.equal(parseUnits("201", 18));
  });
});
