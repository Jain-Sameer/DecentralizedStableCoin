// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {
    ERC20Burnable, ERC20
} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract DecentralisedStableCoinTest is Test {
    DecentralisedStableCoin dsc;

    error InconsistentSupply();

    address owner = address(this);
    address user = makeAddr("user");
    address unauthorizedAccount = user;
    uint256 constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        dsc = new DecentralisedStableCoin(owner);
        dsc.mint(user, STARTING_BALANCE);
        dsc.mint(owner, STARTING_BALANCE);
    }

    function testOwnerIsCorrect() public view {
        assertEq(dsc.owner(), owner);
    }

    function testIfOnlyOwnerCanCallFunction() public {
        vm.startPrank(user);
        uint256 AMOUNT = 0.001 ether;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        dsc.burn(AMOUNT);
        vm.stopPrank();
    }

    function testIfOwnerCanCallFunction() public {
        vm.startPrank(owner);
        dsc.mint(owner, 10 ether);
        uint256 AMOUNT_TO_BURN = 0.01 ether;
        dsc.burn(AMOUNT_TO_BURN);
        vm.stopPrank();
    }

    function testIfBalanceIsGreaterThanAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_MustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_MustBeMoreThanZero.selector);
        dsc.mint(user, 0);
        vm.stopPrank();
    }

    function testIfZeroAddress() public {
        vm.startPrank(owner);
        address userTest = address(0);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_MustBeNotZeroAddress.selector);
        dsc.mint(userTest, 1);
        vm.stopPrank();
    }

    function testIfBalanceLessThanAmount() public {
        vm.startPrank(owner);
        uint256 AMOUNT_TO_BURN = 1000 ether;
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_BurnAmountExceedsBalance.selector);
        dsc.burn(AMOUNT_TO_BURN);
        vm.stopPrank();
    }

    function testIfMintingIncreasesTheBalanceOfTheUser() public {
        vm.startPrank(owner);
        uint256 initialBalanceOfUser = dsc.balanceOf(user);
        uint256 mintAmount = 1 ether;
        dsc.mint(user, mintAmount);
        uint256 finalBalanceOfUser = initialBalanceOfUser + mintAmount;
        assertEq(finalBalanceOfUser, dsc.balanceOf(user), "Not successfully minted");
        vm.stopPrank();
    }

    function testIfBurningDecreasesTheOwnerBalance() public {
        vm.startPrank(owner);
        uint256 ownerStartingBalance = dsc.balanceOf(owner);
        uint256 burnAmount = 10 ether;
        dsc.burn(burnAmount);
        uint256 ownerEndingBalance = dsc.balanceOf(owner);
        assertEq(ownerStartingBalance - burnAmount, ownerEndingBalance);
        vm.stopPrank();
    }

    function testIfTotalSupplyIsConsistent() public view {
        uint256 amountUser = dsc.balanceOf(user);
        uint256 amountOwner = dsc.balanceOf(owner);
        uint256 totalSupply = dsc.totalSupply();
        uint256 expectedSupply = amountUser + amountOwner;

        assertEq(expectedSupply, totalSupply, "Supply is inconsistent");
    }

    function testIfTotalSupplyisInconsistent() public {
        uint256 amountUser = dsc.balanceOf(user);
        uint256 amountOwner = dsc.balanceOf(owner);

        vm.startPrank(owner);
        address tempuser = makeAddr("tempuser");
        dsc.mint(tempuser, 10 ether);
        vm.stopPrank();
        uint256 totalSupply = dsc.totalSupply();
        uint256 expectedSupply = amountUser + amountOwner;
        vm.expectRevert(InconsistentSupply.selector);
        if (totalSupply != expectedSupply) {
            revert InconsistentSupply();
        }
    }
}
