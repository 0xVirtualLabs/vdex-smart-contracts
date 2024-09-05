# Solidity API

## Lock

### unlockTime

```solidity
uint256 unlockTime
```

### owner

```solidity
address payable owner
```

### Withdrawal

```solidity
event Withdrawal(uint256 amount, uint256 when)
```

### constructor

```solidity
constructor(uint256 _unlockTime) public payable
```

### withdraw

```solidity
function withdraw() public
```

## DexSupporter

This contract is responsible for supporting the 0xVault contract.
It handles dispute resolution, partial liquidation, and other functions related to the 0xVault.

### InvalidSchnorrSignature

```solidity
error InvalidSchnorrSignature()
```

### vault

```solidity
contract IVault vault
```

The 0xVault contract.

### supraVerifier

```solidity
address supraVerifier
```

The SupraVerifier contract.

### supraStorageOracle

```solidity
address supraStorageOracle
```

The SupraStorageOracle contract.

### lpProvider

```solidity
address lpProvider
```

The LpProvider contract.

### ONE

```solidity
uint256 ONE
```

Constant value for 10^18.

### constructor

```solidity
constructor(address _vault, address _supraVerifier, address _supraStorageOracle, address _lpProvider) public
```

Constructor for the DexSupporter contract.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | The address of the 0xVault contract. |
| _supraVerifier | address | The address of the SupraVerifier contract. |
| _supraStorageOracle | address | The address of the SupraStorageOracle contract. |
| _lpProvider | address | The address of the LpProvider contract. |

### challengeLiquidatedPosition

```solidity
function challengeLiquidatedPosition(uint32 requestId, struct Crypto.LiquidatedPosition[] positions) external
```

Challenges a liquidated position.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The ID of the dispute. |
| positions | struct Crypto.LiquidatedPosition[] | The liquidated positions. |

### settleDispute

```solidity
function settleDispute(uint32 requestId) external
```

Settles a dispute.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The ID of the dispute. |

### liquidatePartially

```solidity
function liquidatePartially(address user, struct Crypto.SchnorrSignature _schnorr) external
```

Liquidates a user's position partially.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user. |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature. |

### setVault

```solidity
function setVault(address _vault) external
```

Sets the 0xVault contract.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | The address of the 0xVault contract. |

## LpProvider

_A contract for managing liquidity provision and fund management
This contract allows LP providers to deposit funds, request withdrawals,
and manage liquidity for different tokens._

### NAV_DECIMALS

```solidity
uint256 NAV_DECIMALS
```

### vault

```solidity
address vault
```

### coldWallet

```solidity
address coldWallet
```

### oracle

```solidity
address oracle
```

### startEpochTimestamp

```solidity
uint256 startEpochTimestamp
```

### epochPeriod

```solidity
uint256 epochPeriod
```

### withdrawalDelayTime

```solidity
uint256 withdrawalDelayTime
```

### pairId

```solidity
mapping(address => uint256) pairId
```

### isLPProvider

```solidity
mapping(address => bool) isLPProvider
```

### lpProvidedAmount

```solidity
mapping(address => uint256) lpProvidedAmount
```

### fundAmount

```solidity
mapping(address => uint256) fundAmount
```

### totalNAVs

```solidity
mapping(address => uint256) totalNAVs
```

### userNAVs

```solidity
mapping(address => mapping(address => uint256)) userNAVs
```

### reqWithdraws

```solidity
mapping(address => mapping(address => struct LpProvider.ReqWithdraw)) reqWithdraws
```

### claimableAmount

```solidity
mapping(address => mapping(address => uint256)) claimableAmount
```

### navPrice

```solidity
uint256 navPrice
```

### ReqWithdraw

```solidity
struct ReqWithdraw {
  uint256 navAmount;
  uint256 timestamp;
}
```

### LPProvided

```solidity
event LPProvided(address user, address token, uint256 amount)
```

### LPWithdrawn

```solidity
event LPWithdrawn(address user, address token, uint256 amount)
```

### DepositFund

