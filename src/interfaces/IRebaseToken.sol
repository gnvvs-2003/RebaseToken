// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRebaseToken
 * @author gnvvs-2003
 * @notice This interface is used to interact with the RebaseToken contract
 * It is used to mint and burn tokens
 */

interface IRebaseToken {
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getUserInterestRate(address _user) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
}
