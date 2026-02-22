# Working principle of our Rebase Token
1. user 1 deposits some ETH into the vault contract 
2. mints the equal amount of rebase tokens
3. user 1 gets a initial interest rate of 0.05%(example) set by the owner
4. If the golbal value decreases then the owner can decrease the intrest rate (say decrease by 0.01%)
5. Now the intrest rate will be 0.04% for upcomming users and user 1 still gets 0.05% interest
6. If user2 deposits some ETH into the vault contract then user 2 will get the interest rate of 0.04%
7. Let say owner makes the interest rate 0.03% then the new users will get 0.03% interest and user 1(0.05%) and user 2(0.04%) still gets their respective interest rates

# TODO
1. A protocol that allows user to deposit ETH into a vault and in return ,recieve rebase tokens that represents their underlying balance
2. Rebase Token => The balanceOf function will be dynamic since it will be changing with time 
    - Balance increases with time
    - mint tokens to user when they perform any action(minting ,burning ,transferring or `bridging`)
3. Interest Rate => 
    - Individually sets interest rate for each user based on global intrest rate 
    - This intrest rate will be decreased over time to incentivise early users
    - The intrest rate will be calculated based on the increase in token adoption

# Contract Structure

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

imports

constant variables

immutable variables 

private variables

public variables

structs 

functions

    - constructor

    - modifiers

    - external functions

    - external getter functions

    - public view functions

    - public functions

    - private functions

    - internal functions

    - events

    - errors

# Building Cross Chain Rebase token with foundry and chainlink CCIP

Building a rebase token rebase token capable of operating and being transferred across multiple chains using chainlink CCIP.

## Rebase Token 

A rebase token is a type of cryptocurrency where the total supply adjusts algorithmically 
This adjustment is distributed proportionally among all token holders.
Which implies the user token balance changes not due to direct transfrs from/to the user wallet but due to the effective quantity or vaalue represented by each token unit shifts with supply

`In our specific implementation the rebase mechanism will be tied to interest rate, making user user balance to appear to grow over time as the interest accrues to the user balance`

## Cross Chain Funtionality

The core challange here is to enable the token or atlest its value representation to move from source chain to destination chain

## Chainlink CCIP

CCIP(cross chain interoperability protocol) enables the token cross chain capabilities 
It enables or provides a secure and reliable way to transfer tokens and data or messages between different blockchains

## Burn and mint mechanism

To maintain a consistent total circulating supply across all integrated chains we will use a burn and mint mechanism when tokens are transferred from source chain to destination chain

1. Tokens are burned on the source chain -- irrecoverable 
2. An equvivalent amount of tokens are minted on the destination chain
Finally the total no of tokens across all chains remains same

The rebase token will accure interest based on a straight forward linear model i.e Linear Interest
The interest earned will be a product of the user's specific interest rate and the time elapsed since their last balance update or interaction with the contract

## Local CCIP Simulation
For the purpose of local development and testing we will be using a simulated version of chainlink CCIP

### Learning Objectives
1. Chainlink CCIP
2. Enabling an existing token for cross chain functionality i.e CCIP compatibility
3. Techniques for creating custom tokens specifically designed for CCIP going beyond ERC20 standard
4. Design and implementation of rebase tokens
5. Usage of `super` keyword
6. Testing 
7. Understanding and mitigating issues related to `token dust`
8. Handling precision and truncation challanges in financial calculations
9. Implementing unit testing, fuzz testing, integration testing, fork testing
10. Usage of nested structs
11. Mechanism of bridging tokens across chains
12. Intricacies of cross chain transfers

## Development workflow

* Deployer.s.sol: This script handles the deployment of the RebaseToken, RebaseTokenPool, and Vault contracts to the target blockchain.

* ConfigurePool.s.sol: After deployment, this script is used to configure the CCIP settings on the RebaseTokenPool contracts on each chain. This includes setting parameters like supported remote chains (using their chain selectors), addresses of token contracts on other chains, and rate limits for CCIP transfers.

* BridgeTokens.s.sol: This script provides a convenient way to initiate a cross-chain token transfer, automating the calls to the RebaseTokenPool for locking/burning and CCIP message dispatch.

* Interactions.s.sol: (Implied) This script would likely contain functions for other general interactions with the deployed contracts, such as depositing into the vault or checking balances.

## Testing mechanism

* RebaseToken.t.sol:

Purpose: Contains unit and fuzz tests specifically for the RebaseToken.sol contract.

Key Test Feature: Employs assertApproxEqAbs(value1, value2, delta) for assertions. Due to the nature of interest calculations over time and potential floating-point arithmetic nuances (even when emulated with fixed-point in Solidity), rebase calculations can lead to very minor precision differences. Using assertApproxEqAbs allows us to verify that calculated values are within an acceptable tolerance (delta) of expected values, rather than insisting on exact equality (assertEq) which might lead to spurious test failures.

* CrossChain.t.sol:

Purpose: Contains fork tests designed to validate the end-to-end cross-chain functionality.

Key Test Features:

Utilizes vm.createFork("rpc_url") to create local forks of testnets like Sepolia and Arbitrum Sepolia. This allows tests to run against a snapshot of the real chain state.

Integrates CCIPLocalSimulatorFork from Chainlink Local. This powerful tool enables the simulation of CCIP message routing and execution between these local forks, effectively creating a local, two-chain (or multi-chain) test environment.

The test setup involves initializing two (or more) forked environments to represent the source and destination chains for the cross-chain operations.

## Automating deployment and cross chain operations : `bridgeToZkSync.sh`

* To streamline the entire process from deployment to a live cross-chain transfer, a bash script like bridgeToZkSync.sh is invaluable.