```solidity
event DepositFund(address user, address token, uint256 amount, uint256 fundAmount)
```

### WithdrawFund

```solidity
event WithdrawFund(address user, address token, uint256 amount, uint256 fundAmount)
```

### WithdrawRequested

```solidity
event WithdrawRequested(address user, address token, uint256 navAmount, uint256 timestamp)
```

### LPProviderStatusChanged

```solidity
event LPProviderStatusChanged(address lpProvider, bool isProvider)
```

### VaultChanged

```solidity
event VaultChanged(address newVault)
```

### ColdWalletChanged

```solidity
event ColdWalletChanged(address newColdWallet)
```

### OracleChanged

```solidity
event OracleChanged(address newOracle)
```

### EpochParametersChanged

```solidity
event EpochParametersChanged(uint256 newStartEpochTimestamp, uint256 newEpochPeriod)
```

### WithdrawalDelayTimeChanged

```solidity
event WithdrawalDelayTimeChanged(uint256 newWithdrawalDelayTime)
```

### RewardDepositedForMarketMaker

```solidity
event RewardDepositedForMarketMaker(address token, uint256 amount)
```

### NAVPriceUpdated

```solidity
event NAVPriceUpdated(uint256 newPrice)
```

### onlyVault

```solidity
modifier onlyVault()
```

### initialize

```solidity
function initialize(address _owner, address _vault, address _oracle, uint256 _epochPeriod, uint256 _startEpochTimestamp, uint256 _withdrawalDelayTime, address _coldWallet) public
```

### depositFund

```solidity
function depositFund(address token, uint256 amount) external
```

_Allows LP providers to deposit funds_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to deposit |
| amount | uint256 | The amount of tokens to deposit |

### requestWithdrawFund

```solidity
function requestWithdrawFund(address token, uint256 navsAmount) external
```

_Allows LP providers to request a withdrawal_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to withdraw |
| navsAmount | uint256 | The amount of NAVs to withdraw |

### withdrawFund

```solidity
function withdrawFund(address token) external
```

_Allows LP providers to withdraw funds after the delay period_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to withdraw |

### provideLiquidity

```solidity
function provideLiquidity(address token, uint256 amount) external
```

_Allows LP providers to provide liquidity_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to provide liquidity for |
| amount | uint256 | The amount of tokens to provide as liquidity |

### withdrawAllLiquidity

```solidity
function withdrawAllLiquidity(address token) external
```

_Allows LP providers to withdraw all their provided liquidity_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to withdraw liquidity from |

### increaseLpProvidedAmount

```solidity
function increaseLpProvidedAmount(address token, uint256 amount) external
```

_Increases the LP provided amount (can only be called by the vault)_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token |
| amount | uint256 | The amount to increase |

### decreaseLpProvidedAmount

```solidity
function decreaseLpProvidedAmount(address user, address token, uint256 amount) external
```

_Decreases the LP provided amount (can only be called by the vault)_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address |  |
| token | address | The address of the token |
| amount | uint256 | The amount to decrease |

### claimProfit

```solidity
function claimProfit(address token, uint256 amount) external
```

_Allows the vault to claim profits for a specific token_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token |
| amount | uint256 | The amount of tokens to claim as profit |

### setLPProvider

```solidity
function setLPProvider(address[] lpProvider, bool[] isProvider) external
```

_Sets the LP provider status for multiple addresses_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| lpProvider | address[] | Array of LP provider addresses |
| isProvider | bool[] | Array of boolean values indicating LP provider status |

### setNAVPrice

```solidity
function setNAVPrice(uint256 newPrice) external
```

_Updates the NAV price for a token_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newPrice | uint256 | The new NAV price |

### setVault

```solidity
function setVault(address _vault) external
```

_Sets the vault address_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | The new vault address |

### setColdWallet

```solidity
function setColdWallet(address _coldWallet) external
```

_Sets the cold wallet address_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _coldWallet | address | The new cold wallet address |

### setOracle

```solidity
function setOracle(address _oracle) external
```

