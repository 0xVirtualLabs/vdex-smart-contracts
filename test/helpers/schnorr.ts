import { secp256k1 } from "@noble/curves/secp256k1";
import {
  keccak256,
  encodeAbiParameters,
  encodePacked,
  toHex,
  pad,
  getAddress,
  concat,
  type Hex,
  type Address,
} from "viem";

// Reproduces the exact Schnorr-via-ecrecover scheme that
// `Crypto._verifySchnorrSignature` verifies on-chain:
//
//   sp = N - (s * px) mod N
//   ep = N - (e * px) mod N
//   R  = ecrecover(sp, parity, px, ep)          // == address(k*G)
//   valid iff  e == keccak256(R, parity, px, keccak256(data))
//         and  address(uint160(px)) == combinedPublicKey
//
// Signing (single key x, public point P = x*G with x-coord px):
//   choose nonce k, R = address(k*G)
//   e = keccak256(abi.encodePacked(R, parity, px, keccak256(data)))
//   s = (k + e*x) mod N
//
// parity follows the compressed-pubkey convention used by the backend
// (`SchnorrkelUtil`): prefix 0x02 (even y) -> 27, 0x03 (odd y) -> 28.

const N = secp256k1.CURVE.n;
const Point = secp256k1.ProjectivePoint;

const mod = (a: bigint, m: bigint = N): bigint => ((a % m) + m) % m;
const b32 = (v: bigint): Hex => pad(toHex(v), { size: 32 });

function pointAddress(x: bigint, y: bigint): Address {
  // address = last 20 bytes of keccak256(uncompressed pubkey x||y), 64 bytes
  return getAddress(("0x" + keccak256(concat([b32(x), b32(y)])).slice(-40)) as Hex);
}

export interface SchnorrSig {
  data: Hex;
  signature: Hex;
  combinedPublicKey: Address;
}

/**
 * Sign arbitrary already-encoded `data` bytes, producing a
 * `Crypto.SchnorrSignature` that `Crypto._verifySchnorrSignature` accepts.
 */
export function signSchnorr(privHex: string, data: Hex): SchnorrSig {
  const priv = privHex.startsWith("0x") ? privHex.slice(2) : privHex;
  const x = mod(BigInt("0x" + priv));
  if (x === 0n) throw new Error("invalid private key");

  const P = Point.BASE.multiply(x).toAffine();
  const px = P.x;
  if (px >= N) throw new Error("px >= N: pick another key (ecrecover would reject)");
  const parity = (P.y & 1n) === 0n ? 27 : 28;
  const pxB = b32(px);
  const combinedPublicKey = getAddress(("0x" + pxB.slice(-40)) as Hex);

  const msgHash = keccak256(data);

  // deterministic nonce derived from the key and message
  let k = mod(BigInt(keccak256(concat([b32(x), msgHash]))));
  if (k === 0n) k = 1n;
  const R = Point.BASE.multiply(k).toAffine();
  const Raddr = pointAddress(R.x, R.y);

  const e = keccak256(
    encodePacked(["address", "uint8", "bytes32", "bytes32"], [Raddr, parity, pxB, msgHash])
  );
  const s = mod(k + mod(BigInt(e)) * x);

  const signature = encodeAbiParameters(
    [{ type: "bytes32" }, { type: "bytes32" }, { type: "bytes32" }, { type: "uint8" }],
    [pxB, e, b32(s), parity]
  );

  return { data, signature, combinedPublicKey };
}

export interface WithdrawPayload {
  trader: Address;
  token: Address;
  amount: bigint;
  timestamp: bigint; // uint64
  chainId: bigint;
}

/**
 * Build a valid `Crypto.SchnorrSignature` for `withdrawSchnorr`, whose `data`
 * is `abi.encode(trader, token, amount, timestamp, chainId)`, exactly what
 * `Crypto.decodeSchnorrDataWithdraw` decodes.
 */
export function buildWithdrawSchnorr(privHex: string, p: WithdrawPayload): SchnorrSig {
  const data = encodeAbiParameters(
    [
      { type: "address" },
      { type: "address" },
      { type: "uint256" },
      { type: "uint64" },
      { type: "uint256" },
    ],
    [p.trader, p.token, p.amount, p.timestamp, p.chainId]
  );
  return signSchnorr(privHex, data);
}
