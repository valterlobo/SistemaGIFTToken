// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {GiftTokenFactory} from "../src/GiftTokenFactory.sol";
import {GiftToken} from "../src/GiftToken.sol";
import {ReservePool} from "../src/ReservePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 para testes
contract MockERC20 is IERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract GiftTokenFactoryTest is Test {
    GiftTokenFactory public factory;
    GiftToken public giftToken;
    MockERC20 public usdc;
    MockERC20 public usdt;

    address public owner;
    address public user1;
    address public user2;
    address public merchant;

    uint256 constant EXCHANGE_RATE = 1e18; // 1:1
    uint256 constant MIN_BUY = 1e18; // 1 token
    uint256 constant MIN_REDEEM = 1e18; // 1 token

    event PoolCreated(address indexed pool, address indexed reserveToken, uint256 exchangeRate, uint256 timestamp);
    event PoolDisabled(address indexed pool, uint256 timestamp);
    event PoolEnabled(address indexed pool, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        merchant = makeAddr("merchant");

        // Deploy tokens
        giftToken = new GiftToken("GFT", "GIFT TOKEN", owner);
        usdc = new MockERC20();
        usdt = new MockERC20();

        // Deploy factory
        vm.startPrank(owner);
        factory = new GiftTokenFactory(address(giftToken));
        vm.stopPrank();
        // Transferir ownership do GiftToken para a factory poder autorizar pools
        giftToken.grantRole(keccak256("POOL_MANAGER_ROLE"), address(factory));
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(factory.GIFT_TOKEN(), address(giftToken));
        assertEq(factory.owner(), owner);
        assertEq(factory.getPoolCount(), 0);
    }

    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert("Factory: zero gift token address");
        new GiftTokenFactory(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE POOL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateReservePool() public {
        vm.expectEmit(false, true, false, true);
        emit PoolCreated(address(0), address(usdc), EXCHANGE_RATE, block.timestamp);

        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        assertTrue(pool != address(0));
        assertTrue(factory.isValidPool(pool));
        assertEq(factory.getPoolCount(), 1);

        // Verificar informações do pool
        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertEq(info.poolAddress, pool);
        assertEq(info.reserveToken, address(usdc));
        assertEq(info.exchangeRate, EXCHANGE_RATE);
        assertEq(info.createdAt, block.timestamp);
        assertTrue(info.isActive);

        // Verificar se pool foi autorizado no GiftToken
        //assertTrue(giftToken.hasRole(giftToken.POOL_MANAGER_ROLE(), info.poolAddress));
    }

    function test_CreateReservePool_MultipleTokens() public {
        address pool1 = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        address pool2 = factory.createReservePool(address(usdt), EXCHANGE_RATE * 2, MIN_BUY, MIN_REDEEM);

        assertEq(factory.getPoolCount(), 2);

        address[] memory allPools = factory.getAllPools();
        assertEq(allPools.length, 2);
        assertEq(allPools[0], pool1);
        assertEq(allPools[1], pool2);

        address[] memory usdcPools = factory.getPoolsByReserveToken(address(usdc));
        assertEq(usdcPools.length, 1);
        assertEq(usdcPools[0], pool1);

        address[] memory usdtPools = factory.getPoolsByReserveToken(address(usdt));
        assertEq(usdtPools.length, 1);
        assertEq(usdtPools[0], pool2);
    }

    function test_CreateReservePool_RevertZeroReserveToken() public {
        vm.expectRevert("Factory: zero reserve token address");
        factory.createReservePool(address(0), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
    }

    function test_CreateReservePool_RevertGiftTokenAsReserve() public {
        vm.expectRevert("Factory: reserve cannot be GIFT token");
        factory.createReservePool(address(giftToken), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
    }

    function test_CreateReservePool_RevertZeroExchangeRate() public {
        vm.expectRevert("Factory: exchange rate must be greater than 0");
        factory.createReservePool(address(usdc), 0, MIN_BUY, MIN_REDEEM);
    }

    function test_CreateReservePool_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
    }

    /*//////////////////////////////////////////////////////////////
                        DISABLE/ENABLE POOL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DisablePool() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        vm.expectEmit(true, false, false, true);
        emit PoolDisabled(pool, block.timestamp);

        factory.disablePool(pool);

        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertFalse(info.isActive);
        assertTrue(ReservePool(pool).paused());
    }

    function test_DisablePool_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.disablePool(address(usdc));
    }

    function test_DisablePool_RevertAlreadyDisabled() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        factory.disablePool(pool);

        vm.expectRevert("Factory: pool already disabled");
        factory.disablePool(pool);
    }

    function test_EnablePool() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        factory.disablePool(pool);

        vm.expectEmit(true, false, false, true);
        emit PoolEnabled(pool, block.timestamp);

        factory.enablePool(pool);

        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertTrue(info.isActive);
        assertFalse(ReservePool(pool).paused());
    }

    function test_EnablePool_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.enablePool(address(usdc));
    }

    function test_EnablePool_RevertAlreadyEnabled() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        vm.expectRevert("Factory: pool already enabled");
        factory.enablePool(pool);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetAllPools() public {
        address pool1 = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        address pool2 = factory.createReservePool(address(usdt), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        address[] memory pools = factory.getAllPools();
        assertEq(pools.length, 2);
        assertEq(pools[0], pool1);
        assertEq(pools[1], pool2);
    }

    function test_GetPoolCount() public {
        assertEq(factory.getPoolCount(), 0);

        factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        assertEq(factory.getPoolCount(), 1);

        factory.createReservePool(address(usdt), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        assertEq(factory.getPoolCount(), 2);
    }

    function test_GetPoolsByReserveToken() public {
        address pool1 = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        address pool2 = factory.createReservePool(address(usdc), EXCHANGE_RATE * 2, MIN_BUY, MIN_REDEEM);
        factory.createReservePool(address(usdt), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        address[] memory usdcPools = factory.getPoolsByReserveToken(address(usdc));
        assertEq(usdcPools.length, 2);
        assertEq(usdcPools[0], pool1);
        assertEq(usdcPools[1], pool2);

        address[] memory usdtPools = factory.getPoolsByReserveToken(address(usdt));
        assertEq(usdtPools.length, 1);
    }

    function test_GetPoolInfo() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertEq(info.poolAddress, pool);
        assertEq(info.reserveToken, address(usdc));
        assertEq(info.exchangeRate, EXCHANGE_RATE);
        assertEq(info.createdAt, block.timestamp);
        assertTrue(info.isActive);
    }

    function test_GetPoolInfo_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.getPoolInfo(address(usdc));
    }

    function test_GetPoolMetrics() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        (
            address reserveToken,
            uint256 exchangeRate,
            uint256 totalBought,
            uint256 totalRedeemed,
            uint256 reserveBalance,
            bool isPaused,
            bool isActive
        ) = factory.getPoolMetrics(pool);

        assertEq(reserveToken, address(usdc));
        assertEq(exchangeRate, EXCHANGE_RATE);
        assertEq(totalBought, 0);
        assertEq(totalRedeemed, 0);
        assertEq(reserveBalance, 0);
        assertFalse(isPaused);
        assertTrue(isActive);
    }

    function test_GetPoolMetrics_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.getPoolMetrics(address(usdc));
    }

    function test_GetSystemStats() public {
        factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        address pool2 = factory.createReservePool(address(usdt), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        factory.disablePool(pool2);

        (uint256 totalPools, uint256 activePools, uint256 totalGiftSupply, uint256 authorizedPoolsCount) =
            factory.getSystemStats();

        assertEq(totalPools, 2);
        assertEq(activePools, 1);
        assertEq(totalGiftSupply, giftToken.totalSupply());
        assertEq(authorizedPoolsCount, 2);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferPoolOwnership() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        factory.transferPoolOwnership(pool, user1);

        // O novo owner precisa aceitar
        vm.prank(user1);
        //ReservePool(pool).acceptOwnership();

        assertEq(ReservePool(pool).owner(), user1);
    }

    function test_TransferPoolOwnership_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.transferPoolOwnership(address(usdc), user1);
    }

    function test_TransferPoolOwnership_RevertZeroAddress() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        vm.expectRevert("Factory: zero address");
        factory.transferPoolOwnership(pool, address(0));
    }

    function test_AddMerchantToPool() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        factory.addMerchantToPool(pool, merchant);

        assertTrue(ReservePool(pool).isMerchant(merchant));
    }

    function test_AddMerchantToPool_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.addMerchantToPool(address(usdc), merchant);
    }

    function test_RemoveMerchantFromPool() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        factory.addMerchantToPool(pool, merchant);

        factory.removeMerchantFromPool(pool, merchant);

        assertFalse(ReservePool(pool).isMerchant(merchant));
    }

    function test_RemoveMerchantFromPool_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.removeMerchantFromPool(address(usdc), merchant);
    }

    function test_UpdatePoolExchangeRate() public {
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        uint256 newRate = EXCHANGE_RATE * 2;
        factory.updatePoolExchangeRate(pool, newRate);

        (uint256 rate,) = ReservePool(pool).getExchangeRate();

        assertEq(rate, newRate);

        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertEq(info.exchangeRate, newRate);
    }

    function test_UpdatePoolExchangeRate_RevertInvalidPool() public {
        vm.expectRevert("Factory: invalid pool");
        factory.updatePoolExchangeRate(address(usdc), EXCHANGE_RATE * 2);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CreateReservePool(uint256 exchangeRate) public {
        vm.assume(exchangeRate > 0 && exchangeRate < type(uint128).max);

        address pool = factory.createReservePool(address(usdc), exchangeRate, MIN_BUY, MIN_REDEEM);

        GiftTokenFactory.PoolInfo memory info = factory.getPoolInfo(pool);
        assertEq(info.exchangeRate, exchangeRate);
    }

    function testFuzz_UpdatePoolExchangeRate(uint256 initialRate, uint256 newRate) public {
        vm.assume(initialRate > 0 && initialRate < type(uint128).max);
        vm.assume(newRate > 0 && newRate < type(uint128).max);

        address pool = factory.createReservePool(address(usdc), initialRate, MIN_BUY, MIN_REDEEM);
        factory.updatePoolExchangeRate(pool, newRate);

        (uint256 rate,) = ReservePool(pool).getExchangeRate();
        assertEq(rate, newRate);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_FullLifecycle() public {
        // 1. Criar pool
        address pool = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        assertEq(factory.getPoolCount(), 1);

        // 2. Adicionar merchant
        factory.addMerchantToPool(pool, merchant);
        assertTrue(ReservePool(pool).isMerchant(merchant));

        // 3. Atualizar taxa de câmbio
        uint256 newRate = EXCHANGE_RATE * 2;
        factory.updatePoolExchangeRate(pool, newRate);
        (uint256 rate,) = ReservePool(pool).getExchangeRate();
        assertEq(rate, newRate);

        // 4. Desabilitar pool
        factory.disablePool(pool);
        assertFalse(factory.getPoolInfo(pool).isActive);
        assertTrue(ReservePool(pool).paused());

        // 5. Reabilitar pool
        factory.enablePool(pool);
        assertTrue(factory.getPoolInfo(pool).isActive);
        assertFalse(ReservePool(pool).paused());

        // 6. Verificar estatísticas
        (uint256 totalPools, uint256 activePools,,) = factory.getSystemStats();
        assertEq(totalPools, 1);
        assertEq(activePools, 1);
    }

    function test_Integration_MultiplePools() public {
        // Criar múltiplos pools
        address pool1 = factory.createReservePool(address(usdc), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);
        address pool2 = factory.createReservePool(address(usdc), EXCHANGE_RATE * 2, MIN_BUY, MIN_REDEEM);
        address pool3 = factory.createReservePool(address(usdt), EXCHANGE_RATE, MIN_BUY, MIN_REDEEM);

        // Verificar contagem
        assertEq(factory.getPoolCount(), 3);

        // Verificar pools por token
        address[] memory usdcPools = factory.getPoolsByReserveToken(address(usdc));
        assertEq(usdcPools.length, 2);

        // Desabilitar um pool
        factory.disablePool(pool2);

        // Verificar estatísticas
        (uint256 totalPools, uint256 activePools,,) = factory.getSystemStats();
        assertEq(totalPools, 3);
        assertEq(activePools, 2);

        // Verificar que pools individuais ainda funcionam
        assertTrue(factory.isValidPool(pool1));
        assertTrue(factory.isValidPool(pool2));
        assertTrue(factory.isValidPool(pool3));
    }
}