_Sets the oracle address_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _oracle | address | The new oracle address |

### setPairIDForTokens

```solidity
function setPairIDForTokens(address[] tokens, uint256[] ids) external
```

_Sets the pair ID for tokens_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Array of token addresses |
| ids | uint256[] | Array of corresponding pair IDs |

### setEpochParameters

```solidity
function setEpochParameters(uint256 _startEpochTimestamp, uint256 _epochPeriod) external
```

_Sets the epoch parameters_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _startEpochTimestamp | uint256 | The new start epoch timestamp |
| _epochPeriod | uint256 | The new epoch period |

### setWithdrawalDelayTime

```solidity
function setWithdrawalDelayTime(uint256 _withdrawalDelayTime) external
```

_Sets the withdrawal delay time_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _withdrawalDelayTime | uint256 | The new withdrawal delay time |

### depositRewardForMarketMaker

```solidity
function depositRewardForMarketMaker(address token, uint256 amount) external
```

_Deposits rewards for market makers_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to deposit |
| amount | uint256 | The amount of tokens to deposit |

## Vault

_A contract for managing user funds and positions
This contract allows users to deposit and withdraw funds, open and close positions,
and manage their trades._

### signatureExpiryTime

```solidity
uint256 signatureExpiryTime
```

_Public variable to store the signature expiry time._

### _disputes

```solidity
mapping(uint32 => struct Vault.Dispute) _disputes
```

_Public mapping to store disputes based on their IDs._

### combinedPublicKey

```solidity
mapping(address => address) combinedPublicKey
```

_Public mapping to store combined public keys._

### isTokenSupported

```solidity
mapping(address => bool) isTokenSupported
```

_Public mapping to check if a token is supported._

### ONE

```solidity
uint256 ONE
```

_Constant representing the value 1e9._

### depositedAmount

```solidity
mapping(address => mapping(address => uint256)) depositedAmount
```

_Public mapping to store deposited amounts for LP._

### lpProvider

```solidity
address lpProvider
```

_Public variable to store the LP provider address._

### dexSupporter

```solidity
address dexSupporter
```

_Public variable to store the DEX supporter address._

### TokenBalance

_Struct to represent token balances._

```solidity
struct TokenBalance {
  address token;
  uint256 balance;
}
```

### Deposited

```solidity
event Deposited(address user, address token, uint256 amount)
```

### Withdrawn

```solidity
event Withdrawn(address user, address token, uint256 amount)
```

### WithdrawalRequested

```solidity
event WithdrawalRequested(address user, address token, uint256 amount, uint32 requestId)
```

### TokenAdded

```solidity
event TokenAdded(address token)
```

### TokenRemoved

```solidity
event TokenRemoved(address token)
```

### LPProvided

```solidity
event LPProvided(address user, address token, uint256 amount)
```

### LPWithdrawn

```solidity
event LPWithdrawn(address user, address token, uint256 amount)
```

### PartialLiquidation

```solidity
event PartialLiquidation(address user, address token, uint256 amount)
```

### InvalidSignature

```solidity
error InvalidSignature()
```

### InvalidUsedSignature

```solidity
error InvalidUsedSignature()
```

### InvalidSchnorrSignature

```solidity
error InvalidSchnorrSignature()
```

### InvalidSP

```solidity
error InvalidSP()
```

### ECRecoverFailed

```solidity
error ECRecoverFailed()
```

### InvalidAddress

```solidity
error InvalidAddress()
```

### DisputeChallengeFailed

```solidity
error DisputeChallengeFailed()
```

### SettleDisputeFailed

```solidity
error SettleDisputeFailed()
```

### DataNotVerified

```solidity
error DataNotVerified()
```

### WithdrawParams

```solidity
struct WithdrawParams {
  address trader;
  address token;
  uint256 amount;
  uint64 timestamp;
}
```

### OraclePrice

```solidity
struct OraclePrice {
  string positionId;
  address token;
  uint256 price;
  uint64 timestamp;
}
```

### DisputeStatus

