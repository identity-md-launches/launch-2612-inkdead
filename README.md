# InkDead (IDEAD)

A plain, fixed-supply ERC-20 for the IdentityMD custom-token launch on Ethereum mainnet.

| Parameter | Value |
| --- | --- |
| Solidity contract | `IDEADToken` (`src/IDEADToken.sol`) |
| `name()` | `InkDead` |
| `symbol()` | `IDEAD` |
| `decimals()` | `18` |
| `totalSupply()` | `1_000_000_000 * 10**18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |
| Compiler | solc `0.8.26`, optimizer on (200 runs), `evm_version = "cancun"`, `bytecode_hash = "none"` |

## What the token does

- Mints the whole supply (one billion tokens at 18 decimals) to the deployer in the constructor and
  emits the standard `Transfer(address(0), deployer, supply)` event.
- Implements ERC-20 with the metadata extension: `name`, `symbol`, `decimals`, `totalSupply`,
  `balanceOf`, `allowance`, `transfer`, `approve`, `transferFrom`, `Transfer`, `Approval`.
- Reverts with ERC-6093 custom errors: `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`,
  `ERC20InvalidReceiver`, `ERC20InvalidSender`, `ERC20InvalidApprover`, `ERC20InvalidSpender`.
- Treats an allowance of `type(uint256).max` as unlimited (it is never decremented), as
  OpenZeppelin v5 does.

## What the token does not do

There is deliberately nothing else. The brief asks for a token with a name, a symbol and a supply,
so the contract has:

- no owner, `Ownable`, roles or `transferOwnership`;
- no `mint`, `burn`, `burnFrom` or any path that changes `totalSupply` after construction
  (`totalSupply()` is a compile-time constant);
- no pause, blacklist, freeze, lock or seize;
- no transfer fee, tax, reflection or burn-on-transfer, so every launch flow (factory to
  distributor, distributor to claimant, factory to pool, pool to trader and back) moves exactly the
  amount stated;
- no `receive` or `fallback`, so ether sent to it reverts;
- no `delegatecall`, `callcode`, `selfdestruct`, proxies, initializers or external libraries;
- no external calls of any kind, including in the constructor, so it deploys on an empty chain.

## Launch parameters (for the manifest step)

These are the values the launch's manifest step needs. They are listed here and are **not** written
to a `launch.json` in this repository, as the launch process requires.

- `token.contract`: `IDEADToken`
- `token.name`: `InkDead`
- `token.symbol`: `IDEAD`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- `contracts`: `[]` (no application contracts)
- Chain: Ethereum, chain id `1`
- Pair: IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`
- `pool.fee`: `12500`, `pool.tickSpacing`: `60`, `pool.initialPrice`: `79228162514264337593543950336`
  (the deployer derives the real opening price from the economics)
- `economics`: `{"poolBps":8000,"initialMarketCapWei":"4299000000000000000000","remainderTo":"0x2587352d988530a97a8f8a1b15ad5bd14f32c94f"}`

Because the constructor mints to `msg.sender` and the factory deploys the token, the factory holds
the whole supply after construction and distributes it: 10% to the launch's MerkleDistributor, 80%
to the single-sided Uniswap v4 pool, and the remaining 10% to the `remainderTo` address above. The
token does not need to know the factory, the pool manager or the distributor, because it exempts
nothing: there is no fee to exempt from.

## After launch

There is nothing to configure. The contract has no owner-settable values and no owner.

## Assumptions

- The requester wants a standard ERC-20 and nothing more. Every feature the brief did not ask for
  (burn, tax, vesting, governance, permit) was left out rather than guessed at.
- "All minted once to the deployer" means `msg.sender` of the constructor. Under the launch that is
  the ProjectFactory, which is the intended holder of the supply before distribution. Deploying the
  contract directly from an EOA mints the supply to that EOA instead.
- One billion tokens means `1_000_000_000 * 10**18` minor units; both the constant and the
  manifest supply above use that figure.
- The project vendors no libraries. The ERC-20 and the test cheatcode interface are written out in
  the repository, so the offline verifier needs nothing it cannot find in the tree.

## Operational responsibilities

- **The token has no operator.** Nobody can pause it, recover tokens sent to it or to the wrong
  address, change the supply, or intervene in any transfer. Holders are responsible for their own
  keys and approvals; the usual advice applies (approve exact amounts, not unlimited ones).
- **The launch deployer (IMD)** compiles with the pinned `foundry.toml`, deploys through the
  factory, and performs the distribution and pool seeding. This repository does not deploy,
  broadcast or hold keys. It contains no deploy script because the token takes no configuration and
  the factory, not a script, performs the launch.
- **Explorer verification** of the deployed bytecode (with `forge verify-contract`, compiler
  `0.8.26`, optimizer 200 runs, `bytecode_hash = "none"`) is the deployer's task after launch.
- **Security review.** The tests here are behavioural checks, not an audit. The contract is small
  and holds no funds itself, but an independent adversarial review before release remains the
  policy for anything that other people's funds will pass through.

## Layout

```
foundry.toml              compiler pins and profile
src/IDEADToken.sol        the token
src/interfaces/IERC20.sol ERC-20 interface with metadata
test/utils/TestBase.sol   minimal Vm cheatcode interface and assertions (no forge-std)
test/IDEADToken.t.sol     success, failure and fuzz tests
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

The fuzz tests bound their own inputs and pass for any seed. To reproduce the verifier's run:

```
FOUNDRY_FUZZ_SEED=0x8acbbce6192ca122c804723a0450a01a793bdf7248fad1d22fb15cc6dd9425e6 forge test
```

The tests read no environment variables and do not depend on the caller's address, so they pass
in any order, in parallel and with an empty environment.

### What the tests cover

- Metadata and the one-time mint: name, symbol, decimals, supply, deployer balance, the mint
  event, and that whoever deploys receives the supply.
- `transfer`: balance movement and event, full-balance transfer, zero-amount transfer,
  self-transfer, insufficient balance, empty account, zero-address receiver.
- `approve` and `transferFrom`: allowance set and overwritten, event, spending decrements the
  allowance, unlimited allowance is not decremented, missing allowance, allowance exceeded,
  allowance above balance, zero-address receiver, and that the deployer cannot pull from a holder
  without an allowance.
- No privileged path: the launch floor's list of mint, ownership, upgrade, pause, blacklist,
  freeze, lock, seize and `burnFrom` selectors all revert whether a stranger or the deployer calls
  them, the supply never changes, and a holder keeps and can still move its balance. Ether sent to
  the contract reverts.
- Fuzz: supply conservation across transfers and chains of transfers, reverts above balance,
  `transferFrom` within and above the allowance.

## Security checklist applied

From the eth-security reference: no reentrancy surface (no external calls), checks before effects,
no `tx.origin`, no `selfdestruct`, no `delegatecall`, no proxies or initializers, no unchecked
arithmetic except where the preceding check or the constant supply makes overflow impossible, custom
errors rather than string reverts, events on every state change, and no owner power to document as
a trust assumption because there is none. Slither and Mythril were not run as part of this task;
the verifier runs Slither.