* Purpose: This script automates a complex sequence of operations involving contract deployments, configurations, and interactions across multiple chains (e.g., Sepolia and zkSync Sepolia).

* Steps it typically performs:

* Sets necessary permissions for the RebaseTokenPool contract, often involving CCIP-specific roles.

* Assigns CCIP roles and configures permissions for inter-chain communication.

* Deploys the core contracts (RebaseToken, RebaseTokenPool, Vault) to a source chain (e.g., Sepolia) using script/Deployer.s.sol.

* Parses the deployment output to extract the addresses of the newly deployed contracts.

* Deploys the Vault (and potentially RebaseToken and RebaseTokenPool if not already deployed as part of a unified script) on the destination chain (e.g., zkSync Sepolia).

* Configures the RebaseTokenPool on the source chain (Sepolia) using script/ConfigurePool.s.sol, linking it to the destination chain by setting remote chain selectors, token addresses on the destination chain, and CCIP rate limits.

* Simulates user interaction by depositing funds (e.g., ETH) into the Vault on Sepolia, thereby minting rebase tokens.

* Includes a pause or wait period to allow some interest to accrue on the rebase tokens.

* Configures the RebaseTokenPool on the destination chain (zkSync Sepolia), establishing the reciprocal CCIP linkage.

* Initiates a cross-chain transfer of the rebase tokens from Sepolia to zkSync Sepolia using script/BridgeTokens.s.sol.

* Performs balance checks on both chains before and after the bridge operation to verify the successful transfer and correct accounting.

### Example Use Case 
1. Deploy the `RebaseToken` ,`RebaseTokenPool` ,`Vault` contracts to a source chain (e.g., Sepolia) using script/Deployer.s.sol.
2. Cross chain deployment : Deploy the corresponding smart contracts onto a second testnet such as `ZkSync Sepolia`
3. CCIP configuration : Configure the chainlink CCIP between deployed contratcs on `sepolia` and `ZkSync Sepolia`
4. Acquire rebase tokens : Deposit ETH into the `Vault` contract on `sepolia`, therby receiving an initial balance of rebase tokens
5. Interest Accrual : Observe as the rebase token balance in the sepolia wallet increases over time, reflecting the accrure interest as per the tokens rebase mechanism
6. Cross chain transfer Execute the `BridgeTokens.s.sol` Foundry script
* Instruct the RebaseTokenPool on Sepolia to burn a specified amount of the user's rebase tokens.
* Initiate a CCIP message to the RebaseTokenPool on zkSync Sepolia.
* Upon successful CCIP message relay, the RebaseTokenPool on zkSync Sepolia will mint an equivalent amount of rebase tokens to the user's address on that chain.
7. Verification : Verify that the rebase token balance on zkSync Sepolia has increased by the expected amount.

## Type Casting for Interoperability
- When a contract instance needs to be passed as an interface type : `InterfaceType(address(contractInstance))`
- When a contract instance needs to be passed as an address type : `address(contractInstance)`
- When sending ETH via a low level call the target address must be cast to payable i.e `payable(address)`

## Testing 
forge runs tests written in solidity. Test file reside in `test/` directory and are prefixed with `test`

Forge supports the following types of testing:

1. unit testing
2. fuzz testing
3. Invariant Testing
4. Revert Testing
5. Access Control Testing
6. Event Testing
7. Gas Testing
8. Fork Testing
9. Integration Testing
10. Property based Testing

### UNIT Testing : Testing individual functions in isolation

Sample Contract 
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public number;

    function increment() public {
        number++;
    }

    function setNumber(uint256 _num) public {
        number = _num;
    }
}
```

Testfile

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test {
    Counter counter;

    function setUp() public {
        counter = new Counter();
    }

    function testIncrement() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testSetNumber() public {
        counter.setNumber(10);
        assertEq(counter.number(), 10);
    }
}
```

### FUZZ Testing : Automatic Random Testing (Tests function when it has parameters)

```solidity
function testFuzzSetNumber(uint256 _num) public{
    counter.setNumber(_num);
    assertEq(counter.number(), _num);
}
```

- Generates random uint256
- Runs test multiple times
- Finds edge cases

> Restricting Fuzz Inputs : `vm.assume()` filters invalid fuzz inputs
```solidity
function testFuzzSetNumber(uint256 _num) public{
    vm.assume(_num < 1e18);
    counter.setNumber(_num);
    assertEq(counter.number(), _num);
}
```

### INVARIANT Testing : Testing invariants(i.e properties which will always be true for the entire contract)

Starts with `invariant` prefix

```solidity
function invariant_NumberIsAlwaysPositive() public{
    assert(counter.number() >= 0);
}
```

This test randomly calls `setNumber` and `increment` i.e contract functions and checks the invariant after each call

### REVERT Testing : Testing if the function reverts when expected
Testing failure cases 

```solidity
function testRevert_WhenInvalid() public{
    vm.expectRevert();
    counter.setNumber(type(uint256).max+1);
}
```

This function checks if the `setNumber` function reverts when the input is greater than `type(uint256).max` 

### ACCESS CONTROL Testing : Testing access control

```solidity
address owner = makeAddr("owner");
address user = makeAddr("user");

function testOnlyOwnerCanCallFunction() public{
    vm.prank(user);
    vm.expectRevert();
    contract.onlyOwnerFunction();
}
```

### EVENT Testing : Verify emitted events

```solidity
event NumberSet(uint256 newNumber);
```

- Testfile

```solidity
function testEventNumberSet() public{
    vm.expectEmit(true,false,false,true);
    emit NumberSet(10);
    counter.setNumber(10);
}
```

### GAS Testing : Measures gas usage

```bash
forge test --gas-report
```