```solidity
enum DisputeStatus {
  None,
  Opened,
  Challenged,
  Settled
}
```

### Dispute

```solidity
struct Dispute {
  address user;
  address challenger;
  uint64 timestamp;
  struct Crypto.Balance[] balances;
  struct Crypto.Position[] positions;
  uint8 status;
  uint32 sessionId;
}
```

### ClosePositionDispute

```solidity
struct ClosePositionDispute {
  address user;
  address challenger;
  uint64 timestamp;
  struct Crypto.Position[] positions;
  uint8 status;
  uint32 sessionId;
}
```

### DisputeOpened

```solidity
event DisputeOpened(uint32 requestId, address user)
```

### DisputeChallenged

```solidity
event DisputeChallenged(uint32 requestId, address user)
```

### PositionDisputeChallenged

```solidity
event PositionDisputeChallenged(uint32 requestId, address user)
```

### DisputeSettled

```solidity
event DisputeSettled(uint32 requestId, address user)
```

### initialize

```solidity
function initialize(address _owner, uint256 _signatureExpiryTime, address _lpProvider, address _dexSupporter) public
```

_Initialize the Vault contract._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _owner | address | The owner of the Vault contract. |
| _signatureExpiryTime | uint256 | The expiry time for signatures. |
| _lpProvider | address | The address of the LP provider. |
| _dexSupporter | address | The address of the DEX supporter. |

### deposit

```solidity
function deposit(address token, uint256 amount) external
```

_Deposit tokens into the Vault._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token to deposit. |
| amount | uint256 | The amount of tokens to deposit. |

### withdrawSchnorr

```solidity
function withdrawSchnorr(address _combinedPublicKey, struct Crypto.SchnorrSignature _schnorr) external
```

_Withdraw tokens from the Vault using a Schnorr signature._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _combinedPublicKey | address | The combined public key of the user. |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature. |

### setSupportedToken

```solidity
function setSupportedToken(address token, bool isSupported) external
```

_Set the supported status of a token._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token. |
| isSupported | bool | Whether the token is supported. |

### setSchnorrSignatureUsed

```solidity
function setSchnorrSignatureUsed(bytes signature) external
```

_Set the Schnorr signature as used._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| signature | bytes | The Schnorr signature. |

### isSchnorrSignatureUsed

```solidity
function isSchnorrSignatureUsed(bytes signature) external view returns (bool)
```

_Check if a Schnorr signature has been used._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| signature | bytes | The Schnorr signature. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Whether the signature has been used. |

### withdrawAndClosePositionTrustlessly

```solidity
function withdrawAndClosePositionTrustlessly(struct Crypto.SchnorrSignature _schnorr) external
```

_Withdraw tokens and close positions trustlessly using a Schnorr signature._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature. |

### challengeDispute

```solidity
function challengeDispute(uint32 requestId, struct Crypto.SchnorrSignature _schnorr) external
```

_Challenge a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature. |

### getDisputeStatus

```solidity
function getDisputeStatus(uint32 requestId) external view returns (bool isOpenDispute, uint64 timestamp, address user)
```

_Get the status of a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| isOpenDispute | bool | Whether the dispute is open. |
| timestamp | uint64 | The timestamp of the dispute. |
| user | address | The user who opened the dispute. |

### getDisputePositions

```solidity
function getDisputePositions(uint32 requestId) external view returns (struct Crypto.Position[])
```

_Get the positions of a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct Crypto.Position[] | The positions of the dispute. |

### getDisputeBalances

```solidity
function getDisputeBalances(uint32 requestId) external view returns (struct Crypto.Balance[])
```

_Get the balances of a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct Crypto.Balance[] | The balances of the dispute. |

### updateLiquidatedPositions

```solidity
function updateLiquidatedPositions(uint32 requestId, uint256[] liquidatedIndexes, uint256 liquidatedCount, bool isCrossLiquidated) external
```

_Update the liquidated positions of a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |
| liquidatedIndexes | uint256[] | The indexes of the liquidated positions. |
| liquidatedCount | uint256 | The number of liquidated positions. |
| isCrossLiquidated | bool | Whether the liquidation is cross-liquidated. |

