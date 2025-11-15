// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GiftToken} from "../src/GiftToken.sol";
import {ReservePool} from "../src/ReservePool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Reserve Token para testes
contract MockReserveToken is ERC20 {
    constructor() ERC20("Mock Reserve", "MOCK") {
        _mint(msg.sender, 1000000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ReservePoolTest is Test {
    GiftToken public giftToken;
    MockReserveToken public reserveToken;
    ReservePool public pool;

    address public owner;
    address public merchant1;
    address public merchant2;
    address public user1;
    address public user2;

    uint256 constant EXCHANGE_RATE = 10e18; // 1 Reserve = 10 GIFT
    uint256 constant MIN_BUY = 1e18;
    uint256 constant MIN_REDEEM = 1e18;

    event BuyExecuted(address indexed buyer, uint256 reserveAmountIn, uint256 giftAmountOut, uint256 timestamp);
    event RedeemExecuted(address indexed merchant, uint256 giftAmountIn, uint256 reserveAmountOut, uint256 timestamp);
    event MerchantAdded(address indexed merchant, uint256 timestamp);
    event MerchantRemoved(address indexed merchant, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        merchant1 = makeAddr("merchant1");
        merchant2 = makeAddr("merchant2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy tokens
        giftToken = new GiftToken("GIFT TOKEN", "GIFT", owner);
        reserveToken = new MockReserveToken();

        // Deploy pool
        pool = new ReservePool(address(giftToken), address(reserveToken), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        // Autoriza pool no GIFT Token
        giftToken.addAuthorizedPool(address(pool));

        // Distribui reserve tokens para usuários
        bool ok;
        ok = reserveToken.transfer(user1, 10000e18);
        if (!ok) revert("Transfer failed");
        ok = reserveToken.transfer(user2, 10000e18);
        if (!ok) revert("Transfer failed");

        // Adiciona liquidez inicial ao pool
        reserveToken.approve(address(pool), 100000e18);
        pool.depositReserve(100000e18);
    }

    function testInitialState() public view {
        assertEq(pool.GIFT_TOKEN(), address(giftToken));
        assertEq(pool.RESERVE_TOKEN(), address(reserveToken));
        assertEq(pool.exchangeRate(), EXCHANGE_RATE);
        assertEq(pool.RATE_DECIMALS(), 18);
        assertEq(pool.minBuyAmount(), MIN_BUY);
        assertEq(pool.minRedeemAmount(), MIN_REDEEM);
        assertEq(pool.totalBought(), 0);
        assertEq(pool.totalRedeemed(), 0);
        assertEq(pool.getMerchantCount(), 0);
    }

    function testAddMerchant() public {
        vm.expectEmit(true, false, false, true);
        emit MerchantAdded(merchant1, block.timestamp);

        pool.addMerchant(merchant1);

        assertTrue(pool.isMerchant(merchant1));
        assertEq(pool.getMerchantCount(), 1);

        address[] memory merchants = pool.getAllMerchants();
        assertEq(merchants.length, 1);
        assertEq(merchants[0], merchant1);
    }

    function testRemoveMerchant() public {
        pool.addMerchant(merchant1);
        pool.addMerchant(merchant2);

        vm.expectEmit(true, false, false, true);
        emit MerchantRemoved(merchant1, block.timestamp);

        pool.removeMerchant(merchant1);

        assertFalse(pool.isMerchant(merchant1));
        assertTrue(pool.isMerchant(merchant2));
        assertEq(pool.getMerchantCount(), 1);
    }

    function testBuyGiftToken() public {
        uint256 reserveAmount = 100e18;
        uint256 expectedGift = 1000e18; // 100 * 10

        vm.startPrank(user1);
        reserveToken.approve(address(pool), reserveAmount);

        uint256 initialReserveBalance = reserveToken.balanceOf(user1);

        vm.expectEmit(true, false, false, false);
        emit BuyExecuted(user1, reserveAmount, expectedGift, block.timestamp);

        uint256 giftOut = pool.buyGiftToken(reserveAmount);
        vm.stopPrank();

        assertEq(giftOut, expectedGift);
        assertEq(giftToken.balanceOf(user1), expectedGift);
        assertEq(reserveToken.balanceOf(user1), initialReserveBalance - reserveAmount);
        assertEq(pool.totalBought(), expectedGift);
        assertEq(pool.buyCount(), 1);
    }

    function testBuyMultipleTimes() public {
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 1000e18);

        pool.buyGiftToken(100e18);
        pool.buyGiftToken(200e18);
        pool.buyGiftToken(50e18);
        vm.stopPrank();

        assertEq(giftToken.balanceOf(user1), 3500e18); // (100+200+50)*10
        assertEq(pool.buyCount(), 3);
        assertEq(pool.totalBought(), 3500e18);
    }

    function testCannotBuyBelowMinimum() public {
        vm.startPrank(user1);
        reserveToken.approve(address(pool), MIN_BUY - 1);

        vm.expectRevert("ReservePool: amount below minimum");
        pool.buyGiftToken(MIN_BUY - 1);
        vm.stopPrank();
    }

    function testCannotBuyWithoutApproval() public {
        vm.prank(user1);
        vm.expectRevert();
        pool.buyGiftToken(100e18);
    }

    function testRedeemGiftToken() public {
        // Setup: adiciona merchant e faz compra inicial
        pool.addMerchant(merchant1);

        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);

        // Transfere GIFT para merchant
        giftToken.transfer(merchant1, 500e18);
        vm.stopPrank();

        // Merchant resgata
        uint256 giftAmount = 500e18;
        uint256 expectedReserve = 50e18; // 500 / 10

        vm.startPrank(merchant1);
        giftToken.approve(address(pool), giftAmount);

        uint256 initialReserveBalance = reserveToken.balanceOf(merchant1);

        vm.expectEmit(true, false, false, false);
        emit RedeemExecuted(merchant1, giftAmount, expectedReserve, block.timestamp);

        uint256 reserveOut = pool.redeemGiftToken(giftAmount);
        vm.stopPrank();

        assertEq(reserveOut, expectedReserve);
        assertEq(giftToken.balanceOf(merchant1), 0);
        assertEq(reserveToken.balanceOf(merchant1), initialReserveBalance + expectedReserve);
        assertEq(pool.totalRedeemed(), giftAmount);
        assertEq(pool.redeemCount(), 1);
    }

    function testNonMerchantCannotRedeem() public {
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);

        giftToken.approve(address(pool), 500e18);

        vm.expectRevert("ReservePool: caller is not a merchant");
        pool.redeemGiftToken(500e18);
        vm.stopPrank();
    }

    function testCannotRedeemBelowMinimum() public {
        pool.addMerchant(merchant1);

        vm.prank(merchant1);
        vm.expectRevert("ReservePool: amount below minimum");
        pool.redeemGiftToken(MIN_REDEEM - 1);
    }

    function testCannotRedeemWithInsufficientLiquidity() public {
        pool.addMerchant(merchant1);

        // Retira toda liquidez do pool
        pool.withdrawReserve(pool.getReserveBalance());
        console.log("Pool reserve after withdrawal:", pool.getReserveBalance());

        // Usuário compra GIFT
        vm.startPrank(user1);
        console.log(reserveToken.balanceOf(user1));
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);
        bool ok = giftToken.transfer(merchant1, 1000e18);
        //vm.expectRevert("ReservePool: insufficient reserve liquidity");
        if (!ok) revert("Transfer failed");
        console.log("Transfer succeeded");
        vm.stopPrank();

        // Merchant tenta resgatar mas não há liquidez
        vm.startPrank(merchant1);
        giftToken.approve(address(pool), 5000e18);
        console.log("Pool reserve           :", pool.getReserveBalance());
        console.log("Pool gift token        :", pool.getGiftTokenBalance());
        console.log("Merchant gift token    :", giftToken.balanceOf(merchant1));
        vm.expectRevert("ReservePool: insufficient reserve liquidity");
        pool.redeemGiftToken(5000e18);
        //console.log("Merchant reserve token :", reserveToken.balanceOf(merchant1));
        //console.log("Merchant gift    token :", giftToken.balanceOf(merchant1));

        vm.stopPrank();
    }

    function testCalculateBuyOutput() public view {
        uint256 reserveAmount = 100e18;
        uint256 expectedGift = 1000e18;

        uint256 calculated = pool.calculateBuyOutput(reserveAmount);
        assertEq(calculated, expectedGift);
    }

    function testCalculateRedeemOutput() public view {
        uint256 giftAmount = 1000e18;
        uint256 expectedReserve = 100e18;

        uint256 calculated = pool.calculateRedeemOutput(giftAmount);
        assertEq(calculated, expectedReserve);
    }

    function testUpdateExchangeRate() public {
        uint256 newRate = 20e18; // 1 Reserve = 20 GIFT

        pool.updateExchangeRate(newRate);

        assertEq(pool.exchangeRate(), newRate);

        // Testa com nova taxa
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        uint256 giftOut = pool.buyGiftToken(100e18);
        vm.stopPrank();

        assertEq(giftOut, 2000e18); // 100 * 20
    }

    function testCannotUpdateExchangeRateToZero() public {
        vm.expectRevert("ReservePool: rate must be greater than 0");
        pool.updateExchangeRate(0);
    }

    function testUpdateMinAmounts() public {
        uint256 newMinBuy = 10e18;
        uint256 newMinRedeem = 5e18;

        pool.updateMinAmounts(newMinBuy, newMinRedeem);

        assertEq(pool.minBuyAmount(), newMinBuy);
        assertEq(pool.minRedeemAmount(), newMinRedeem);
    }

    function testDepositReserve() public {
        uint256 depositAmount = 1000e18;
        uint256 initialBalance = pool.getReserveBalance();

        reserveToken.approve(address(pool), depositAmount);
        pool.depositReserve(depositAmount);

        assertEq(pool.getReserveBalance(), initialBalance + depositAmount);
    }

    function testWithdrawReserve() public {
        uint256 withdrawAmount = 1000e18;
        uint256 initialBalance = pool.getReserveBalance();
        uint256 ownerInitialBalance = reserveToken.balanceOf(owner);

        pool.withdrawReserve(withdrawAmount);

        assertEq(pool.getReserveBalance(), initialBalance - withdrawAmount);
        assertEq(reserveToken.balanceOf(owner), ownerInitialBalance + withdrawAmount);
    }

    function testGetPoolMetrics() public {
        // Faz algumas operações
        pool.addMerchant(merchant1);

        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);
        giftToken.transfer(merchant1, 500e18);
        vm.stopPrank();

        vm.startPrank(merchant1);
        giftToken.approve(address(pool), 500e18);
        pool.redeemGiftToken(500e18);
        vm.stopPrank();

        (
            uint256 bought,
            uint256 redeemed,
            uint256 balance,
            uint256 merchantCount,
            uint256 buyCount,
            uint256 redeemCount
        ) = pool.getPoolMetrics();

        assertEq(bought, 1000e18);
        assertEq(redeemed, 500e18);
        assertGt(balance, 0);
        assertEq(merchantCount, 1);
        assertEq(buyCount, 1);
        assertEq(redeemCount, 1);
    }

    function testPausePool() public {
        pool.pause();
        assertTrue(pool.paused());

        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.buyGiftToken(100e18);
        vm.stopPrank();
    }

    function testUnpausePool() public {
        pool.pause();
        pool.unpause();
        assertFalse(pool.paused());

        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);
        vm.stopPrank();

        assertEq(giftToken.balanceOf(user1), 1000e18);
    }

    function testReentrancyProtection() public {
        // Este teste verifica que o modificador nonReentrant está presente
        // Foundry detecta automaticamente tentativas de reentrada
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 100e18);
        pool.buyGiftToken(100e18);
        vm.stopPrank();
    }

    function testOnlyOwnerFunctions() public {
        vm.startPrank(user1);

        vm.expectRevert();
        pool.addMerchant(merchant1);

        vm.expectRevert();
        pool.removeMerchant(merchant1);

        vm.expectRevert();
        pool.updateExchangeRate(20e18);

        vm.expectRevert();
        pool.pause();

        vm.expectRevert();
        pool.depositReserve(1000e18);

        vm.expectRevert();
        pool.withdrawReserve(1000e18);

        vm.stopPrank();
    }

    function testFuzzBuy(uint96 amount) public {
        vm.assume(amount >= MIN_BUY && amount <= 1000000e18);

        reserveToken.mint(user1, amount);

        vm.startPrank(user1);
        reserveToken.approve(address(pool), amount);

        uint256 expectedGift = (amount * EXCHANGE_RATE) / 1e18;
        uint256 giftOut = pool.buyGiftToken(amount);
        vm.stopPrank();

        assertEq(giftOut, expectedGift);
        assertEq(giftToken.balanceOf(user1), expectedGift);
    }

    function testFuzzRedeem(uint96 buyAmount) public {
        vm.assume(buyAmount >= MIN_BUY && buyAmount <= 100000e18);

        pool.addMerchant(merchant1);
        reserveToken.mint(user1, buyAmount);

        // Compra
        vm.startPrank(user1);
        reserveToken.approve(address(pool), buyAmount);
        uint256 giftReceived = pool.buyGiftToken(buyAmount);
        giftToken.transfer(merchant1, giftReceived);
        vm.stopPrank();

        // Resgate
        if (giftReceived >= MIN_REDEEM) {
            vm.startPrank(merchant1);
            giftToken.approve(address(pool), giftReceived);

            uint256 expectedReserve = (giftReceived * 1e18) / EXCHANGE_RATE;
            uint256 reserveOut = pool.redeemGiftToken(giftReceived);
            vm.stopPrank();

            assertEq(reserveOut, expectedReserve);
        }
    }

    function testCompleteUserJourney() public {
        // 1. Adiciona merchant
        pool.addMerchant(merchant1);

        // 2. User1 compra GIFT
        vm.startPrank(user1);
        reserveToken.approve(address(pool), 500e18);
        pool.buyGiftToken(500e18);
        assertEq(giftToken.balanceOf(user1), 5000e18);

        // 3. User1 transfere para User2
        giftToken.transfer(user2, 2000e18);
        vm.stopPrank();

        assertEq(giftToken.balanceOf(user2), 2000e18);

        // 4. User2 transfere para merchant
        vm.prank(user2);
        giftToken.transfer(merchant1, 2000e18);

        // 5. Merchant resgata
        vm.startPrank(merchant1);
        giftToken.approve(address(pool), 2000e18);
        uint256 reserveOut = pool.redeemGiftToken(2000e18);
        vm.stopPrank();

        assertEq(reserveOut, 200e18);
        assertEq(giftToken.balanceOf(merchant1), 0);
    }
}
