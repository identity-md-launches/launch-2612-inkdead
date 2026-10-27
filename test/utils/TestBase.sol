// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The subset of Foundry cheatcodes these tests use, declared here so the project needs no
/// vendored test library. Every function matches the signature Foundry's `Vm` exposes at the
/// cheatcode address.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function assume(bool condition) external pure;
    function label(address account, string calldata newLabel) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
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

    function assertEq(bytes32 a, bytes32 b, string memory message) internal pure {
        if (a != b) revert(message);
    }

    function assertEq(bytes memory a, bytes memory b, string memory message) internal pure {
        if (keccak256(a) != keccak256(b)) revert(message);
    }

    /// @dev Maps `x` into `[min, max]` without discarding runs, the way forge-std's `bound` does:
    /// values already in range are kept, so the edges a fuzzer favours (0, 1, max) still land on
    /// the edges of the range.
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        require(min <= max, "bound: min > max");
        if (x >= min && x <= max) return x;
        uint256 size = max - min;
        if (size == type(uint256).max) return x;
        size += 1;
        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) return max - (type(uint256).max - x);
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            return min + rem - 1;
        }
        uint256 diff2 = min - x;
        uint256 rem2 = diff2 % size;
        if (rem2 == 0) return min;
        return max - rem2 + 1;
    }
}