### updatePartialLiquidation

```solidity
function updatePartialLiquidation(address user, address[] tokens, uint256[] losses, uint256 totalLossCount) external
```

_Update the partial liquidation of a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user. |
| tokens | address[] | The addresses of the tokens. |
| losses | uint256[] | The amounts of the losses. |
| totalLossCount | uint256 | The total number of losses. |

### settleDisputeResult

```solidity
function settleDisputeResult(uint32 requestId, uint256[] updatedBalances, uint256[] pnlValues, bool[] isProfits) external
```

_Settle the result of a dispute._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestId | uint32 | The request ID of the dispute. |
| updatedBalances | uint256[] | The updated balances of the user. |
| pnlValues | uint256[] | The PNL values of the user. |
| isProfits | bool[] | Whether the PNL values are profits. |

### setSignatureExpiryTime

```solidity
function setSignatureExpiryTime(uint256 _expiryTime) external
```

_Set the signature expiry time._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _expiryTime | uint256 | The new signature expiry time. |

### setDexSupporter

```solidity
function setDexSupporter(address _dexSupporter) external
```

_Set the DEX supporter address._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _dexSupporter | address | The new DEX supporter address. |

### setLpProvider

```solidity
function setLpProvider(address _lpProvider) external
```

_Set the LP provider address._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _lpProvider | address | The new LP provider address. |

### setCombinedPublicKey

```solidity
function setCombinedPublicKey(address _user, address _combinedPublicKey) external
```

_Set the combined public key of a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _user | address | The address of the user. |
| _combinedPublicKey | address | The combined public key of the user. |

## ILpProvider

### increaseLpProvidedAmount

```solidity
function increaseLpProvidedAmount(address token, uint256 amount) external
```

_Increases the amount of liquidity provided for a specific token._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | The address of the token for which liquidity is being increased. |
| amount | uint256 | The amount by which liquidity is being increased. |

### decreaseLpProvidedAmount

```solidity
function decreaseLpProvidedAmount(address user, address token, uint256 amount) external
```

_Decreases the amount of liquidity provided by a specific user for a specific token._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user whose liquidity is being decreased. |
| token | address | The address of the token for which liquidity is being decreased. |
| amount | uint256 | The amount by which liquidity is being decreased. |

## IOracle

_Interface for interacting with the Oracle contract._

### priceFeed

_Struct representing price feed data._

```solidity
struct priceFeed {
  uint256 round;
  uint256 decimals;
  uint256 time;
  uint256 price;
}
```

### getSvalue

```solidity
function getSvalue(uint256 pairIndex) external view returns (struct IOracle.priceFeed)
```

_Retrieves the price feed data for a specific pair index._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pairIndex | uint256 | The index of the pair to retrieve data for. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct IOracle.priceFeed | The price feed data for the specified pair index. |

## ISupraVerifier

_Interface for Supra Verifier contract_

### isPairAlreadyAddedForHCC

```solidity
function isPairAlreadyAddedForHCC(uint256[] _pairIndexes) external view returns (bool)
```

Checks if a pair is already added for HCC

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _pairIndexes | uint256[] | Array of pair indexes to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Whether the pair is already added |

### isPairAlreadyAddedForHCC

```solidity
function isPairAlreadyAddedForHCC(uint256 _pairId) external view returns (bool)
```

Checks if a pair is already added for HCC

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _pairId | uint256 | The pair ID to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Whether the pair is already added |

### requireHashVerified_V2

```solidity
function requireHashVerified_V2(bytes32 message, uint256[2] signature, uint256 committee_id) external view
```

Requires hash verification for version 2

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| message | bytes32 | The message hash to verify |
| signature | uint256[2] | The signature to verify |
| committee_id | uint256 | The committee ID |

### requireHashVerified_V1

```solidity
function requireHashVerified_V1(bytes message, uint256[2] signature) external view
```

