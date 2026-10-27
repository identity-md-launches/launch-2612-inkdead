// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The subset of Foundry cheatcodes these tests use, declared here so the project needs no
/// vendored test library. Every function matches the signature Foundry's `Vm` exposes at the
/// cheatcode address.
interface Vm {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function assume(bool condition) external pure;
    function label(address account, string calldata newLabel) external;
}

/// @notice Minimal assertion base for the tests. A failed assertion reverts with its message, which
/// Foundry reports as the test's failure.
abstract contract TestBase {
    /// @dev `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition, string memory message) internal pure {
        if (!condition) revert(message);
    }

    function assertEq(uint256 a, uint256 b, string memory message) internal pure {
        if (a != b) revert(message);
    }

    function assertEq(address a, address b, string memory message) internal pure {
        if (a != b) revert(message);
    }

    function assertEq(string memory a, string memory b, string memory message) internal pure {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) revert(message);
    }

    function assertLe(uint256 a, uint256 b, string memory message) internal pure {
        if (a > b) revert(message);
    }

    function assertGt(uint256 a, uint256 b, string memory message) internal pure {
        if (a <= b) revert(message);
    }
}
