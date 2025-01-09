// have our invariants/properties of the system that must hold

//what are our invariants ?
// 1. total supply of dsc should be less than the total value of collateral
// 2. getter view functions should never revert

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../fuzz/Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    DeployDSC deployer;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        console.log("setUP() completed");
        targetContract(address(handler));

        // dont call redeemCollateral unless there is something to redeem
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get value of all the collateral in the protocol
        console.log("test completed");
        //compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUSDValue(weth, wethDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, wbtcDeposited);

        console.log("Total Supply : ", totalSupply);
        console.log("wBTC Value : ", wethValue);
        console.log("wETH Value : ", wbtcValue);
        console.log("Times mint is called : ", handler.timesMintisCalled());
        assert(wethValue + wbtcValue >= totalSupply);
    }
    // function make invariants for getters to check they dont revert
}
