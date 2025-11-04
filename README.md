# Self Fee Hook for Uniswap v4

**A Uniswap v4 hook that provides discounted trading fees for users who verify their identity using Self.xyz 🦄**

### Overview

`SelfFeeHook` is a dynamic fee hook that rewards users with **70% fee reduction** when they present a valid Self identity verification proof during swaps. This hook integrates with [Self.xyz](https://self.xyz) to enable privacy-preserving identity verification without revealing personal information.

### Key Features

- **Identity-Based Fee Discounts**: Users with valid Self proofs receive 0.3% fee instead of the standard 1%
- **Privacy-Preserving**: Uses zero-knowledge proofs - no personal data is stored on-chain
- **Non-Blocking**: Swaps always execute even if verification fails - users simply pay the standard fee
- **Dynamic Fee Pools Only**: Requires pools configured with dynamic fees (`fee = 0x800000`)

---

# Uniswap v4 Hook Template

**A template for writing Uniswap v4 Hooks 🦄**

### Get Started

This template provides a starting point for writing Uniswap v4 Hooks, including a simple example and preconfigured test environment. Start by creating a new repository using the "Use this template" button at the top right of this page. Alternatively you can also click this link:

[![Use this Template](https://img.shields.io/badge/Use%20this%20Template-101010?style=for-the-badge&logo=github)](https://github.com/uniswapfoundation/v4-template/generate)

1. The example hook [Counter.sol](src/Counter.sol) demonstrates the `beforeSwap()` and `afterSwap()` hooks
2. The test template [Counter.t.sol](test/Counter.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.
3. The [SelfFeeHook.sol](src/SelfFeeHook.sol) demonstrates identity-based dynamic fee adjustments using Self.xyz verification

<details>
<summary>Updating to v4-template:latest</summary>

This template is actively maintained -- you can update the v4 dependencies, scripts, and helpers:

```bash
git remote add template https://github.com/uniswapfoundation/v4-template
git fetch template
git merge template/main <BRANCH> --allow-unrelated-histories
```

</details>

### Requirements

This template is designed to work with Foundry (stable). If you are using Foundry Nightly, you may encounter compatibility issues. You can update your Foundry installation to the latest stable version by running:

```
foundryup
```

To set up the project, run the following commands in your terminal to install dependencies and run the tests:

```
forge install
forge test
```

### Local Development

Other than writing unit tests (recommended!), you can only deploy & test hooks on [anvil](https://book.getfoundry.sh/anvil/) locally. Scripts are available in the `script/` directory, which can be used to deploy hooks, create pools, provide liquidity and swap tokens. The scripts support both local `anvil` environment as well as running them directly on a production network.

### Executing locally with using **Anvil**:

1. Start Anvil (or fork a specific chain using anvil):

```bash
anvil
```

or

```bash
anvil --fork-url <YOUR_RPC_URL>
```

2. Execute scripts:

```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key <PRIVATE_KEY> \
    --broadcast
```

### Using **RPC URLs** (actual transactions):

:::info
It is best to not store your private key even in .env or enter it directly in the command line. Instead use the `--account` flag to select your private key from your keystore.
:::

### Follow these steps if you have not stored your private key in the keystore:

<details>

1. Add your private key to the keystore:

```bash
cast wallet import <SET_A_NAME_FOR_KEY> --interactive
```

2. You will prompted to enter your private key and set a password, fill and press enter:

```
Enter private key: <YOUR_PRIVATE_KEY>
Enter keystore password: <SET_NEW_PASSWORD>
```

You should see this:

```
`<YOUR_WALLET_PRIVATE_KEY_NAME>` keystore was saved successfully. Address: <YOUR_WALLET_ADDRESS>
```

::: warning
Use `history -c` to clear your command history.
:::

</details>

1. Execute scripts:

```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url <YOUR_RPC_URL> \
    --account <YOUR_WALLET_PRIVATE_KEY_NAME> \
    --sender <YOUR_WALLET_ADDRESS> \
    --broadcast
```

You will prompted to enter your wallet password, fill and press enter:

```
Enter keystore password: <YOUR_PASSWORD>
```

### Key Modifications to note:

1. Update the `token0` and `token1` addresses in the `BaseScript.sol` file to match the tokens you want to use in the network of your choice for sepolia and mainnet deployments.
2. Update the `token0Amount` and `token1Amount` in the `CreatePoolAndAddLiquidity.s.sol` file to match the amount of tokens you want to provide liquidity with.
3. Update the `token0Amount` and `token1Amount` in the `AddLiquidity.s.sol` file to match the amount of tokens you want to provide liquidity with.
4. Update the `amountIn` and `amountOutMin` in the `Swap.s.sol` file to match the amount of tokens you want to swap.

### Verifying the hook contract

```bash
forge verify-contract \
  --rpc-url <URL> \
  --chain <CHAIN_NAME_OR_ID> \
  # Generally etherscan
  --verifier <Verification_Provider> \
  # Use --etherscan-api-key <ETHERSCAN_API_KEY> if you are using etherscan
  --verifier-api-key <Verification_Provider_API_KEY> \
  --constructor-args <ABI_ENCODED_ARGS> \
  --num-of-optimizations <OPTIMIZER_RUNS> \
  <Contract_Address> \
  <path/to/Contract.sol:ContractName>
  --watch
```

### Troubleshooting

<details>

#### Permission Denied

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh)

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

#### Anvil fork test failures

Some versions of Foundry may limit contract code size to ~25kb, which could prevent local tests to fail. You can resolve this by setting the `code-size-limit` flag

```
anvil --code-size-limit 40000
```

#### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
   - `getHookCalls()` returns the correct flags
   - `flags` provided to `HookMiner.find(...)`
2. Verify salt mining is correct:
   - In **forge test**: the _deployer_ for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
   - In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
     - If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

</details>

### SelfFeeHook Documentation

#### How It Works

The `SelfFeeHook` operates on **dynamic fee pools** in Uniswap v4. When a user performs a swap:

1. **Without Self Proof**: The hook applies the **base fee of 1%** (10,000 basis points)
2. **With Valid Self Proof**: The hook verifies the identity proof and applies a **discounted fee of 0.3%** (3,000 basis points) - a **70% discount**

The verification happens synchronously during the swap execution. If verification fails or no proof is provided, the swap still executes successfully with the base fee.

#### Pool Requirements

**Important**: This hook **only works with dynamic fee pools**. When creating a pool that uses `SelfFeeHook`, you must set the pool's fee to the dynamic fee flag:

```solidity
PoolKey memory key = PoolKey({
    currency0: token0,
    currency1: token1,
    fee: 0x800000,  // DYNAMIC_FEE_FLAG - required for dynamic fee hooks
    tickSpacing: 60,
    hooks: IHooks(address(selfFeeHook))
});
```

#### Self.xyz Integration

The hook integrates with [Self.xyz](https://self.xyz) identity verification infrastructure:

- **Self Verification Hub V2**: Handles zero-knowledge proof verification
- **Privacy-Preserving**: Uses zk-proofs - no personal information is stored on-chain
- **User Context Data**: Users provide proof data encoded as `abi.encode(proofPayload, userContextData)`

#### Usage Flow

1. User obtains Self identity verification proof (typically via QR code scan)
2. Frontend encodes the proof data into the swap's `hookData` parameter
3. Swap is executed with the proof data
4. Hook verifies the proof synchronously during swap execution
5. If valid, discount is applied; if invalid or missing, base fee is charged

#### Fee Structure

| User Status | Fee Applied | Basis Points |
|------------|------------|--------------|
| No proof / Invalid proof | Base fee | 10,000 (1.0%) |
| Valid Self proof | Discount fee | 3,000 (0.3%) |

**Discount**: 70% reduction for verified users

#### Hook Data Format

When executing a swap with Self verification, encode the proof data as follows:

```solidity
bytes memory hookData = abi.encode(proofPayload, userContextData);
```

Where:
- `proofPayload`: `bytes32 attestationId || proof data` (32 bytes attestationId + encoded proof)
- `userContextData`: `bytes32 destChainId || bytes32 userIdentifier || additional data` (minimum 64 bytes)

#### Events

The hook emits `HookSwapMetrics` events for each swap containing:
- Pool identifier
- Verification status (true/false)
- Applied fee (basis points)
- Notional swap amount
- Calculated fee amount
- Block timestamp

This enables off-chain analytics and fee tracking for verified vs unverified swaps.

#### Gas Considerations

- Swaps without proof: Standard swap gas costs
- Swaps with proof: Additional gas for verification (~50k-100k gas depending on proof complexity)
- No persistent storage: The hook uses temporary flags to avoid gas overhead from state updates

#### Security Notes

- The hook never reverts swaps due to verification failures
- Each swap's verification is independent and atomic
- No user data is permanently stored on-chain
- Verification uses Self's battle-tested zk-proof infrastructure

### Additional Resources

- [Uniswap v4 docs](https://docs.uniswap.org/contracts/v4/overview)
- [Self.xyz Documentation](https://docs.self.xyz)
- [v4-periphery](https://github.com/uniswap/v4-periphery)
- [v4-core](https://github.com/uniswap/v4-core)
- [v4-by-example](https://v4-by-example.org)
