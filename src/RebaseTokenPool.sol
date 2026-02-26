// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Pool} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/**
 * @title RebaseTokenPool
 * @author gnvvs-2003
 * @notice This contract is a token pool for the rebase token
 * This contract implements burn and mint mechanism for cross chain functionality
 * This contract direclty inherits from TokenPool contract not from the abstract contract
 */
contract RebaseTokenPool is TokenPool {
    /**
     * @notice Constructor for the RebaseTokenPool contract
     * @param _token The address of the rebase token managed by this pool
     * localTokenDecimals : The decimals of the token i.e 18
     * @param _allowList The list of addresses allowed to send tokens through this pool
     * @param _rmnProxy The address of the RMN(Risk Management Network) proxy
     * @param _router The address of the CCIP Router contract
     */
    constructor(IERC20 _token, address[] memory _allowList, address _rmnProxy, address _router)
        TokenPool(_token, 18, _allowList, _rmnProxy, _router)
    {
        // Constructor logic
    }

    // external functions

    /**
     * @param lockOrBurnIn The input data for the lock or burn operation
     * @return lockOrBurnOut The output data for the lock or burn operation
     * @notice This function is used to lock or burn tokens on the source chain
     */

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn); // validation
        // address originalSender = abi.decode(
        //     lockOrBurnIn.originalSender,
        //     (address)
        // ); // decode the orginal sender address
        uint256 uerInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender); // get the user interest rate
        /// CCIP transfers tokens to the pool before lockOrBurn function is called
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount); // burn the tokens from the pool contract
        /// Prepare the output data for CCIP
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector), // get the remote token address
            destPoolData: abi.encode(uerInterestRate) // encode the interest rate to send cross chain
        });
    }

    /**
     * @param releaseOrMintIn The input data for the release or mint operation
     * @return releaseOrMintOut The output data for the release or mint operation
     * @notice This function is used to release or mint tokens on the destination chain
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn); // validation
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256)); // decode the interest rate
        address receiver = releaseOrMintIn.receiver;
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount, userInterestRate);
        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
