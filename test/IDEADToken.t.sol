// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {IDEADToken} from "../src/IDEADToken.sol";

/// @notice Deploys the token from a separate account so the tests can tell "the deployer" apart
/// from "the test contract". The launch factory plays this role in production.
contract Deployer {
    function deploy() external returns (IDEADToken) {
        return new IDEADToken();
    }
}

/// @notice Behaviour of InkDead (IDEAD): metadata, the one-time mint, ERC-20 success and failure
/// paths, supply conservation, and the absence of any privileged path.
contract IDEADTokenTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    Deployer internal deployer;
    IDEADToken internal token;

    function setUp() public {
        deployer = new Deployer();
        token = deployer.deploy();
        vm.label(address(deployer), "deployer");
        vm.label(address(token), "IDEAD");
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and construction
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "InkDead", "name");
        assertEq(token.symbol(), "IDEAD", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY constant");
        assertEq(token.balanceOf(address(deployer)), SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(this)), 0, "test contract holds nothing");
    }

    function test_constructorEmitsMintTransfer() public {
        Deployer fresh = new Deployer();
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(fresh), SUPPLY);
        fresh.deploy();
    }

    function test_constructorMintsToWhoeverDeploys() public {
        vm.prank(ALICE);
        IDEADToken direct = new IDEADToken();
        assertEq(direct.balanceOf(ALICE), SUPPLY, "alice deployed, alice holds the supply");
        assertEq(direct.totalSupply(), SUPPLY, "supply of the second deployment");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transfer_movesBalanceAndEmits() public {
        uint256 amount = 1_000e18;
        vm.prank(address(deployer));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(deployer), ALICE, amount);
        bool ok = token.transfer(ALICE, amount);
        assertTrue(ok, "transfer returned false");
        assertEq(token.balanceOf(ALICE), amount, "alice balance");
        assertEq(token.balanceOf(address(deployer)), SUPPLY - amount, "deployer balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transfer_fullBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY, "alice holds everything");
        assertEq(token.balanceOf(address(deployer)), 0, "deployer holds nothing");
    }

    function test_transfer_zeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer returned false");
        assertEq(token.balanceOf(BOB), 0, "bob balance");
    }

    function test_transfer_toSelfKeepsBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 500e18);
        vm.prank(ALICE);
        token.transfer(ALICE, 500e18);
        assertEq(token.balanceOf(ALICE), 500e18, "self-transfer changed the balance");
    }

    function test_transfer_revertsOnInsufficientBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, ALICE, 10e18, 10e18 + 1));
        vm.prank(ALICE);
        token.transfer(BOB, 10e18 + 1);
    }

    function test_transfer_revertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(address(deployer));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approve_setsAllowanceAndEmits() public {
        vm.prank(ALICE);
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, 123);
        assertTrue(token.approve(BOB, 123), "approve returned false");
        assertEq(token.allowance(ALICE, BOB), 123, "allowance");
    }

    function test_approve_overwritesPreviousAllowance() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 100);
        token.approve(BOB, 7);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 7, "allowance is the last value set");
    }

    function test_approve_revertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    function test_transferFrom_spendsAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 60e18);

        vm.prank(BOB);
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, CAROL, 40e18);
        assertTrue(token.transferFrom(ALICE, CAROL, 40e18), "transferFrom returned false");

        assertEq(token.balanceOf(ALICE), 60e18, "alice balance");
        assertEq(token.balanceOf(CAROL), 40e18, "carol balance");
        assertEq(token.balanceOf(BOB), 0, "the spender received nothing");
        assertEq(token.allowance(ALICE, BOB), 20e18, "allowance decremented");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferFrom_infiniteAllowanceIsNotDecremented() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);

        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 100e18);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "infinite allowance was decremented");
        assertEq(token.balanceOf(CAROL), 100e18, "carol balance");
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100e18);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_transferFrom_revertsAboveAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 10);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 10, 11));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 11);
        assertEq(token.allowance(ALICE, BOB), 10, "a failed transferFrom spent allowance");
    }

    function test_transferFrom_revertsWhenAllowanceExceedsBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 5);
        vm.prank(ALICE);
        token.approve(BOB, 10);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 6);
    }

    function test_transferFrom_revertsToZeroAddress() public {
        vm.prank(address(deployer));
        token.approve(BOB, 1);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(deployer), address(0), 1);
    }

    function test_transferFrom_deployerCannotPullFromHolderWithoutAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100e18);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, address(deployer), 0, 1));
        vm.prank(address(deployer));
        token.transferFrom(ALICE, address(deployer), 1);
        assertEq(token.balanceOf(ALICE), 100e18, "the deployer moved a holder's balance");
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged path
    // ---------------------------------------------------------------------------------------------

    /// @dev Mirrors the launch floor: common mint and admin selectors, tried by a stranger and by the
    /// deployer, must leave the supply and the stranger's balance untouched.
    function test_noCallIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertTrue(!ok, string.concat("unexpected success from a stranger: ", signatures[i]));
            vm.prank(address(deployer));
            (ok,) = address(token).call(data);
            assertTrue(!ok, string.concat("unexpected success from the deployer: ", signatures[i]));
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    /// @dev Mirrors the launch floor: pause, blacklist, freeze, seize and burnFrom selectors tried by
    /// the deployer must not move or freeze a holder's balance.
    function test_noCallMovesOrFreezesAHolder() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(data);
            assertTrue(!ok, string.concat("unexpected success: ", signatures[i]));
        }
        assertEq(token.balanceOf(ALICE), held, "a privileged call moved the holder's balance");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "the holder can no longer transfer");
        assertEq(token.balanceOf(BOB), held / 2, "the holder's transfer delivered short");
    }

    function test_noEtherAccepted() public {
        (bool ok,) = address(token).call{value: 1 wei}("");
        assertTrue(!ok, "the token accepted ether");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = amount % (SUPPLY + 1);
        vm.prank(address(deployer));
        assertTrue(token.transfer(to, amount), "transfer returned false");
        if (to == address(deployer)) {
            assertEq(token.balanceOf(address(deployer)), SUPPLY, "self-transfer changed the deployer balance");
        } else {
            assertEq(token.balanceOf(to), amount, "recipient balance");
            assertEq(token.balanceOf(address(deployer)), SUPPLY - amount, "sender balance");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    function testFuzz_transferRevertsAboveBalance(uint256 excess) public {
        excess = (excess % 1e30) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDEADToken.ERC20InsufficientBalance.selector, address(deployer), SUPPLY, SUPPLY + excess
            )
        );
        vm.prank(address(deployer));
        token.transfer(ALICE, SUPPLY + excess);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = allowanceAmount % (SUPPLY + 1);
        spend = allowanceAmount == 0 ? 0 : spend % (allowanceAmount + 1);
        vm.prank(address(deployer));
        token.approve(BOB, allowanceAmount);
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(deployer), CAROL, spend), "transferFrom returned false");
        assertEq(token.balanceOf(CAROL), spend, "carol balance");
        assertEq(token.balanceOf(address(deployer)), SUPPLY - spend, "deployer balance");
        assertEq(token.allowance(address(deployer), BOB), allowanceAmount - spend, "remaining allowance");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    function testFuzz_transferFromRevertsAboveAllowance(uint256 allowanceAmount, uint256 excess) public {
        allowanceAmount = allowanceAmount % SUPPLY;
        excess = (excess % (SUPPLY - allowanceAmount)) + 1;
        vm.prank(address(deployer));
        token.approve(BOB, allowanceAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDEADToken.ERC20InsufficientAllowance.selector, BOB, allowanceAmount, allowanceAmount + excess
            )
        );
        vm.prank(BOB);
        token.transferFrom(address(deployer), CAROL, allowanceAmount + excess);
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = a % (SUPPLY + 1);
        b = b % (a + 1);
        c = c % (b + 1);
        vm.prank(address(deployer));
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CAROL, c);
        uint256 sum =
            token.balanceOf(address(deployer)) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL);
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
        assertEq(token.balanceOf(ALICE), a - b, "alice balance");
        assertEq(token.balanceOf(BOB), b - c, "bob balance");
        assertEq(token.balanceOf(CAROL), c, "carol balance");
    }
}
