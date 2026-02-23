// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol"; // Added later

/**
 * @title Vault
 * @author gnvvs-2003
 * This contract will serve as the central hub for user interactions in our ecosystem
 * Primary responsibilities include
 * 1. Receiving ETH Deposits from users : Users will send ETH to the Vault
 * 2. Issuing Rebase Tokens : Upon deposit, the vault mints Rebase Tokens to the user
 * 3. Users will be able to redeem their Rebase tokens through Vault to reclaim their ETH
 * 4. The Vault is designed to recieve ETH rewards which will later be distributed among token holders
 * Finally this Vault acts as a secure deposit box for users ETH and a distribution hub for rewards handling all the minting and burning tokens
 * Core Functionalities included
 * 1. Store address of rebase token
 * 2. Implements deposit function (Accepts ETH from user and mints the Rebase tokens)
 * 3. Implements redeem function (Burns the user's Rebase tokens and transfer the ETH to the user)
 * 4. Implement a mechanism to add ETH rewards to the vault
 */

contract Vault {
    // immutables
    IRebaseToken private immutable i_rebaseToken;

    constructor(IRebaseToken _rebaseTokenAddress) {
        i_rebaseToken = _rebaseTokenAddress;
    }

    // external functions

    /**
     * This function is a fallback function that is triggered when ETH is sent to the contract
     * Any ETH sent this way simply increases the contract balance
     * This can be considered as a part of rewards pool
     */
    receive() external payable {}

    /**
     * This function allows user to deposit ETH into the valut and receive an equvalent amount of RebaseTokens
     * The amount of ETH sent with the transaction determines the amount of tokens minted
     * Protocol assumes 1:1 peg for 1WEI of ETH to 1 RebaseToken
     */

    function deposit() external payable {
        uint256 amountToMint = msg.value;
        if (amountToMint == 0) {
            revert Vault__AmountMustBeGreaterThanZero();
        }
        i_rebaseToken.mint(msg.sender, amountToMint);
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @param _amount The amount of tokens to burn
     * This function burns the amount of tokens and transfers the corresponding ETH to the user
     * Using low level functions for transfer of ETH for gas efficiency
     */

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}(""); // using low level call to send ETH for gas efficiency
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    // external getter functions
    /**
     * @notice Returns the address of the rebase token associated with this vault
     */

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    // events
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    // errors
    error Vault__RedeemFailed();
    error Vault__AmountMustBeGreaterThanZero();
}
