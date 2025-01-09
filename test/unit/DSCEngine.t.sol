// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MintDSCFails.sol";
import {MockFailedTransfer} from "../mocks/TransferFails.sol";
import {MockFailedTransferFrom} from "../mocks/TransferFromFails.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    ERC20Mock wethMock;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    address public user = makeAddr("user");
    address[] public tokenAddress;
    address[] public priceFeedsAddresses;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    event CollateralRedeemed(
        address indexed RedeemedFrom, address indexed RedeemedTo, address indexed tokenCollateralAddress, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        tokenAddress = [weth, wbtc];
        priceFeedsAddresses = [ethUsdPriceFeed, btcUsdPriceFeed];
    }

    //////////////////////
    ///constructor feed///
    /////////////////////

    address[] tokenAddresses;
    address[] priceFeeds;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeeds.push(ethUsdPriceFeed);
        priceFeeds.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSC_TokenAddressesAndPriceFeedAddressesMustBeEqual.selector);
        new DSCEngine(tokenAddresses, priceFeeds, address(dsc));
    }

    ////////////////
    ///price feed///
    ////////////////

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expected = 30000e18;
        uint256 actualEthValue = dscEngine.getUSDValue(weth, ethAmount);
        assertEq(expected, actualEthValue, "Not equal!");
    }

    function testGetTokenAmountfromUSD() public view {
        uint256 usdAmount = 100 ether;
        uint256 expected = 0.05 ether;
        uint256 actual = dscEngine.getTokenAmountfromUSD(weth, usdAmount);
        assertEq(expected, actual);
    }

    ////////////////////////
    ///deposit collateral///
    ////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfNotAllowedToken() public {
        ERC20Mock randToken = new ERC20Mock();
        randToken.mint(user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral((weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCminted, uint256 collateralValueInUSD) = dscEngine.getAccountInfo(user);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountfromUSD(weth, collateralValueInUSD);
        assertEq(totalDSCminted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        assertEq(dsc.balanceOf(user), 0);
    }

    // write on your own.

    function testHealthFactorIsFineIfNoDSCMinted() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 colleteralValueInUSD) = dscEngine.getAccountInfo(user);
        uint256 healthFactorVal = dscEngine.calculateHealthFactor(totalDSCMinted, colleteralValueInUSD);
        assert(healthFactorVal >= dscEngine.getMinimumHealthFactor());
    }
    ///////////////////////
    //// deposit  /////////
    //// mint dsc /////////
    ///////////////////////

    function testIfDepositandMintingBreaksHealthFactor() public {
        (, int256 priceEth,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(priceEth) * dscEngine.getAdditionalFeedPrecision()))
            / dscEngine.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralandMintDSC() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintwithDepositCollateral() public depositedCollateralandMintDSC {
        uint256 userbalance = dsc.balanceOf(user);
        assertEq(AMOUNT_MINT, userbalance);
    }

    ///////////////////////
    //// mint dsc /////////
    ///////////////////////

    function testMintingFailsIfNoCollateral() public {
        vm.startPrank(user);
        uint256 expectedHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDSC(AMOUNT_MINT);
        vm.stopPrank();
    }

    function testMintingDSCFailsForZero() public {
        vm.startPrank(user);
        uint256 amountMint = 0;
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.mintDSC(amountMint);
        vm.stopPrank();
    }

    function testRevertsIfMintingFails() public {
        // unique setup to test mint fails from DecentralisedStableCoin.sol
        address tempUser = vm.addr(deployerKey);
        MockFailedMintDSC mockDSC = new MockFailedMintDSC(tempUser);
        vm.startBroadcast(tempUser);
        DSCEngine dscE = new DSCEngine(tokenAddress, priceFeedsAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(dscE));
        vm.stopBroadcast();
        //
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
        dscE.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
    }

    function testCanMintDSCalone() public depositedCollateral {
        uint256 initialBalance = dsc.balanceOf(user);
        vm.startPrank(user);
        dscEngine.mintDSC(AMOUNT_MINT);
        vm.stopPrank();
        uint256 expectedBalance = initialBalance + AMOUNT_MINT;
        uint256 actualBalance = dsc.balanceOf(user);

        assertEq(expectedBalance, actualBalance, "Not succesfully Minted");
    }

    ///////////////////////////////
    /// redeem collateral tests ///
    ///////////////////////////////

    function testRevertsIfRedeemCollateralAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testIfCollateralSuccesfullyRedeemed() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL / 2);
        vm.stopPrank();
    }

    function testStateUpdateIfCollateralRedeemed() public depositedCollateral {
        uint256 initialCollateralDeposited = AMOUNT_COLLATERAL;
        uint256 amountCollateralRedeemed = AMOUNT_COLLATERAL / 2;
        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, amountCollateralRedeemed);
        vm.stopPrank();

        uint256 collateralDepositedAfterRedeemed = dscEngine.getCollateralDepositedByUser(user, weth);
        uint256 expectedCollateralDepositedAfterRedeemed = initialCollateralDeposited - amountCollateralRedeemed;
        assertEq(collateralDepositedAfterRedeemed, expectedCollateralDepositedAfterRedeemed);
    }

    function testRevertsIfTransferFromFails() public {
        address tempUser = vm.addr(deployerKey);
        vm.startBroadcast(tempUser);
        MockFailedTransfer mockDSC = new MockFailedTransfer(tempUser);
        tokenAddress = [address(mockDSC)];
        priceFeedsAddresses = [ethUsdPriceFeed];
        DSCEngine mockdscE = new DSCEngine(tokenAddress, priceFeedsAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockdscE));
        vm.stopBroadcast();

        vm.startPrank(user);
        ERC20Mock(address(mockDSC)).mint(user, 100 ether);
        ERC20Mock(address(mockDSC)).approve(address(mockdscE), AMOUNT_COLLATERAL);
        mockdscE.depositCollateral(address(mockDSC), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        mockdscE.redeemCollateral(address(mockDSC), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testHealthFactorBreaksAfterReedemingCollateralUponMinting() public depositedCollateralandMintDSC {
        vm.startPrank(user);
        uint256 expectedHealthFactor = 0; // if all collateral redeemed
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCorrectArgsOfTheEvent() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(user, user, weth, AMOUNT_COLLATERAL);

        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    ///////////////////
    //// burnDSC //////
    ///////////////////

    function testNotBurningZeroDSC() public depositedCollateralandMintDSC {
        uint256 amountBurnDSC = 0;
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.burnDSC(amountBurnDSC);
        vm.stopPrank();
    }

    function testBurnDSCSuccessful() public depositedCollateralandMintDSC {
        uint256 amountDSCtoBurn = 5 ether;
        vm.startPrank(user);
        ERC20Mock(address(dsc)).approve(address(dscEngine), amountDSCtoBurn);
        dscEngine.burnDSC(amountDSCtoBurn);
        vm.stopPrank();
    }

    function testStateUpdatedUponSuccessfulBurn() public depositedCollateralandMintDSC {
        uint256 amountDSCbeforeBurning = dscEngine.getDSCMintedByAUser(user);
        uint256 amountToBurn = 5 ether;

        vm.startPrank(user);
        ERC20Mock(address(dsc)).approve(address(dscEngine), amountToBurn);
        dscEngine.burnDSC(amountToBurn);
        vm.stopPrank();

        uint256 expectedDSCAmount = amountDSCbeforeBurning - amountToBurn;
        uint256 actualDSC = dscEngine.getDSCMintedByAUser(user);

        assertEq(expectedDSCAmount, actualDSC);
    }

    function testburnDSCRevertsIfTransferFromFails() public {
        //setUp
        address tempUser = vm.addr(deployerKey);
        MockFailedTransferFrom mockDSC = new MockFailedTransferFrom(tempUser);
        vm.startBroadcast(tempUser);
        DSCEngine mockDSCEngine = new DSCEngine(tokenAddress, priceFeedsAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockDSCEngine));
        vm.stopBroadcast();

        //actual test
        vm.startPrank(user);
        // setting up deposit and mint
        ERC20Mock(weth).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);
        mockDSCEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);

        // trying to burn dsc now
        uint256 amountDSCToBurn = 10 ether;
        ERC20Mock(address(mockDSC)).approve(address(mockDSCEngine), amountDSCToBurn);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        mockDSCEngine.burnDSC(amountDSCToBurn);
        vm.stopPrank();
    }

    /////////////////////////////////
    /// redeem collateral for dsc ///
    /////////////////////////////////

    function testMinteDDSCUpdatesAfterBurning() public depositedCollateralandMintDSC {
        vm.startPrank(user);
        uint256 dscMintedbeforeBurning = dscEngine.getDSCMintedByAUser(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        dscEngine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        uint256 dscMintedAfterBurning = dscEngine.getDSCMintedByAUser(weth);
        vm.stopPrank();
        assertEq(dscMintedbeforeBurning - AMOUNT_MINT, dscMintedAfterBurning);
    }

    function testIfBurningandRedeemingBreaksHealthFactor() public depositedCollateralandMintDSC {
        vm.startPrank(user);

        uint256 amounToRedeem = AMOUNT_COLLATERAL;
        uint256 amountToBurn = AMOUNT_MINT / 10;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(AMOUNT_MINT - amountToBurn, 0);

        ERC20Mock(address(dsc)).approve(address(dscEngine), amountToBurn);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.redeemCollateralForDSC(weth, amounToRedeem, amountToBurn);

        vm.stopPrank();
    }

    ///////////////////////
    /// liquidate tests ///
    ///////////////////////

    function testNotTryingToCoverZeroDebt() public depositedCollateralandMintDSC {
        address newUser = makeAddr("newUser");

        vm.startPrank(newUser);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
        vm.stopPrank();
    }

    function testNotLiquidatingAUserWithGoodHealthFactor() public depositedCollateralandMintDSC {
        address newUser = makeAddr("newUser");

        vm.startPrank(newUser);
        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorFine.selector);
        dscEngine.liquidate(weth, user, 5 ether);
        vm.stopPrank();
    }

    // more liquidation tests pending
}