Requires hash verification for version 1

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| message | bytes | The message to verify |
| signature | uint256[2] | The signature to verify |

## IVault

_Interface for interacting with the Vault contract._

### Dispute

_Struct representing a dispute in the Vault._

```solidity
struct Dispute {
  address user;
  address challenger;
  uint64 timestamp;
  struct Crypto.Balance[] balances;
  struct Crypto.Position[] positions;
  uint8 status;
  uint32 sessionId;
}
```

### isTokenSupported

```solidity
function isTokenSupported(address token) external view returns (bool)
```

_Checks if a token is supported by the Vault._

### updateLiquidatedPositions

```solidity
function updateLiquidatedPositions(uint32 requestId, uint256[] liquidatedIndexes, uint256 liquidatedCount, bool isCrossLiquidated) external
```

_Updates the positions that have been liquidated in the Vault._

### getDisputeStatus

```solidity
function getDisputeStatus(uint32 requestId) external view returns (bool isOpenDispute, uint64 timestamp, address user)
```

_Retrieves the status of a dispute in the Vault._

### getDisputePositions

```solidity
function getDisputePositions(uint32 requestId) external view returns (struct Crypto.Position[])
```

_Retrieves the positions involved in a dispute in the Vault._

### getDisputeBalances

```solidity
function getDisputeBalances(uint32 requestId) external view returns (struct Crypto.Balance[])
```

_Retrieves the balances involved in a dispute in the Vault._

### depositedAmount

```solidity
function depositedAmount(address user, address token) external view returns (uint256)
```

_Retrieves the amount deposited by a user for a specific token in the Vault._

### settleDisputeResult

```solidity
function settleDisputeResult(uint32 requestId, uint256[] updatedBalances, uint256[] pnlValues, bool[] isProfits) external
```

_Settles the result of a dispute in the Vault._

### combinedPublicKey

```solidity
function combinedPublicKey(address user) external view returns (address)
```

_Retrieves the combined public key of a user in the Vault._

### _disputes

```solidity
function _disputes(uint32 reqId) external view returns (struct IVault.Dispute)
```

_Retrieves a specific dispute in the Vault._

### updatePartialLiquidation

```solidity
function updatePartialLiquidation(address user, address[] tokens, uint256[] losses, uint256 totalLossCount) external
```

_Updates the partial liquidation of a user in the Vault._

### setSchnorrSignatureUsed

```solidity
function setSchnorrSignatureUsed(bytes signature) external
```

_Sets a Schnorr signature as used in the Vault._

### isSchnorrSignatureUsed

```solidity
function isSchnorrSignatureUsed(bytes signature) external view returns (bool)
```

_Checks if a Schnorr signature has been used in the Vault._

## Crypto

### InvalidSignature

```solidity
error InvalidSignature()
```

### InvalidUsedSignature

```solidity
error InvalidUsedSignature()
```

### InvalidSchnorrSignature

```solidity
error InvalidSchnorrSignature()
```

### InvalidSP

```solidity
error InvalidSP()
```

### ECRecoverFailed

```solidity
error ECRecoverFailed()
```

### InvalidAddress

```solidity
error InvalidAddress()
```

### DisputeChallengeFailed

```solidity
error DisputeChallengeFailed()
```

### SettleDisputeFailed

```solidity
error SettleDisputeFailed()
```

### TokenBalance

_Struct representing the balance of a token._

```solidity
struct TokenBalance {
  address token;
  uint256 balance;
}
```

### WithdrawTrustlesslyParams

_Struct representing parameters for trustless withdrawal._

```solidity
struct WithdrawTrustlesslyParams {
  struct Crypto.TokenBalance[] tokenBalances;
  uint64 timestamp;
  struct Crypto.SchnorrSignature schnorr;
}
```

### SchnorrSignature

_Struct representing a Schnorr signature._

```solidity
struct SchnorrSignature {
  bytes data;
  bytes signature;
  address combinedPublicKey;
}
```

### WithdrawParams

_Struct representing parameters for withdrawal._

