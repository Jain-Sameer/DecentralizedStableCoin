// // have our invariants/properties of the system that must hold

// //what are our invariants ?
// // 1. total supply of dsc should be less than the total value of collateral
// // 2. getter view functions should never revert

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Test, console} from "../../lib/forge-std/src/Test.sol";
// import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract InvariantsTest is StdInvariant, Test {
//     DSCEngine dscEngine;
//     DecentralisedStableCoin dsc;
//     HelperConfig config;
//     DeployDSC deployer;
//     address weth;
//     address wbtc;
//     function setUp () external {
//         deployer = new DeployDSC();
//         (dsc, dscEngine, config) = deployer.run();
//         (, , weth, wbtc, ) = config.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         //get value of all the collateral in the protocol
//         //compare it to all the debt (dsc)
//         console.log("does it reach here ?");
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 wethDeposited = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

//         uint256 wethValue = dscEngine.getUSDValue(weth, wethDeposited);
//         uint256 wbtcValue = dscEngine.getUSDValue(wbtc, wbtcDeposited);

//         assert(wethValue+wbtcValue >= totalSupply);
//     }
// }
