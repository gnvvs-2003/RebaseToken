// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    // private variables
    RebaseToken private rebaseToken;
    Vault private vault;
    // public variables
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    /**
     * @notice This function is used to set up the test environment
     * We are sending the address of the rebase token to the vault contract
     * This address will implement the IRebaseToken interface which includes mint and burn functions which are declared in the interface
     * Since the rebaseToken address has access to the mint and buren function we can pass this address
     * In simple terms : “Trust me, this address implements IRebaseToken.”
     * Next we grant a role to the vault contract to mint and burn tokens since the contract inherits from the interface IRebaseToken
     * Finally we send an initial liquid amount of 1ETH
     * We are using prank here since the subsequent transactions require the roles which are granted by the owner only
     * With out doing prank as owner the transactions would be called from the test contract but not from the owner or roles provided by the owner
     */

    function setUp() public {
        vm.startPrank(owner); // for access control
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        // assert(success);
    }

    // test functions

    /**
     * Test -1 : Testing if the rebase token accures interest linearly over time after user deposits
     * @param amount : Amount of ETH to be deposited (Fuzzed parameter)
     * Step-1 : Bound the value of amount between 1e5(100,000 WEI) and type(uint96).max
     * step-2 : Send the amount of ETH to the user
     * Step-3 : Implement the deposit logic
     * Step-4 : Warp time forard by t seconds to check if the interest  = balance gained  = g1
     * Step-5 : Warp time forard again by t seconds to check if the interest  = balance gained  = g2
     * Step-6 : Check if g1 = g2
     */

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}(); // msg.sender = user => user deposits the amount to vault
        uint256 initialBalance = rebaseToken.balanceOf(user);
        assertApproxEqAbs(initialBalance, amount, 1); // margin = 1wei
        uint256 timeDelta = 1 hours;
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstTimeDelta = rebaseToken.balanceOf(user);
        uint256 interestEarned = balanceAfterFirstTimeDelta - initialBalance;
        assert(interestEarned > 0);
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterSecondTimeDelta = rebaseToken.balanceOf(user);
        uint256 interestEarned2 = balanceAfterSecondTimeDelta - balanceAfterFirstTimeDelta;
        assert(interestEarned2 > 0);
        assertApproxEqAbs(interestEarned, interestEarned2, 1); // margin = 1wei
        vm.stopPrank();
    }

    /**
     * Test -2 :Testing redeem operations : Immediate redeem
     * This test case checks the functionality when users deposits and redeem immediately their entire balance
     * User deposit a fuzzed amount
     * User redeems their full balance
     */

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}(); // msg.sender = user => user deposits the amount to vault
        uint256 initialBalance = rebaseToken.balanceOf(user);
        vault.redeem(initialBalance); // msg.sender = user => user redeems their full balance
        uint256 finalBalance = rebaseToken.balanceOf(user);
        assertApproxEqAbs(finalBalance, 0, 1); // margin = 1wei
        vm.stopPrank();
    }

    /**
     * Test -3 :Testing redeem operations : Partial redeem i.e redeem after time passed
     * This test case checks the functionality when users deposits and redeem after some time has passed
     * User deposit a fuzzed amount
     * User redeems their full balance
     */

    function testRedeemAfterTimePassed(uint256 _amount, uint256 _timeDelta) public {
        _timeDelta = bound(_timeDelta, 1000, type(uint96).max);
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();
        vm.warp(block.timestamp + _timeDelta);
        uint256 balanceAfterTimePassed = rebaseToken.balanceOf(user);
        vm.deal(owner, balanceAfterTimePassed - _amount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterTimePassed - _amount);
        vm.prank(user);
        vault.redeem(type(uint256).max); // redeeem total amount
        uint256 ethBalance = address(user).balance;
        assertApproxEqAbs(ethBalance, balanceAfterTimePassed, 1);
        assertGt(ethBalance, _amount);
    }

    /**
     * Test -4 :Testing transfer operations
     * This test case checks the functionality when users transfer their tokens to another user(a new user)
     * User deposit a fuzzed amount
     * User transfers their tokens to another user
     * This test checks the tranfer of tokens and also the inherited interest rate of the users
     */

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amount, 1e5, amount - 1e5);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);
        // owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRateByNonOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 1e5, 5e10);
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 1e5);
    }

    function testGetPrincipalAmount(uint256 amount) public {
        // principle Amount never changes only interest accumulates
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principalBalanceOf(user), amount);
        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    function testGetRebaseTokenAddress() public {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateWillOnlyDecrease(uint256 newInterestRate) public {
        uint256 initalInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initalInterestRate + 1, type(uint256).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecreaseWithTime.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initalInterestRate);
    }

    function testOnlyOwnerCanGrantMintAndBurnRole() public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.grantMintAndBurnRole(user);
    }
}

