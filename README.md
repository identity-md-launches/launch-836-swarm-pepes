# Swarm Pepes (SWARMPEPES)

A fixed-supply ERC-20 using vendored OpenZeppelin Contracts v5.0.2. The only
custom logic is the constructor mint in `src/SwarmPepes.sol`.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Contract identifier | `src/SwarmPepes.sol:SwarmPepes` |
| Name | `Swarm Pepes` |
| Symbol | `SWARMPEPES` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Minor-unit supply | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; ABI encoding `0x`) |
| Deployment value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Application contracts | None |

The full supply is minted once, with one `Transfer` event from the zero address.
A direct deployment credits the deploying account. A factory deployment credits
the factory itself, including through CREATE2; it does not credit `tx.origin`
or the account that called the factory. No initializer or post-deployment token
configuration is needed. Creation bytecode is available in
`out/SwarmPepes.sol/SwarmPepes.json` after building, or with
`forge inspect src/SwarmPepes.sol:SwarmPepes bytecode`.

## Behavior and assumptions

- Transfers move the exact amount, with no fees, burns, rebasing, limits, or
  address exemptions. Zero-value transfers and self-transfers are supported.
- Transfers to the zero address revert. Insufficient balances or allowances
  revert atomically; a failed `transferFrom` also preserves the allowance.
- `approve` replaces the existing allowance and emits `Approval`. Finite
  allowances decrease on `transferFrom`; `type(uint256).max` remains unchanged.
  This OpenZeppelin version does not emit `Approval` when spending an allowance.
- No owner, pause, blacklist, seizure, public mint/burn, upgrade, permit, or
  recovery functions exist. The deployer has no power over other holders.
- Token operations make no external calls or recipient callbacks. They use no
  oracle, randomness, time, chain addresses, or offchain service.

The task is interpreted as a conventional transferable ERC-20. The token does
not itself allocate the supply, create a market, or enforce launch economics.
For an IdentityMD launch, the external factory is responsible for the 10% swarm
allocation, liquidity, and forwarding the remainder. Exact transfer behavior
supports those flows. Pair currency, network, factory and pool addresses, price,
pool allocation, and remainder recipient belong to that launch configuration;
none were specified here or hardcoded. No launch manifest is supplied.

## Build and verification

With Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization at 200
runs, and `bytecode_hash = "none"`. Deployment requires a chain that supports
the compiled EVM target. FFI and filesystem cheatcode permissions are disabled.
Every source dependency and its license is vendored as ordinary files in `lib/`;
no dependency download is required. An offline verifier only needs its provided
compiler and Foundry. Tests use a small local cheatcode interface and never read
or modify the environment, fork a chain, or require a wallet or RPC.

The suite covers metadata, single mint event, direct and CREATE2 factory
deployment, exact token-side launch transfers, transfer/approval events, zero
and full amounts, self-transfers, delegated transfers, revocation, unlimited
allowances, invalid addresses, insufficient balances/allowances, rollback,
unavailable admin/mint/burn calls, and forbidden runtime opcodes. Four fuzz tests
include a 32-operation transfer/approval sequence checked against an independent
balance model after every step (256 cases each by default).

The supplied protected test was read as an acceptance reference. Its full
Uniswap v4 launch harness needs network-owned factory libraries, manifest data,
and environment configuration outside this token project. The local factory
test checks token behavior; it does not claim to execute that integration or
perform a real swap.

## Operational responsibilities

The deployment operator must use the pinned build settings, verify the deployed
source and metadata, confirm the entire `10^27` supply first belongs to the
actual deploying account/factory, and validate the external launch configuration
and distribution. No deployment or transaction broadcasting is performed here.

Holders control transfers and approvals. Wallets should use allowances limited
to their intended spend and account for the standard ERC-20 approval replacement
race (revoke and confirm before granting a replacement). Lost keys or tokens sent
to an unrecoverable address cannot be rescued. Ordinary native-currency deposits
revert; forcibly received native currency and other tokens sent to this token
contract have no recovery mechanism. There are no token maintenance, privileged
key, upgrade, or emergency-pause duties.

Local tests and a source review are not an independent security audit. An
independent adversarial review and the network's complete launch integration
checks remain release responsibilities. Slither and Mythril were not run.
