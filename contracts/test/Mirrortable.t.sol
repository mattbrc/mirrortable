// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Mirrortable.sol";
import "../src/MockERC20.sol";

/**
 * @dev Basic test for Mirrortable
 */
contract MirrortableTest is Test {
    Mirrortable public mirrortable;
    MockERC20 public usdc;

    address alice = address(0x1234);
    address bob = address(0x5678);

    function setUp() public {
        // 1. Deploy Mirrortable
        mirrortable = new Mirrortable();

        // 2. Deploy Mock USDC
        usdc = new MockERC20("Mock USDC", "mUSDC");

        // 3. Make the test contract the owner of Mirrortable
        //    so we can call createShareClass().
        mirrortable.transferOwnership(address(this));

        // 4. Fund Alice with 1000 USDC
        usdc.mint(alice, 1000e6); // 1,000 USDC (6 decimals)
    }

    function testCreateShareClass() public {
        mirrortable.createShareClass("Seed", 1e6, 10000, false);
        (
            string memory name,
            uint256 price,
            uint256 supply,
            bool restricted
        ) = mirrortable.shareClasses(0);

        assertEq(name, "Seed");
        assertEq(price, 1e6);
        assertEq(supply, 10000);
        assertFalse(restricted);
    }

    function testInvest() public {
        // 1. Create a share class
        mirrortable.createShareClass("Seed", 1e6, 10000, false);

        // 2. Alice invests 500 USDC
        // Approve & invest
        vm.startPrank(alice);
        usdc.approve(address(mirrortable), 500e6);
        mirrortable.invest(0, 500e6, address(usdc));
        vm.stopPrank();

        // 3. Check that Alice now holds 500 shares
        uint256 aliceShares = mirrortable.sharesBalanceOf(alice, 0);
        assertEq(aliceShares, 500);

        // 4. Check totalShares decreased
        (, , uint256 remaining, ) = mirrortable.shareClasses(0);
        assertEq(remaining, 10000 - 500);

        // 5. Check that contract's owner (test contract) got the 500 USDC
        uint256 contractOwnerBal = usdc.balanceOf(address(this));
        assertEq(contractOwnerBal, 500e6);
    }

    function testTransferShares() public {
        // Create a restricted share class
        mirrortable.createShareClass("RestrictedRound", 1e6, 10000, true);

        // Alice invests 100 shares
        vm.startPrank(alice);
        usdc.approve(address(mirrortable), 100e6);
        mirrortable.invest(0, 100e6, address(usdc));
        vm.stopPrank();

        // Now Alice has 100 shares
        uint256 aliceBal = mirrortable.sharesBalanceOf(alice, 0);
        assertEq(aliceBal, 100);

        // Attempt transfer to Bob
        vm.startPrank(alice);
        mirrortable.transferShares(bob, 0, 50);
        vm.stopPrank();

        // Because we haven't implemented actual KYC checks (they default to true),
        // the transfer should succeed.
        assertEq(mirrortable.sharesBalanceOf(alice, 0), 50);
        assertEq(mirrortable.sharesBalanceOf(bob, 0), 50);
    }
}
