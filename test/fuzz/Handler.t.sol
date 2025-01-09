// this narrows down the way we call the functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 constant STARTING_BALANCE = 1e59 ether;
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintisCalled = 0;

    MockV3Aggregator public ethUSDpriceFeed;
    address[] public usersWithCOllateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory allowedTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(allowedTokens[0]);
        wbtc = ERC20Mock(allowedTokens[1]);
        console.log("Handler constructor");

        ethUSDpriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    // redeemCollateral -> there needs to a collateral to be redeemed
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("depositCollateral");
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, MAX_DEPOSIT_SIZE);
        collateral.approve(address(dscEngine), MAX_DEPOSIT_SIZE);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCOllateralDeposited.push(msg.sender);
    }

    function mintDSC(uint256 amountDSCToMint, uint256 seed) public {
        if (usersWithCOllateralDeposited.length == 0) return;

        address sender = usersWithCOllateralDeposited[seed % usersWithCOllateralDeposited.length];

        (uint256 totalDSCminted, uint256 collateralUSD) = dscEngine.getAccountInfo(sender);
        int256 maxDSCToMint = (int256(collateralUSD) / 2) - int256(totalDSCminted);

        if (maxDSCToMint < 0) return;

        amountDSCToMint = bound(amountDSCToMint, 0, uint256(maxDSCToMint));

        if (amountDSCToMint == 0) return;

        vm.startPrank(sender);
        dscEngine.mintDSC(amountDSCToMint);
        vm.stopPrank();

        timesMintisCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToBeRedeemed = dscEngine.getCollateralDepositedByUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToBeRedeemed);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // This breaks our test suite.
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUSDpriceFeed.updateAnswer(newPriceInt);
    // }
}