```solidity
struct WithdrawParams {
  address trader;
  address token;
  uint256 amount;
  uint64 timestamp;
}
```

### SchnorrDataWithdraw

_Struct representing data for a Schnorr withdrawal._

```solidity
struct SchnorrDataWithdraw {
  address trader;
  address token;
  uint256 amount;
  uint64 timestamp;
}
```

### OraclePrice

_Struct representing the price of an asset in an Oracle._

```solidity
struct OraclePrice {
  uint256 positionId;
  address token;
  uint256 price;
  uint64 timestamp;
}
```

### Balance

_Struct representing a user's balance._

```solidity
struct Balance {
  uint256 oracleId;
  address addr;
  uint256 balance;
}
```

### Collateral

_Struct representing collateral for a position._

```solidity
struct Collateral {
  uint256 oracleId;
  address token;
  uint256 quantity;
  uint256 entryPrice;
}
```

### LiquidatedPosition

_Struct representing a liquidated position._

```solidity
struct LiquidatedPosition {
  string positionId;
  bytes proofBytes;
}
```

### UpdateDispute

_Struct representing an update to a dispute._

```solidity
struct UpdateDispute {
  uint32 disputeId;
}
```

### Position

_Struct representing a trading position._

```solidity
struct Position {
  string positionId;
  uint256 oracleId;
  address token;
  uint256 quantity;
  uint256 leverageFactor;
  string leverageType;
  bool isLong;
  struct Crypto.Collateral[] collaterals;
  uint256 entryPrice;
  uint256 createdTimestamp;
}
```

### SchnorrData

_Struct representing Schnorr signature data._

```solidity
struct SchnorrData {
  uint32 signatureId;
  address addr;
  struct Crypto.Balance[] balances;
  struct Crypto.Position[] positions;
  string sigType;
  uint256 timestamp;
}
```

### ClosePositionSchnorrData

_Struct representing Schnorr data for closing a position._

```solidity
struct ClosePositionSchnorrData {
  uint32 signatureId;
  address addr;
  struct Crypto.Position[] positions;
  string sigType;
  uint256 timestamp;
}
```

### DisputeStatus

_Enum representing the status of a dispute._

```solidity
enum DisputeStatus {
  None,
  Opened,
  Challenged,
  Settled
}
```

### Dispute

_Struct representing a dispute._

```solidity
struct Dispute {
  address user;
  address challenger;
  uint64 timestamp;
  struct Crypto.Balance[] balances;
  uint8 status;
  uint32 sessionId;
}
```

### ClosePositionDispute

_Struct representing a dispute for closing a position._

```solidity
struct ClosePositionDispute {
  address user;
  address challenger;
  uint64 timestamp;
  struct Crypto.Position[] positions;
  uint8 status;
  uint32 sessionId;
}
```

### decodeSchnorrData

```solidity
function decodeSchnorrData(struct Crypto.SchnorrSignature _schnorr) external pure returns (struct Crypto.SchnorrData)
```

_Decodes Schnorr data from a Schnorr signature._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature to decode. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct Crypto.SchnorrData | The decoded Schnorr data. |

### decodeSchnorrDataWithdraw

```solidity
function decodeSchnorrDataWithdraw(struct Crypto.SchnorrSignature _schnorr, address combinedPublicKey) external view returns (struct Crypto.SchnorrDataWithdraw)
```

_Decodes Schnorr data from a Schnorr signature for withdrawal._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature to decode. |
| combinedPublicKey | address | The combined public key to verify the signature. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct Crypto.SchnorrDataWithdraw | The decoded Schnorr data for withdrawal. |

### _verifySignature

```solidity
function _verifySignature(bytes32 _digest, bytes _signature, address _trustedSigner) external pure
```

_Verifies an ECDSA signature._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _digest | bytes32 | The digest to be signed. |
| _signature | bytes | The signature to be verified. |
| _trustedSigner | address | The address of the trusted signer. |

### _splitSignature

```solidity
function _splitSignature(bytes sig) public pure returns (bytes32 r, bytes32 s, uint8 v)
```

