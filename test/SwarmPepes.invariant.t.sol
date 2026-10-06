// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../src/SwarmPepes.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Closed actor set: every possible recipient is tracked. Ghosts record intended
/// transfers and authorizations, never copy post-call balances or allowances.
contract SwarmPepesHandler is TestBase {
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    SwarmPepes public immutable token;
    address[4] public actors;
    uint256[4] public balances;
    uint256[4][4] public approvals;

    constructor() {
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        token = new SwarmPepes();
        balances[0] = SUPPLY;
    }

    // Bounds retain zero, one and the entire balance frequently, without discards.
    function _amount(uint256 seed, uint256 maximum) internal pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return seed % (maximum + 1);
    }

    function transfer(uint256 from, uint256 to, uint256 seed) public {
        from %= 4;
        to %= 4;
        uint256 amount = _amount(seed, balances[from]);
        vm.prank(actors[from]);
        require(token.transfer(actors[to], amount), "transfer must succeed");
        balances[from] -= amount;
        balances[to] += amount;
    }

    function approve(uint256 owner, uint256 spender, uint256 seed) public {
        owner %= 4;
        spender %= 4;
        uint256 amount = seed % 4 == 0 ? type(uint256).max : _amount(seed, SUPPLY);
        _approve(owner, spender, amount);
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) internal {
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], amount), "approve must succeed");
        approvals[owner][spender] = amount;
    }

    // Uses prior authorizations, so replacement, revocation and repeated spending
    // interact across separate randomly ordered calls.
    function transferFrom(uint256 owner, uint256 spender, uint256 to, uint256 seed) public {
        owner %= 4;
        spender %= 4;
        to %= 4;
        uint256 allowance = approvals[owner][spender];
        uint256 maximum = balances[owner] < allowance ? balances[owner] : allowance;
        uint256 amount = _amount(seed, maximum);
        vm.prank(actors[spender]);
        require(token.transferFrom(actors[owner], actors[to], amount), "delegated transfer must succeed");
        if (allowance != type(uint256).max) approvals[owner][spender] -= amount;
        balances[owner] -= amount;
        balances[to] += amount;
    }

    function rejectedTransfer(uint256 owner, uint256 to, bool useMaximum) public {
        owner %= 4;
        to %= 4;
        uint256 amount = useMaximum ? type(uint256).max : balances[owner] + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balances[owner], amount
            )
        );
        vm.prank(actors[owner]);
        token.transfer(actors[to], amount);
        // Ghosts unchanged: global invariants detect any failed-call side effects.
    }

    function rejectedAllowance(uint256 owner, uint256 spender, uint256 to, uint256 seed) public {
        owner %= 4;
        spender %= 4;
        to %= 4;
        uint256 allowance = _amount(seed, SUPPLY);
        _approve(owner, spender, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowance, allowance + 1
            )
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], allowance + 1);
    }

    function rejectedDelegatedBalance(uint256 owner, uint256 spender, uint256 to, bool infinite) public {
        owner %= 4;
        spender %= 4;
        to %= 4;
        uint256 amount = balances[owner] + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balances[owner], amount
            )
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], amount);
    }

    function rejectedZeroRecipient(uint256 owner, uint256 spender, uint256 seed) public {
        owner %= 4;
        spender %= 4;
        uint256 amount = _amount(seed, balances[owner]);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], address(0), amount);
    }

    function roundTrip(uint256 owner, uint256 other, uint256 seed) public {
        owner %= 4;
        other = (owner + 1 + other % 3) % 4;
        uint256 amount = _amount(seed, balances[owner]);
        vm.prank(actors[owner]);
        require(token.transfer(actors[other], amount), "roundtrip outward");
        vm.prank(actors[other]);
        require(token.transfer(actors[owner], amount), "roundtrip return");
        // An exact, fee-free roundtrip leaves all modeled balances unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmPepesInvariantTest is TestBase {
    SwarmPepesHandler internal handler;
    SwarmPepes internal token;

    // Foundry's target discovery ABI, kept local to avoid adding a dependency.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new SwarmPepesHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectedTransfer.selector;
        selectors[4] = handler.rejectedAllowance.selector;
        selectors[5] = handler.rejectedDelegatedBalance.selector;
        selectors[6] = handler.rejectedZeroRecipient.selector;
        selectors[7] = handler.roundTrip.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// @dev Fixed supply specification and exact conservation identity.
    function invariant_FixedSupplyEqualsSumOfBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18, "fixed supply");
        assertEq(sum, token.totalSupply(), "all supply accounted for");
        assertEq(token.balanceOf(address(0)), 0, "no burns");
        assertEq(token.balanceOf(address(token)), 0, "no unmodeled diversion");
    }

    function invariant_BalancesAndAllowancesMatchAuthorizedActions() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), handler.balances(i), "exact actor balance");
            for (uint256 j; j < 4; ++j) {
                assertEq(
                    token.allowance(handler.actors(i), handler.actors(j)),
                    handler.approvals(i, j),
                    "exact authorization, including failed-call rollback"
                );
            }
        }
    }

    // Pin an interacting sequence in addition to randomly generated sequences.
    function test_StatefulEdgesAndFailureRollback() public {
        handler.transfer(0, 1, 2); // entire supply
        handler.approve(1, 2, 0); // infinite authorization
        handler.transferFrom(1, 2, 1, 2); // delegated self-transfer
        handler.transferFrom(1, 2, 3, 1); // one wei
        handler.rejectedDelegatedBalance(3, 2, 0, false);
        handler.rejectedDelegatedBalance(3, 2, 0, true);
        handler.rejectedZeroRecipient(1, 2, 2);
        handler.rejectedAllowance(1, 2, 0, 0); // revoke, then reject spend
        handler.rejectedTransfer(1, 1, true); // uint256 maximum
        handler.roundTrip(1, 0, 2);
        invariant_FixedSupplyEqualsSumOfBalances();
        invariant_BalancesAndAllowancesMatchAuthorizedActions();
    }
}
