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
    MyERC20 public tokenB;
    CErc20 public cTokenB;
    Comptroller public comptroller;
    SimplePriceOracle public priceOracle;
    WhitePaperInterestRateModel public interestRateModel;

    uint private constant MINT_AMOUNT = 100;

    function setUp() public {
        comptroller = new Comptroller();
        priceOracle = new SimplePriceOracle();
        interestRateModel = new WhitePaperInterestRateModel(0, 0);

        // set simplePriceOracle as price oracle
        comptroller._setPriceOracle(priceOracle);


    }

    function test_assert_mint_success() public {
        createTokenA();
        mint();

        // cErc20's erc20A increase
        assertEq(tokenA.balanceOf(address(cTokenA)), MINT_AMOUNT);

        // owner's cErc20A increase
        assertEq(cTokenA.balanceOf(address(this)), MINT_AMOUNT);
    }

    function test_assert_redeem_success() public {
        createTokenA();
        redeem();

        // cErc20's erc20A is 0
        assertEq(tokenA.balanceOf(address(cTokenA)), 0);

        // owner's cErc20A is 0
        assertEq(cTokenA.balanceOf(address(this)), 0);
    }

    function test_assert_borrow_success() public {

    }

    function createTokenA() private {
        tokenA = new MyERC20("TokenA", "TKA", 1e18);
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

    function createTokenB() private {
        tokenB = new MyERC20("TokenB", "TKB", 1e18);
        cTokenB = new CErc20Immutable(
            address(tokenB),
            comptroller,
            interestRateModel,
            1e18,
            "cTokenB",
            "cTKB",
            18,
            payable(address(this))
        );

        // add cTokenB to supportMarket
        comptroller._supportMarket(cTokenB);
    }

    function prepare() private {
        // set tokenA's price as 1$
        priceOracle.setUnderlyingPrice(cTokenA, 1e18);
        // set tokenB's price as 100$
        priceOracle.setUnderlyingPrice(cTokenB, 100 * 1e18);
        // set tokenB's collateral factor as 50%
        comptroller._setCollateralFactor(cTokenB, 0.5 * 1e18);
        // set cTokenB as collateral
        comptroller.enterMarkets([cTokenB]);
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
