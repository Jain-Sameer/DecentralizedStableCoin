// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {console} from "../lib/forge-std/src/Test.sol";
/**
 * @title DecentralisedStableCoin
 * @author Sameer Jain
 * Collateral : Exogenous (ETH and BTC)
 * Relative Stability : Pegged to USD
 *
 * this is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system
 */

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin_MustBeMoreThanZero();
    error DecentralisedStableCoin_BurnAmountExceedsBalance();
    error DecentralisedStableCoin_MustBeNotZeroAddress();

    constructor(address _address) ERC20("DecentralisedStableCoin", "DSC") Ownable(_address) {}

    function GreaterThanZero(uint256 _amount) internal pure {
        if (_amount <= 0) {
            revert DecentralisedStableCoin_MustBeMoreThanZero();
        }
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        GreaterThanZero(_amount);
        if (balance < _amount) {
            revert DecentralisedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount); // super -> uses the burn function from the parent class/contract which is ERC20burnable
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin_MustBeNotZeroAddress();
        }
        GreaterThanZero(_amount);
        _mint(_to, _amount);
        return true;
    }
}
