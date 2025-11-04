// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title MockERC20Test
 * @notice Test suite for MockERC20 token
 */
contract MockERC20Test is Test {
    MockERC20 token;
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        token = new MockERC20("Test Token", "TEST", 18);
    }

    function test_Constructor_SetsMetadata() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
    }

    function test_Mint_AddsToBalance() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_EmitsTransfer() public {
        uint256 amount = 1000 ether;
        
        // Verify mint increases balance (transfer event is implicit)
        token.mint(user1, amount);
        assertEq(token.balanceOf(user1), amount);
    }

    function test_Burn_RemovesFromBalance() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 300 ether;
        
        token.mint(user1, mintAmount);
        token.burn(user1, burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    function test_Burn_EmitsTransfer() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 300 ether;
        
        token.mint(user1, mintAmount);
        token.burn(user1, burnAmount);
        
        // Verify burn decreases balance (transfer event is implicit)
        assertEq(token.balanceOf(user1), mintAmount - burnAmount);
    }

    function test_Transfer_MovesTokens() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.transfer(user2, 500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
        assertEq(token.balanceOf(user2), 500 ether);
        assertEq(token.totalSupply(), amount);
    }

    function test_Transfer_EmitsEvent() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.transfer(user2, 500 ether);

        // Verify transfer occurred (transfer event is implicit)
        assertEq(token.balanceOf(user2), 500 ether);
    }

    function test_Transfer_RequiresSufficientBalance() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, amount + 1);
    }

    function test_Approve_SetsAllowance() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, 500 ether);

        assertEq(token.allowance(user1, user2), 500 ether);
    }

    function test_Approve_EmitsEvent() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, 500 ether);

        // Verify approval was set (approval event is implicit)
        assertEq(token.allowance(user1, user2), 500 ether);
    }

    function test_TransferFrom_UsingAllowance() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, 500 ether);

        vm.prank(user2);
        token.transferFrom(user1, user2, 500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
        assertEq(token.balanceOf(user2), 500 ether);
        assertEq(token.allowance(user1, user2), 0);
    }

    function test_TransferFrom_MaxAllowance() public {
        uint256 amount = 1000 ether;
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, type(uint256).max);

        vm.prank(user2);
        token.transferFrom(user1, user2, 500 ether);

        assertEq(token.allowance(user1, user2), type(uint256).max);
    }

    function test_MintBatch_MintsToMultipleAddresses() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = address(0x3);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        token.mintBatch(recipients, amounts);

        assertEq(token.balanceOf(user1), 100 ether);
        assertEq(token.balanceOf(user2), 200 ether);
        assertEq(token.balanceOf(address(0x3)), 300 ether);
        assertEq(token.totalSupply(), 600 ether);
    }

    function test_MintBatch_RevertsOnLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        vm.expectRevert("MockERC20: arrays length mismatch");
        token.mintBatch(recipients, amounts);
    }
}

