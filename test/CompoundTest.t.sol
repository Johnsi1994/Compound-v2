// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/compound/CErc20.sol";
import "../src/compound/Comptroller.sol";
import "../src/compound/SimplePriceOracle.sol";
import "../src/compound/WhitePaperInterestRateModel.sol";
import "../src/erc20/MyERC20.sol";
import "../src/compound/CErc20Immutable.sol";

contract CompoundTest is Test {
    MyERC20 public tokenA;
    CErc20 public cTokenA;
    Comptroller public comptroller;
    SimplePriceOracle public priceOracle;
    WhitePaperInterestRateModel public interestRateModel;

    uint private constant MINT_AMOUNT = 100;

    function setUp() public {
        tokenA = new MyERC20("TokenA", "TKA", 1e18);

        comptroller = new Comptroller();
        priceOracle = new SimplePriceOracle();
        interestRateModel = new WhitePaperInterestRateModel(0, 0);

        // set simplePriceOracle as price oracle
        comptroller._setPriceOracle(priceOracle);

        cTokenA = new CErc20Immutable(
            address(tokenA),
            comptroller,
            interestRateModel,
            1e18,
            "cTokenA",
            "cTKA",
            18,
            payable(address(this))
        );

        // add cTokenA to supportMarket
        comptroller._supportMarket(cTokenA);
    }

    function test_assert_mint_success() public {
        mint();

        // cErc20's erc20A increase
        assertEq(tokenA.balanceOf(address(cTokenA)), MINT_AMOUNT);

        // owner's cErc20A increase
        assertEq(cTokenA.balanceOf(address(this)), MINT_AMOUNT);
    }

    function test_assert_redeem_success() public {
        redeem();

        // cErc20's erc20A is 0
        assertEq(tokenA.balanceOf(address(cTokenA)), 0);

        // owner's cErc20A is 0
        assertEq(cTokenA.balanceOf(address(this)), 0);
    }

    function mint() private {
        // to approve cErc20 address, cuz we will do transferFrom when mint cErc20
        tokenA.approve(address(cTokenA), MINT_AMOUNT);

        // mint cErc20
        // there are 2 steps in this mint action: do transferFrom in erc20 first, and then mint cErc20
        cTokenA.mint(MINT_AMOUNT);
    }

    function redeem() private {
        // do mint
        mint();

        // do redeem
        // there are 2 steps in this redeem action: to decrease cErc20 first, then do transfer in erc20
        cTokenA.redeem(MINT_AMOUNT);
    }

}
