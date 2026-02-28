// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress, // Address receiving tokens on the destination chain
        uint64 destinationChainSelector, // CCIP selector for the destination chain
        address tokenToSendAddress, // Address of the ERC20 token being bridged
        uint256 amountToSend, // Amount of the token to bridge
        address linkTokenAddress, // Address of the LINK token (for fees) on the source chain
        address routerAddress // Address of the CCIP Router on the source chain
    ) public {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        vm.startBroadcast();
        /// message to send
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        /// ccip fee required to send the message
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        /// approve the router to spend the fee token
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        /// approve the router to spend the token to send
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        /// send the message
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
