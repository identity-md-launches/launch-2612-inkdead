// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase, Vm} from "./utils/TestBase.sol";
import {IDEADToken} from "../src/IDEADToken.sol";

contract EdgeDeployer {
    function deploy() external returns (IDEADToken) {
        return new IDEADToken();
    }
}

/// @notice Inputs the happy-path suite does not reach: the zero address as a caller, the order in
/// which `transferFrom` checks allowance and balance, the allowance just below "unlimited", and that
/// a reverted call leaves nothing behind.
/// forge-config: default.fuzz.runs = 1000
contract IDEADTokenEdgesTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    bytes32 internal constant APPROVAL_TOPIC = keccak256("Approval(address,address,uint256)");
    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    address internal deployer;
    IDEADToken internal token;

    function setUp() public {
        EdgeDeployer d = new EdgeDeployer();
        token = d.deploy();
        deployer = address(d);
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(to, amount);
    }

    // ---------------------------------------------------------------------------------------------
    // The zero address as caller or counterparty
    // ---------------------------------------------------------------------------------------------

    function test_zeroAddressCallerCannotTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_zeroAddressCallerCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(ALICE, 1);
    }

    /// @dev With no allowance and a zero amount, the allowance check passes and the sender guard is
    /// what stops a pull from the zero address.
    function test_transferFromZeroAddressRevertsAsInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(0), CAROL, 0);
    }

    function test_transferFromZeroAddressNonZeroAmountRevertsOnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(0), CAROL, 1);
    }

    function test_transferZeroAmountToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    function test_transferFromToZeroAddressWithInfiniteAllowanceReverts() public {
        vm.prank(deployer);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY, "a reverted burn moved tokens");
    }

    function test_balanceOfZeroAddressIsZero() public view {
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
    }

    // ---------------------------------------------------------------------------------------------
    // transferFrom ordering and allowance edges
    // ---------------------------------------------------------------------------------------------

    /// @dev An owner calling transferFrom on its own balance still needs an allowance to itself.
    function test_transferFromOwnBalanceNeedsSelfAllowance() public {
        _fund(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);

        vm.startPrank(ALICE);
        token.approve(ALICE, 4);
        token.transferFrom(ALICE, BOB, 4);
        vm.stopPrank();
        assertEq(token.balanceOf(BOB), 4, "self-approved pull delivered");
        assertEq(token.allowance(ALICE, ALICE), 0, "self allowance spent");
    }

    /// @dev Allowance is checked before balance: with both short, the allowance error wins.
    function test_transferFromBothShortReportsAllowanceFirst() public {
        _fund(ALICE, 5);
        vm.prank(ALICE);
        token.approve(BOB, 3);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 3, 6));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 6);
    }

    function test_transferFromZeroAmountWithoutAllowanceSucceeds() public {
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 0), "zero pull returned false");
        assertEq(token.allowance(ALICE, BOB), 0, "allowance changed");
    }

    /// @dev One below "unlimited" is an ordinary allowance and is decremented.
    function test_allowanceJustBelowMaxIsDecremented() public {
        vm.prank(deployer);
        token.approve(BOB, type(uint256).max - 1);
        vm.prank(BOB);
        token.transferFrom(deployer, CAROL, 1);
        assertEq(token.allowance(deployer, BOB), type(uint256).max - 2, "allowance not decremented");
    }

    function test_infiniteAllowanceStillBoundByBalance() public {
        _fund(ALICE, 7);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, ALICE, 7, 8));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 8);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "allowance changed");
    }

    function test_allowanceSpentExactlyToZeroThenReverts() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 30);
        vm.startPrank(BOB);
        token.transferFrom(ALICE, CAROL, 30);
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(ALICE, CAROL, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 70, "alice balance");
    }

    function test_approveZeroRevokes() public {
        _fund(ALICE, 100);
        vm.startPrank(ALICE);
        token.approve(BOB, 50);
        token.approve(BOB, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
    }

    function test_allowancesAreIsolatedPerOwnerAndSpender() public {
        vm.prank(ALICE);
        token.approve(BOB, 11);
        assertEq(token.allowance(ALICE, BOB), 11, "alice->bob");
        assertEq(token.allowance(BOB, ALICE), 0, "bob->alice is not symmetric");
        assertEq(token.allowance(ALICE, CAROL), 0, "alice->carol");
    }

    // ---------------------------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------------------------

    /// @dev transferFrom emits exactly one Transfer and no Approval (OpenZeppelin v5 semantics).
    function test_transferFromEmitsOnlyTransfer() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 60);
        vm.recordLogs();
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 40);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one log");
        assertEq(logs[0].emitter, address(token), "emitter");
        assertEq(logs[0].topics[0], TRANSFER_TOPIC, "Transfer topic");
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(ALICE))), "from");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(CAROL))), "to");
        assertEq(abi.decode(logs[0].data, (uint256)), 40, "value");
    }

    function test_zeroTransferEmitsTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        token.transfer(BOB, 0);
    }

    function test_approveMaxEmitsApproval() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, type(uint256).max);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
    }

    // ---------------------------------------------------------------------------------------------
    // Construction details
    // ---------------------------------------------------------------------------------------------

    function test_constructorEmitsExactlyOneLog() public {
        vm.recordLogs();
        EdgeDeployer d = new EdgeDeployer();
        IDEADToken t = d.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one log");
        assertEq(logs[0].emitter, address(t), "emitter");
        assertEq(logs[0].topics[0], TRANSFER_TOPIC, "Transfer topic");
        assertEq(logs[0].topics[1], bytes32(0), "minted from zero");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(d)))), "minted to deployer");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "minted the supply");
    }

    function test_supplyExactMinorUnits() public view {
        assertEq(token.totalSupply(), 1000000000000000000000000000, "supply in minor units");
        assertEq(uint256(token.DECIMALS()), 18, "DECIMALS constant");
        assertEq(token.NAME(), "InkDead", "NAME constant");
        assertEq(token.SYMBOL(), "IDEAD", "SYMBOL constant");
    }

    function test_unknownSelectorAndEmptyCalldataRevert() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertTrue(!ok, "unknown selector succeeded");
        (ok,) = address(token).call("");
        assertTrue(!ok, "empty calldata succeeded");
        (ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertTrue(!ok, "burn exists");
        assertEq(token.totalSupply(), SUPPLY, "supply");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: reverted calls leave state untouched; allowance arithmetic at its edges
    // ---------------------------------------------------------------------------------------------

    function testFuzz_failedTransferLeavesStateUntouched(uint256 held, uint256 excess) public {
        held = bound(held, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - held);
        _fund(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IDEADToken.ERC20InsufficientBalance.selector, ALICE, held, held + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + excess);
        assertEq(token.balanceOf(ALICE), held, "sender balance");
        assertEq(token.balanceOf(BOB), 0, "receiver balance");
        assertEq(token.balanceOf(deployer), SUPPLY - held, "deployer balance");
    }

    function testFuzz_allowanceDecrementsExactly(uint256 allowed, uint256 spend) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        spend = bound(spend, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(deployer);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        token.transferFrom(deployer, CAROL, spend);
        assertEq(token.allowance(deployer, BOB), allowed - spend, "remaining allowance");
        assertEq(token.balanceOf(CAROL), spend, "received");
    }

    function testFuzz_infiniteAllowanceNeverDecrements(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        vm.prank(deployer);
        token.approve(BOB, type(uint256).max);
        vm.startPrank(BOB);
        token.transferFrom(deployer, CAROL, a);
        token.transferFrom(deployer, ALICE, b);
        vm.stopPrank();
        assertEq(token.allowance(deployer, BOB), type(uint256).max, "allowance decremented");
        assertEq(token.balanceOf(deployer), SUPPLY - a - b, "deployer balance");
    }

    function testFuzz_approveSetsAnyValue(address owner, address spender, uint256 value) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(owner, spender), value, "allowance");
    }

    function testFuzz_transferFromAboveAllowanceKeepsAllowance(uint256 allowed, uint256 excess) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        excess = bound(excess, 1, type(uint256).max - allowed);
        vm.prank(deployer);
        token.approve(BOB, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IDEADToken.ERC20InsufficientAllowance.selector, BOB, allowed, allowed + excess)
        );
        vm.prank(BOB);
        token.transferFrom(deployer, CAROL, allowed + excess);
        assertEq(token.allowance(deployer, BOB), allowed, "allowance changed by a revert");
        assertEq(token.balanceOf(deployer), SUPPLY, "balance changed by a revert");
    }

    function testFuzz_transferToSelfIsNoop(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY, "self-transfer changed balance");
    }
}
