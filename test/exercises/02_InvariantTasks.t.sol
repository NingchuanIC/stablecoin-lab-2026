// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex6 — invariant testing
/// @notice Every test so far set up a situation and then checked the result. Invariant
///         testing flips that around: let the machine call operations randomly and
///         repeatedly, then ask "no matter how it thrashes, does this property still
///         hold?"
///
///         That is what a stablecoin should be tested like — you will never guess the
///         order an attacker does things in.
///
///         Acceptance: make exercise (it should be red until you are finished)
///
/// @dev How it works: Foundry picks functions from the handler at random, picks random
///      arguments, and calls them N times in a row; after each round it runs every
///      invariant_* function. The first failed assertion is a counterexample.
contract VaultHandler is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address[3] public users;

    /// @dev Bookkeeping: proves the fuzzer really reached the handler instead of idling
    uint256 public ghost_deposits;
    uint256 public ghost_redeems;

    constructor(MockUSDC usdc_, SimpleStablecoin stable_, Vault vault_) {
        usdc = usdc_;
        stable = stable_;
        vault = vault_;

        users[0] = makeAddr("user0");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");
        for (uint256 i; i < users.length; ++i) {
            usdc.faucet(users[i], 1_000_000e6);
        }
    }

    /// @dev Given to you — this is the standard shape of "pick a random argument and keep it
    ///      inside a valid range"
    function deposit(uint256 userSeed, uint256 amount) external {
        address user = users[bound(userSeed, 0, users.length - 1)];

        uint256 balance = usdc.balanceOf(user);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        ghost_deposits++;
    }

    /// Ex6.1 — redemption
    /// @dev Requirements:
    ///       1) pick one user at random (a user may hold 0 sUSD — if so, return early)
    ///       2) bound amount to [1, that user's sUSD balance]
    ///       3) call vault.redeem(amount) as that user
    ///       4) do not forget approve — redeem needs no allowance, but deposit does
    ///      Hint: the two parameters have no names yet. Name them first.
    function redeem(uint256 userSeed, uint256 amount) external {
        address user = users[bound(userSeed, 0, users.length - 1)];
        uint256 balance = stable.balanceOf(user);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(user);
        vault.redeem(amount);
        ghost_redeems++;
    }
}

contract InvariantTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;
    VaultHandler internal handler;

    address internal admin = address(this);

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));

        handler = new VaultHandler(usdc, stable, vault);

        // Let the fuzzer call only the handler's deposit / redeem, not its other functions
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.redeem.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// Ex6.2 — backing holds across arbitrary sequences of legitimate operations.
    function invariant_CollateralBacksSupply() public view {
        assertGe(vault.totalCollateral(), stable.totalSupply(), "collateral must cover supply");
    }

    /// Ex6.3 — deposit/redeem never leave stablecoins inside the vault.
    /// @dev This property applies to the handler's operations; unsolicited sUSD transfers
    ///      into the vault are outside this particular invariant's scope.
    function invariant_VaultHoldsNoStablecoin() public view {
        assertEq(stable.balanceOf(address(vault)), 0, "vault must not retain minted sUSD");
    }

    function test_Ex6_HandlerRoundTrip() public {
        handler.deposit(0, 100e6);
        handler.redeem(0, 40e6);
        assertEq(handler.ghost_deposits(), 1);
        assertEq(handler.ghost_redeems(), 1);
        assertEq(stable.balanceOf(handler.users(0)), 60e6);
        assertEq(vault.totalCollateral(), 60e6);
        assertEq(stable.totalSupply(), 60e6);
        handler.redeem(0, type(uint256).max);
        assertEq(handler.ghost_redeems(), 2);
        assertEq(stable.totalSupply(), 0);
        assertEq(vault.totalCollateral(), 0);
    }
}
