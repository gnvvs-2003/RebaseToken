// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {
    RegistryModuleOwnerCustom
} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChain is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;
    Vault vault;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    address owner = makeAddr("owner");

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // deploy and configure on sepolia

        vm.selectFork(sepoliaFork);
        /// 1. deploy the rebase token
        sepoliaToken = new RebaseToken();
        /// 2. create or deploy the vault for source chain i.e sepolia token
        vault = new Vault(IRebaseToken(address(sepoliaToken))); // vault only needed on the source chain
        /// 3. prank as owner
        vm.startPrank(owner);
        /// 4. get the network details for token pool
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        /// 5. register the admin for sepolia token (via owner)
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        /// 6. accept the admin role
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        /// 7. deploy the token pool
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        /// 8. connect the pool and token i.e sepolia token and sepolia token pool
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaTokenPool));
        /// 9. grant the mint and burn role to the sepolia token pool
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));
        vm.stopPrank();

        // deploy and configure on arbitrum sepolia (ALL THE PROCESS IS SAME EXCEPT THERE IS NO VAULT FOR THE DESTINATION CHAIN)
        vm.selectFork(arbSepoliaFork);
        /// 1. deploy the rebase token
        arbSepoliaToken = new RebaseToken();
        vm.startPrank(owner);
        /// 2. get the network details for token pool
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        /// 3. register the admin for arbitrum sepolia token (via owner)
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        /// 4. accept the admin role
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        /// 5. deploy the token pool
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        /// 6. connect the pool and token i.e arbitrum sepolia token and arbitrum sepolia token pool
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaTokenPool));
        /// 7. grant the mint and burn role to the arbitrum sepolia token pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));
        vm.stopPrank();

        /// CONFIGURING SEPOLIA POOL TO INTERACT WITH ARBITRUM SEPOLIA POOL
        configureTokenPool(
            sepoliaFork,
            address(sepoliaTokenPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaTokenPool),
            address(arbSepoliaToken)
        );
        /// CONFIGURING ARBITRUM SEPOLIA POOL TO INTERACT WITH SEPOLIA POOL
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaTokenPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaTokenPool),
            address(sepoliaToken)
        );
    }

    /**
     * @notice This function connects the chains together
     * @param forkId The fork ID of the chain you are configuring
     * @param localPoolAddress address of token pool on the current chain (sepoliaTokenPool,arbSepoliaTokenPool)
     * @param remoteChainSelector CCIP chain selector of the destination chain
     * @param remotePoolAddress Token pool contract deployed on the destination chain (arbSepoliaTokenPool for sepolia,sepoliaTokenPool for arbitrum sepolia)
     * @param remoteTokenAddress Token contract deployed on the destination chain (arbSepoliaToken for sepolia,sepoliaToken for arbitrum sepolia)
     */

    function configureTokenPool(
        uint256 forkId, // The fork ID of the local chain
        address localPoolAddress, // Address of the pool being configured
        uint64 remoteChainSelector, // Chain selector of the remote chain
        address remotePoolAddress, // Address of the pool on the remote chain
        address remoteTokenAddress // Address of the token on the remote chain
    ) public {
        /// 1. Select the chain to configure
        vm.selectFork(forkId);
        /// 2. No existing chains to be removed => empty array
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        /// 3. Adding the remote chain details => Adding one remote chain
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        /// 4. Encoding the remote pool address
        bytes[] memory remotePoolAddressesBytesArray = new bytes[](1);
        remotePoolAddressesBytesArray[0] = abi.encode(remotePoolAddress);
        /// 5. Adding the remote chain details to the chainsToAdd array
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddressesBytesArray,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        /// 6. Calling the applyChainUpdates function to update the chain details cuz it is a owner only function (Pool owner)
        vm.prank(owner); // The 'owner' variable should be the deployer/owner of the localPoolAddress
        /// 7. Calling the applyChainUpdates function to update the chain details
        TokenPool(localPoolAddress).applyChainUpdates(remoteChainSelectorsToRemove, chainsToAdd);
    }
}
