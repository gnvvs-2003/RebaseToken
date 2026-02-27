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
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
// import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChain is Test {
    uint256 SEND_VALUE = 1e5;
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
    address user = makeAddr("user");

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // deploy and configure on sepolia

        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        /// 1. deploy the rebase token
        sepoliaToken = new RebaseToken();
        /// 2. create or deploy the vault for source chain i.e sepolia token
        vault = new Vault(IRebaseToken(address(sepoliaToken))); // vault only needed on the source chain
        /// 3. get the network details for token pool
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        /// 4. register the admin for sepolia token (via owner)
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
        /// 8. grant the mint and burn role to the sepolia token pool
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));
        /// 9. Grant the mint and burn role to the vault
        sepoliaToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();

        // deploy and configure on arbitrum sepolia (ALL THE PROCESS IS SAME EXCEPT THERE IS NO VAULT FOR THE DESTINATION CHAIN)
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        /// 1. deploy the rebase token
        arbSepoliaToken = new RebaseToken();
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

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        /// 1. initialize tokens amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        /// 2. Add local token
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        /// 3. Construct the message (CCIP message)
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // receiver on destination chain
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false})) // Using default gas limit not 0 gas
        });
        /// 4. Fee for cross chain operations
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        /// 5. Funding the fee for user
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);
        /// 6. Approving link for router to spend fee to be done by user
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        /// 7. Approve the bridged token to be done by user
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        /// 8. User balance before sending in the local chain
        uint256 localBalanceBefore = localToken.balanceOf(user);
        /// 9. Send the CCIP message
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        /// 10. User balance after sending in the local chain
        uint256 localBalanceAfter = localToken.balanceOf(user);
        /// 11. Assert that the user balance has decreased by the amount to bridge
        assertEq(localBalanceBefore - localBalanceAfter, amountToBridge);
        /// 12. Interest rate of user in local chain
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        /// 13. User balance on the remote chain before receiving
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);

        vm.selectFork(localFork);
        /// 14. Process the message to remote chain (MUST BE DONE ON SOURCE CHAIN)
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        vm.selectFork(remoteFork);
        /// 15. Simulate some time to pass and transfer
        vm.warp(block.timestamp + 20 minutes);
        /// 16. User balance after receiving on the remote chain
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        /// 17. Assert that the user balance has increased by the amount to bridge (approximate due to interest)
        assertApproxEqAbs(remoteBalanceAfter - remoteBalanceBefore, amountToBridge, 10);
        /// 18. Check the interest rates (Specific to rebase token logic) in remote chain
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }

    // testing
    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        /// bridging
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbSepoliaToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
        vm.selectFork(sepoliaFork);
        assertApproxEqAbs(sepoliaToken.balanceOf(user), SEND_VALUE, 50);
    }
}
