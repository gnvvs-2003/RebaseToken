// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RebaseTokenTest} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test{
    // private variables
    RebaseTokenTest private rebaseToken;
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

    function setUp() public{
        vm.startPrank(owner); // for access control
        rebaseToken = new RebaseTokenTest();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        vm.stopPrank();
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

    function testDepositLinear(uint256 amount) public{
        amount = bound(amount,1e5,type(uint96).max);
        vm.startPrank(user);
        vm.deal(user,amount);
        vault.deposit{value: amount}();
        uint255 initialBalance = rebaseToken.balanceOf(user);
        uint256 timeDelta = 1 days;
        vm.warp(block.timestamp+ timeDelta);
        uint256 balanceAfterFirstTimeDelta = rebaseToken.balanceOf(user);
        uint256 interestEarned = balanceAfterFirstTimeDelta - initialBalance;
        vm.warp(block.timestamp+ timeDelta);
        uint256 balanceAfterSecondTimeDelta = rebaseToken.balanceOf(user);
        uint256 interestEarned2 = balanceAfterSecondTimeDelta - balanceAfterFirstTimeDelta;
        assertEq(interestEarned,interestEarned2);
        vm.stopPrank();
    }

}