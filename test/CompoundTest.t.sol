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

    uint256 private constant MINT_AMOUNT = 100;
    uint256 private constant BORROW_AMOUNT = 50;
    uint256 private constant CLOSE_FACTOR = 0.5 * 1e18;
    uint256 private constant LIQUIDATION_INCENTIVE = 0.1 * 1e18;
    uint256 private constant COLLATERAL_FACTOR_30 = 0.3 * 1e18;

    address private constant USER2 = address(0x22);

    function setUp() public {
        comptroller = new Comptroller();
        priceOracle = new SimplePriceOracle();
        interestRateModel = new WhitePaperInterestRateModel(0, 0);

        // set simplePriceOracle as price oracle
        comptroller._setPriceOracle(priceOracle);

        (tokenA, cTokenA) = createToken("TokenA", "TKA", "cTokenA", "cTKA");
        (tokenB, cTokenB) = createToken("TokenB", "TKB", "cTokenB", "cTKB");
    }

    function test_assert_mint_success() public {
        mintCToken(tokenA, cTokenA, MINT_AMOUNT);

        // cErc20's erc20A increase
        assertEq(tokenA.balanceOf(address(cTokenA)), MINT_AMOUNT);

        // owner's cErc20A increase
        assertEq(cTokenA.balanceOf(address(this)), MINT_AMOUNT);
    }

    function test_assert_redeem_success() public {
        mintCToken(tokenA, cTokenA, MINT_AMOUNT);
        redeem(cTokenA, MINT_AMOUNT);

        // cErc20's erc20A is 0
        assertEq(tokenA.balanceOf(address(cTokenA)), 0);

        // owner's cErc20A is 0
        assertEq(cTokenA.balanceOf(address(this)), 0);
    }

    function test_assert_borrow_success() public {
        setupTokens();

        // mint cTokenB
        mintCToken(tokenB, cTokenB, 1);

        // That's say this test contract as User1
        // Before borrow, User1's balance of tokenA and cTokenA's balance of tokenA
        uint256 user1Balance = tokenA.balanceOf(address(this));
        uint256 cTokenABalance = tokenA.balanceOf(address(cTokenA));

        // borrow
        // Maximin of borrow amount is 50$, cuz tokenB's collateral is 50% and we only have 1 tokenB(price 100$)
        cTokenA.borrow(BORROW_AMOUNT);

        // After borrow
        // User1's balance of tokenA should increase 50(BORROW_AMOUNT)
        assertEq(tokenA.balanceOf(address(this)), user1Balance + BORROW_AMOUNT);
        // cTokenA's balance of tokenA should decrease 50(BORROW_AMOUNT)
        assertEq(tokenA.balanceOf(address(cTokenA)), cTokenABalance - BORROW_AMOUNT);
    }

    function test_assert_repay_success() public {
        setupTokens();

        // mint cTokenB
        mintCToken(tokenB, cTokenB, 1);

        // borrow 50$ tokenA
        cTokenA.borrow(BORROW_AMOUNT);

        // That's say this test contract as User1
        // After borrow, User1's balance of tokenA and cTokenA's balance of tokenA
        uint256 user1Balance = tokenA.balanceOf(address(this));
        uint256 cTokenABalance = tokenA.balanceOf(address(cTokenA));

        // when cTokenA execute repayBorrow will transfer tokenA from User1 to cTokenA,
        // so need to approve first
        tokenA.approve(address(cTokenA), BORROW_AMOUNT);
        cTokenA.repayBorrow(BORROW_AMOUNT);

        // After repay
        // User1's balance of tokenA should decrease 50(BORROW_AMOUNT)
        assertEq(tokenA.balanceOf(address(this)), user1Balance - BORROW_AMOUNT);
        // cTokenA's balance of tokenA should increase 50(BORROW_AMOUNT)
        assertEq(tokenA.balanceOf(address(cTokenA)), cTokenABalance + BORROW_AMOUNT);
    }

    function test_change_collateral_factor_then_liquidate_success() public {
        setupTokens();

        // mint cTokenB
        mintCToken(tokenB, cTokenB, 1);

        // borrow 50$ tokenA
        cTokenA.borrow(BORROW_AMOUNT);

        // set close factor to 50%
        comptroller._setCloseFactor(CLOSE_FACTOR);

        // set liquidation incentive to 10%
        comptroller._setLiquidationIncentive(LIQUIDATION_INCENTIVE);

        // set tokenB's new collateral factor as 30%
        comptroller._setCollateralFactor(cTokenB, COLLATERAL_FACTOR_30);

        // check collateral factor been updated
        (, uint256 collateralFactorMantissa,) = comptroller.markets(address(cTokenB));
        assertEq(collateralFactorMantissa, COLLATERAL_FACTOR_30);

        // check shortfall is greater then 0, cuz collateral factor has change form 50 to 30
        // shortfall is 20 at this moment
        (,, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        assertGt(shortfall, 0);

        uint256 repayAmount = shortfall * CLOSE_FACTOR / 1e18;

        vm.startPrank(USER2);
        // User2 mint the repay amount of tokenA then approve for later doing liquidate
        tokenA.mint(repayAmount);
        tokenA.approve(address(cTokenA), repayAmount);

        // balance before liquidate
        uint256 user2Balance = tokenA.balanceOf(address(USER2));
        uint256 cTokenABalance = tokenA.balanceOf(address(cTokenA));

        // User2 liquidate User1, so in tokenA, User2's balance will decrease repayAmount
        cTokenA.liquidateBorrow(address(this), repayAmount, cTokenB);
        vm.stopPrank();

        // After liquidate User2's balance decrease repayAmount and cTokenA's balance increase repayAmount
        assertEq(tokenA.balanceOf(address(USER2)), user2Balance - repayAmount);
        assertEq(tokenA.balanceOf(address(cTokenA)), cTokenABalance + repayAmount);

        /**
         * 需要再研究的問題:
         * 這個測試會成功，但看起來沒有測試到 User2 的收益，總不可能幫忙清算沒酬勞，要研究一下酬勞去哪驗證
         */

        // console.log("==========================================================");
        // console.log("TokenA");
        // console.log("Balance of User 1 : %d", tokenA.balanceOf(address(this)));
        // console.log("Balance of User 2 : %d", tokenA.balanceOf(address(USER2)));
        // console.log("Balance of cTokenA: %d", tokenA.balanceOf(address(cTokenA)));
        // console.log("==========================================================");
        // console.log("cTokenA");
        // console.log("Balance of User 1 : %d", cTokenA.balanceOf(address(this)));
        // console.log("Balance of User 2 : %d", cTokenA.balanceOf(address(USER2)));
        // console.log("==========================================================");
        // console.log("TokenB");
        // console.log("Balance of User 1 : %d", tokenB.balanceOf(address(this)));
        // console.log("Balance of User 2 : %d", tokenB.balanceOf(address(USER2)));
        // console.log("Balance of cTokenB: %d", tokenB.balanceOf(address(cTokenB)));
        // console.log("==========================================================");
        // console.log("cTokenB");
        // console.log("Balance of User 1 : %d", cTokenB.balanceOf(address(this)));
        // console.log("Balance of User 2 : %d", cTokenB.balanceOf(address(USER2)));
    }

    function test_change_token_price_then_liquidate_success() public {
        setupTokens();

        // mint cTokenB
        mintCToken(tokenB, cTokenB, 1);

        // borrow 50$ tokenA
        cTokenA.borrow(BORROW_AMOUNT);

        // set close factor to 50%
        comptroller._setCloseFactor(CLOSE_FACTOR);

        // set liquidation incentive to 10%
        comptroller._setLiquidationIncentive(LIQUIDATION_INCENTIVE);

        // change cTokenB price to 50$
        priceOracle.setUnderlyingPrice(cTokenB, 50 * 1e18);

        // check shortfall is greater then 0, cuz the price of cTokenB has change form 100 to 50
        // shortfall is 25 at this moment
        (,, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        assertGt(shortfall, 0);

        uint256 repayAmount = shortfall * CLOSE_FACTOR / 1e18;

        vm.startPrank(USER2);
        // User2 mint the repay amount of tokenA then approve for later doing liquidate
        tokenA.mint(repayAmount);
        tokenA.approve(address(cTokenA), repayAmount);

        // balance before liquidate
        uint256 user2Balance = tokenA.balanceOf(address(USER2));
        uint256 cTokenABalance = tokenA.balanceOf(address(cTokenA));

        // User2 liquidate User1, so in tokenA, User2's balance will decrease repayAmount
        cTokenA.liquidateBorrow(address(this), repayAmount, cTokenB);
        vm.stopPrank();

        // After liquidate User2's balance decrease repayAmount and cTokenA's balance increase repayAmount
        assertEq(tokenA.balanceOf(address(USER2)), user2Balance - repayAmount);
        assertEq(tokenA.balanceOf(address(cTokenA)), cTokenABalance + repayAmount);
    }

    function createToken(string memory _name, string memory _symbol, string memory _cName, string memory _cSymbol)
        private
        returns (MyERC20 token, CErc20 cToken)
    {
        token = new MyERC20(_name, _symbol, 1e18);
        cToken = new CErc20Immutable(
            address(token), comptroller, interestRateModel, 1e18, _cName, _cSymbol, 18, payable(address(this))
        );

        // Add cToken to the markets mapping
        comptroller._supportMarket(cToken);
    }

    function mintCToken(MyERC20 erc20, CErc20 cErc20, uint256 amount) private {
        // to approve cErc20 address, cuz we will do transferFrom when mint cErc20
        erc20.approve(address(cErc20), amount);

        // mint cErc20
        // there are 2 steps in this mint action: do transferFrom in erc20 first, and then mint cErc20
        cErc20.mint(amount);
    }

    function redeem(CErc20 cErc20, uint256 amount) private {
        // do redeem
        // there are 2 steps in this redeem action: to decrease cErc20 first, then do transfer in erc20
        cErc20.redeem(amount);
    }

    function setupTokens() private {
        // set tokenA's price as 1$
        priceOracle.setUnderlyingPrice(cTokenA, 1e18);
        // set tokenB's price as 100$
        priceOracle.setUnderlyingPrice(cTokenB, 100 * 1e18);
        // set tokenB's collateral factor as 50%
        comptroller._setCollateralFactor(cTokenB, 0.5 * 1e18);
        // set cTokenB as collateral
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cTokenB);
        comptroller.enterMarkets(cTokens);

        // supply tokenA
        vm.startPrank(USER2);
        tokenA.mint(MINT_AMOUNT);
        mintCToken(tokenA, cTokenA, MINT_AMOUNT);
        vm.stopPrank();
    }
}
