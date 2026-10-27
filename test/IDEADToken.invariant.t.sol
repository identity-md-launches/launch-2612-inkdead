// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {IDEADToken} from "../src/IDEADToken.sol";

contract InvariantDeployer {
    function deploy() external returns (IDEADToken) {
        return new IDEADToken();
    }
}

/// @notice Drives the token with bounded inputs from a fixed set of actors (the deployer among them)
/// and keeps an independent ledger of what every balance and allowance must be. Failure paths are
/// exercised too: each must revert with its exact error and leave the ledger and the token equal.
/// Any unexpected outcome reverts the handler, which the invariant runner reports (fail_on_revert).
contract IDEADHandler is TestBase {
    IDEADToken public immutable token;
    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public calls;
    uint256 public okTransfers;
    uint256 public okPulls;
    uint256 public expectedReverts;

    constructor(IDEADToken token_, address[] memory actors_, uint256[] memory balances_) {
        token = token_;
        for (uint256 i; i < actors_.length; ++i) {
            actors.push(actors_[i]);
            ghostBalance[actors_[i]] = balances_[i];
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Biases fuzzed amounts towards 0, 1, the cap and the cap minus one.
    function _amount(uint256 seed, uint256 cap) internal pure returns (uint256) {
        uint256 pick = seed % 8;
        if (pick == 0) return 0;
        if (pick == 1) return cap == 0 ? 0 : 1;
        if (pick == 2) return cap;
        if (pick == 3) return cap == 0 ? 0 : cap - 1;
        return bound(seed, 0, cap);
    }

    function _expectRevertData(bytes memory data, bytes memory expected, string memory what) internal pure {
        if (keccak256(data) != keccak256(expected)) revert(string.concat("wrong revert: ", what));
    }

    // ---------------------------------------------------------------------------------------------
    // Success paths
    // ---------------------------------------------------------------------------------------------

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[from]);
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ++okTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) external {
        ++calls;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (value % 5 == 0) value = type(uint256).max;
        else if (value % 5 == 1) value = bound(value, 0, ghostBalance[owner]);
        vm.prank(owner);
        assertTrue(token.approve(spender, value), "approve returned false");
        ghostAllowance[owner][spender] = value;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        uint256 amount = _amount(amountSeed, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount), "transferFrom returned false");
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ++okPulls;
    }

    // ---------------------------------------------------------------------------------------------
    // Failure paths
    // ---------------------------------------------------------------------------------------------

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        ++calls;
        address from = _actor(fromSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + bound(excessSeed, 1, type(uint256).max - held);
        vm.prank(from);
        try token.transfer(_actor(toSeed), amount) {
            revert("transfer above balance succeeded");
        } catch (bytes memory data) {
            _expectRevertData(
                data,
                abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, from, held, amount),
                "transfer above balance"
            );
        }
        ++expectedReverts;
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        ++calls;
        address from = _actor(fromSeed);
        vm.prank(from);
        try token.transfer(address(0), _amount(amountSeed, ghostBalance[from])) {
            revert("transfer to zero succeeded");
        } catch (bytes memory data) {
            _expectRevertData(
                data, abi.encodeWithSelector(IDEADToken.ERC20InvalidReceiver.selector, address(0)), "to zero"
            );
        }
        ++expectedReverts;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 value) external {
        ++calls;
        vm.prank(_actor(ownerSeed));
        try token.approve(address(0), value) {
            revert("approve zero spender succeeded");
        } catch (bytes memory data) {
            _expectRevertData(
                data, abi.encodeWithSelector(IDEADToken.ERC20InvalidSpender.selector, address(0)), "zero spender"
            );
        }
        ++expectedReverts;
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + bound(excessSeed, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(from, _actor(toSeed), amount) {
            revert("transferFrom above allowance succeeded");
        } catch (bytes memory data) {
            _expectRevertData(
                data,
                abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, spender, allowed, amount),
                "above allowance"
            );
        }
        ++expectedReverts;
    }

    /// @dev Allowance covers the amount but the balance does not.
    function transferFromAboveBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 held = ghostBalance[from];
        if (allowed <= held) return;
        uint256 amount = held + bound(excessSeed, 1, allowed - held);
        vm.prank(spender);
        try token.transferFrom(from, _actor(toSeed), amount) {
            revert("transferFrom above balance succeeded");
        } catch (bytes memory data) {
            _expectRevertData(
                data,
                abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, from, held, amount),
                "above balance"
            );
        }
        ++expectedReverts;
    }

    /// @dev Calls the launch floor's privileged selectors from a random actor; every one must fail.
    function privilegedCall(uint256 actorSeed, uint256 which, uint256 arg) external {
        ++calls;
        string[8] memory signatures = [
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "seize(address)",
            "transferOwnership(address)",
            "freeze(address)"
        ];
        bytes memory data = abi.encodeWithSignature(signatures[which % 8], _actor(arg), arg);
        vm.prank(_actor(actorSeed));
        (bool ok,) = address(token).call(data);
        assertTrue(!ok, string.concat("privileged call succeeded: ", signatures[which % 8]));
        ++expectedReverts;
    }
}

/// @notice Invariants over random call sequences: the supply is fixed, the balances always sum to it,
/// and the token agrees with the independent ledger after every call.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail_on_revert = true
contract IDEADTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    IDEADToken internal token;
    IDEADHandler internal handler;
    address internal deployer;
    address[] internal actors;

    function setUp() public {
        InvariantDeployer d = new InvariantDeployer();
        token = d.deploy();
        deployer = address(d);

        actors.push(deployer);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD00D));

        // Spread some of the supply, keep one actor empty so empty-account paths are reached.
        uint256[] memory balances = new uint256[](actors.length);
        balances[1] = SUPPLY / 10;
        balances[2] = 1;
        balances[3] = 0;
        balances[4] = SUPPLY / 3;
        vm.startPrank(deployer);
        for (uint256 i = 1; i < actors.length; ++i) {
            if (balances[i] > 0) token.transfer(actors[i], balances[i]);
        }
        vm.stopPrank();
        balances[0] = token.balanceOf(deployer);

        handler = new IDEADHandler(token, actors, balances);
    }

    /// @dev Restricts the invariant runner to the handler (read by forge, as forge-std's StdInvariant does).
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "actor balances do not sum to the supply");
    }

    function invariant_balancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance differs from ledger");
        }
    }

    function invariant_allowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance differs from ledger"
                );
            }
        }
    }

    function invariant_nothingLeaksOutsideActors() public view {
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
        assertEq(token.balanceOf(address(token)), 0, "token holds itself");
        assertEq(token.balanceOf(address(handler)), 0, "handler holds tokens");
        assertEq(token.balanceOf(address(this)), 0, "test holds tokens");
    }
}
