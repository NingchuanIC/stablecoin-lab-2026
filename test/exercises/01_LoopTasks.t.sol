// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount > 0);

        // Start with existing supply so we check the increase, not just the final total.
        uint256 initialDeposit = 1_000e6;
        usdc.faucet(alice, initialDeposit + amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), initialDeposit + amount);
        vault.deposit(initialDeposit);

        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();
        uint256 balanceBefore = stable.balanceOf(alice);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(stable.totalSupply() - supplyBefore, amount, "Supply must grow by the deposit");
        assertEq(
            stable.balanceOf(alice) - balanceBefore, amount, "Alice must receive the minted sUSD"
        );
        assertEq(
            vault.totalCollateral() - collateralBefore, amount, "Vault must receive the collateral"
        );
        assertEq(usdc.balanceOf(alice), 0, "Both deposits must transfer Alice's mUSDC");
        assertEq(vault.totalCollateral(), stable.totalSupply(), "Supply must remain fully backed");
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is 10^15 mUSDC, not 1000.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        uint256 intendedAmount = 1_000e6;
        uint256 mistakenAmount = 1_000e18;
        assertEq(usdc.decimals(), 6, "mUSDC uses 6 decimals");
        assertEq(stable.decimals(), 6, "sUSD uses 6 decimals");
        uint256 unitsPerToken = 10 ** uint256(usdc.decimals());

        // Enough balance and allowance make this huge deposit valid in the mock system.
        usdc.faucet(alice, mistakenAmount);
        vm.startPrank(alice);
        usdc.approve(address(vault), mistakenAmount);
        vault.deposit(mistakenAmount);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), mistakenAmount, "The raw input is minted 1:1");
        assertEq(stable.totalSupply(), mistakenAmount, "Supply uses the same raw units");
        assertEq(
            vault.totalCollateral(), mistakenAmount, "The huge amount is actually collateralized"
        );
        assertEq(vault.totalCollateral(), stable.totalSupply(), "The backing invariant still holds");
        assertEq(usdc.balanceOf(alice), 0, "All the funded collateral was deposited");
        assertEq(
            mistakenAmount / unitsPerToken, 1_000_000_000_000_000, "Actual amount is 10^15 tokens"
        );
        assertEq(
            mistakenAmount / intendedAmount,
            1_000_000_000_000,
            "The amount is 10^12 times too large"
        );

        emit log_named_uint("Intended amount (raw units)", intendedAmount);
        emit log_named_uint("Mistaken amount (raw units)", mistakenAmount);
        emit log_named_uint("Intended amount (whole tokens)", intendedAmount / unitsPerToken);
        emit log_named_uint("Actual amount (whole tokens)", mistakenAmount / unitsPerToken);
        emit log_named_uint("sUSD balance (raw units)", stable.balanceOf(alice));
        emit log_named_uint("Vault collateral (raw units)", vault.totalCollateral());
        emit log_named_uint("sUSD totalSupply (raw units)", stable.totalSupply());
        emit log_named_uint("Error factor", mistakenAmount / intendedAmount);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        assertTrue(false, "TODO Ex4.1");
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        assertTrue(false, "TODO Ex4.2");
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        assertTrue(false, "TODO Ex4.3");
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        assertTrue(false, "TODO Ex4.4");
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        assertTrue(false, "TODO Ex4.5");
    }
}