_Splits a signature into its components._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| sig | bytes | The signature to split. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| r | bytes32 | The R component of the signature. |
| s | bytes32 | The S component of the signature. |
| v | uint8 | The V component of the signature. |

### _verifySchnorrSignature

```solidity
function _verifySchnorrSignature(struct Crypto.SchnorrSignature _schnorr, address _combinedPublicKey) public view returns (bool)
```

_Verifies a Schnorr signature._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _schnorr | struct Crypto.SchnorrSignature | The Schnorr signature to verify. |
| _combinedPublicKey | address | The combined public key to verify the signature. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the signature is valid, otherwise false. |

## Dex

_Library for handling Dex operations_

### MAINTENANCE_MARGIN_PERCENT

```solidity
uint256 MAINTENANCE_MARGIN_PERCENT
```

_Constant for maintenance margin percentage_

### BACKSTOP_LIQUIDATION_PERCENT

```solidity
uint256 BACKSTOP_LIQUIDATION_PERCENT
```

_Constant for backstop liquidation percentage_

### _getPriceByPairId

```solidity
function _getPriceByPairId(struct SupraOracleDecoder.CommitteeFeed[] allFeeds, uint256 pair) public pure returns (uint128)
```

_Get the price by pair ID_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| allFeeds | struct SupraOracleDecoder.CommitteeFeed[] | Array of all feeds |
| pair | uint256 | Pair ID to retrieve price for |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint128 | Price of the pair |

### _getPositionLoss

```solidity
function _getPositionLoss(struct Crypto.Position position, struct SupraOracleDecoder.CommitteeFeed[] allFeeds) public pure returns (uint256)
```

_Calculate the position loss_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| position | struct Crypto.Position | Position data |
| allFeeds | struct SupraOracleDecoder.CommitteeFeed[] | Array of all feeds |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | Loss amount of the position |

### _checkLiquidatedPosition

```solidity
function _checkLiquidatedPosition(struct Crypto.Position position, struct SupraOracleDecoder.CommitteeFeed[] allFeeds, struct Crypto.Balance[] balances) public pure returns (bool)
```

_Check if a position is liquidated_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| position | struct Crypto.Position | Position data |
| allFeeds | struct SupraOracleDecoder.CommitteeFeed[] | Array of all feeds |
| balances | struct Crypto.Balance[] | Array of balances |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if position is liquidated, false otherwise |

## SupraOracleDecoder

_Library for decoding Oracle proofs in the Supra system._

### CommitteeFeed

_Struct representing a feed from a committee._

```solidity
struct CommitteeFeed {
  uint32 pair;
  uint128 price;
  uint64 timestamp;
  uint16 decimals;
  uint64 round;
}
```

### CommitteeFeedWithProof

_Struct representing a feed from a committee with proof._

```solidity
struct CommitteeFeedWithProof {
  struct SupraOracleDecoder.CommitteeFeed[] committee_feeds;
  bytes32[] proofs;
  bool[] flags;
}
```

### PriceDetailsWithCommittee

_Struct representing price details with committee information._

```solidity
struct PriceDetailsWithCommittee {
  uint64 committee_id;
  bytes32 root;
  uint256[2] sigs;
  struct SupraOracleDecoder.CommitteeFeedWithProof committee_data;
}
```

### OracleProofV2

_Struct representing an Oracle proof in version 2._

```solidity
struct OracleProofV2 {
  struct SupraOracleDecoder.PriceDetailsWithCommittee[] data;
}
```

### decodeOracleProof

```solidity
function decodeOracleProof(bytes _bytesProof) external pure returns (struct SupraOracleDecoder.OracleProofV2)
```

Decode the Oracle proof from bytes.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _bytesProof | bytes | The Oracle proof in bytes. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct SupraOracleDecoder.OracleProofV2 | Decoded Oracle proof in version 2. |

## MockOracle

### decimals

```solidity
uint256 decimals
```

### getPrice

```solidity
function getPrice(address token) external view returns (uint256)
```

