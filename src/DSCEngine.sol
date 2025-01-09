// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {console} from "forge-std/Test.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Sameer
 *
 * The system is designed to be as minimal as possible, and have the tokens maintains a 1 token == 1$ peg.\
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is very loosely based on DAI System.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////
    // Errors////
    /////////////

    error DSCEngine_NeedsMoreThanZero();
    error DSC_TokenAddressesAndPriceFeedAddressesMustBeEqual();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_HealthFactorFine();
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorNotFine();

    /////////////
    // Types ////
    /////////////
    using OracleLib for AggregatorV3Interface;

    /////////////
    //State Vars////
    /////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant HEALTH_FACTOR_PRECISION = 10;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_dscMinted;
    address[] private s_collateralToken;

    DecentralisedStableCoin private immutable i_dsc;
    /////////////
    //Events////
    /////////////

    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amount);
    event CollateralRedeemed(
        address indexed RedeemedFrom, address indexed RedeemedTo, address indexed tokenCollateralAddress, uint256 amount
    );

    /////////////
    // Modifier//
    /////////////

    modifier notZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    /////////////
    //Functions//
    /////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSC_TokenAddressesAndPriceFeedAddressesMustBeEqual();
        }
        // ETH/USD, BTC/USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralToken.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    //////////////////
    //Ext. Functions//
    //////////////////
    /**
     * @param tokenCollateralAddress address of token to deposit as collateral
     * @param amountCollateral amount of collateral to deposit
     * @param amountDSCToMint amount of dsc to get against the deposited collateral
     * @notice Function deposits collateral and mints the dsc in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice CEI checks, effects, interactions
     * @param tokenCollateralAddress the address of the token to be selected as collateral
     * @param amountCollateral the amount of the said token to be deposited as the collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        console.log(tokenCollateralAddress);
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress btc, eth ? whatever collateral submitted
     * @param amountCollateral amountofCollateral to burn
     * @param amountDSC amount of DSC to burn and get levied of the debt
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSC)
        external
    {
        burnDSC(amountDSC);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeem collateral checks for health factor
    }

    //in order to redeem collateral
    // 1. health factor must be over 1 after collateral pulled
    // DRY : Dont repeat yourself
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        nonReentrant
    {   
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsbroken(msg.sender);
    }

    // 1. check if collateral value is > DSC amount. Price Feeds, values,etc.abi

    function mintDSC(uint256 amountDSCToMint) public notZero(amountDSCToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsbroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDSC(uint256 amount) public notZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsbroken(msg.sender);
    }

    // If someone is almost undercollaretalised, we will pay you to liquidate them!

    /**
     *
     * @param collateral the erc20 collateral address to liquiodate from the user
     * @param user the user who has the broken the health factor. their hf should be below minimum hf
     * @param debtToCover amount of DSC to burn to imporve the users health factor
     * @notice you can partially liquidate a user
     * @notice you will get a liquidation bonus for taking the users funds
     * @notice function working assumes that the protocol will be overcollateralised always to give out bonuses and in order to work
     * @notice a known bug would be if the protocol were 100% or less collateralised, hten we wont be able to give out liquidation bonuses
     * for eg if the price of the collateral plummeted before anyone could be liquidted
     * Follows CEI - checks effects interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        notZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorFine();
        }
        // burn the dsc debt
        // take their collateral

        // 140 dollars eth -> 100 dollars dsc
        // debt to cover = 100
        uint256 tokenAmountFromDebtCovered = getTokenAmountfromUSD(collateral, debtToCover);
        //give them a bonus , say 10 % bonus ,

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        //burn dsc

        _burnDSC(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotFine();
        }
        _revertIfHealthFactorIsbroken(msg.sender);
    }

    //////////////////
    //Internal Private Functions//
    //////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 colleteralValueInUSD)
    {
        totalDSCMinted = s_dscMinted[user];
        colleteralValueInUSD = getAccountCollateralValue(user);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
    /**
     * returns how close to liquidation the user is
     */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // return (collateralValueInUsd/totalDSCMinted);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsbroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR * PRECISION) {
            revert DSCEngine_BreaksHealthFactor(healthFactor);
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        console.log(amountCollateral);
        console.log(s_collateralDeposited[from][tokenCollateralAddress]);
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    //////////////////
    //Public External View Functions//
    //////////////////
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through each collateral token, get the amount they have deposited and map it to the price to get USD value.
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount); // returns automatically
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //price will be a the price of the corresponsing amount of the token * 1e8
        // return price * amount ; // (price*1e8*1e10) * 1000 * 1e18 balacne the precision

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountfromUSD(address token, uint256 usdAmountinwei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (usdAmountinwei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInfo(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 colleteralValueInUSD)
    {
        (totalDSCMinted, colleteralValueInUSD) = _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getMinimumHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralDepositedByUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getDSCMintedByAUser(address user) external view returns (uint256) {
        return s_dscMinted[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralToken;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
