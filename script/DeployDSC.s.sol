// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    // address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wETHusdPriceFeed, address wBTCusdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wETHusdPriceFeed, wBTCusdPriceFeed];
        address addr = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        DecentralisedStableCoin dsc = new DecentralisedStableCoin(addr);
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine, config);
    }
}
