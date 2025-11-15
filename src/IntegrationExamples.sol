// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GiftToken} from "./GiftToken.sol";
import {ReservePool} from "./ReservePool.sol";
import {GiftTokenFactory} from "./GiftTokenFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IntegrationExamples
 * @dev Exemplos práticos de como integrar com o sistema GIFT Token
 */
contract IntegrationExamples {
    GiftToken public giftToken;
    GiftTokenFactory public factory;

    constructor(address _giftToken, address _factory) {
        giftToken = GiftToken(_giftToken);
        factory = GiftTokenFactory(_factory);
    }

    /**
     * @dev Exemplo 1: Usuário compra GIFT com Reserve Token
     */
    function example1_BuyGift(address poolAddress, address reserveToken, uint256 reserveAmount)
        external
        returns (uint256 giftReceived)
    {
        // 1. Usuário aprova o pool para gastar seu Reserve Token
        IERC20(reserveToken).approve(poolAddress, reserveAmount);

        // 2. Usuário compra GIFT
        giftReceived = ReservePool(poolAddress).buyGiftToken(reserveAmount);

        // GIFT agora está no saldo do usuário
        require(giftToken.balanceOf(msg.sender) >= giftReceived, "Balance check failed");

        return giftReceived;
    }

    /**
     * @dev Exemplo 2: Merchant resgata Reserve Token com GIFT
     */
    function example2_RedeemGift(address poolAddress, uint256 giftAmount) external returns (uint256 reserveReceived) {
        // Verifica se é merchant
        require(ReservePool(poolAddress).isMerchant(msg.sender), "Not a merchant");

        // 1. Merchant aprova o pool para gastar seu GIFT
        giftToken.approve(poolAddress, giftAmount);

        // 2. Merchant resgata Reserve Token
        reserveReceived = ReservePool(poolAddress).redeemGiftToken(giftAmount);

        return reserveReceived;
    }

    /**
     * @dev Exemplo 3: Calcular valores antes de executar
     */
    function example3_CalculateValues(address poolAddress, uint256 reserveAmount)
        external
        view
        returns (uint256 giftFromReserve, uint256 reserveFromGift)
    {
        // Calcula quanto GIFT você recebe por X Reserve
        giftFromReserve = ReservePool(poolAddress).calculateBuyOutput(reserveAmount);

        // Calcula quanto Reserve você recebe por X GIFT
        reserveFromGift = ReservePool(poolAddress).calculateRedeemOutput(giftFromReserve);

        return (giftFromReserve, reserveFromGift);
    }

    /**
     * @dev Exemplo 4: Consultar informações de múltiplos pools
     */
    function example4_GetAllPoolsInfo()
        external
        view
        returns (address[] memory pools, uint256[] memory rates, uint256[] memory balances)
    {
        pools = factory.getAllPools();
        rates = new uint256[](pools.length);
        balances = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            (uint256 rate,) = ReservePool(pools[i]).getExchangeRate();
            rates[i] = rate;
            balances[i] = ReservePool(pools[i]).getReserveBalance();
        }

        return (pools, rates, balances);
    }

    /**
     * @dev Exemplo 5: Fluxo completo - Usuário compra, transfere, merchant resgata
     */
    function example5_CompleteFlow(address poolAddress, address reserveToken, address merchant, uint256 reserveAmount)
        external
        returns (uint256 giftBought, uint256 giftTransferred, uint256 reserveRedeemed)
    {
        // 1. Usuário compra GIFT
        IERC20(reserveToken).approve(poolAddress, reserveAmount);
        giftBought = ReservePool(poolAddress).buyGiftToken(reserveAmount);

        // 2. Usuário usa GIFT (exemplo: paga ao merchant)
        giftTransferred = giftBought / 2; // Transfere metade
        giftToken.transfer(merchant, giftTransferred);

        // 3. Merchant eventualmente resgata (precisa ser chamado pelo merchant)
        // Este código seria executado pelo merchant:
        // giftToken.approve(poolAddress, giftTransferred);
        // reserveRedeemed = ReservePool(poolAddress).redeemGiftToken(giftTransferred);

        return (giftBought, giftTransferred, 0); // reserveRedeemed seria preenchido pelo merchant
    }

    /**
     * @dev Exemplo 6: Comparar taxas de diferentes pools
     */
    function example6_ComparePools(address pool1, address pool2, uint256 amount)
        external
        view
        returns (uint256 gift1, uint256 gift2, bool pool1IsBetter)
    {
        gift1 = ReservePool(pool1).calculateBuyOutput(amount);
        gift2 = ReservePool(pool2).calculateBuyOutput(amount);

        pool1IsBetter = gift1 > gift2;

        return (gift1, gift2, pool1IsBetter);
    }

    /**
     * @dev Exemplo 7: Verificar saúde do pool antes de operar
     */
    function example7_CheckPoolHealth(address poolAddress)
        external
        view
        returns (bool hasLiquidity, bool isActive, uint256 reserveBalance, uint256 utilizationRate)
    {
        // Verifica se pool está ativo
        isActive = !ReservePool(poolAddress).paused();

        // Verifica liquidez
        reserveBalance = ReservePool(poolAddress).getReserveBalance();
        hasLiquidity = reserveBalance > 0;

        // Calcula taxa de utilização
        (uint256 totalBought, uint256 totalRedeemed,,,,) = ReservePool(poolAddress).getPoolMetrics();

        if (totalBought > 0) {
            utilizationRate = (totalRedeemed * 100) / totalBought;
        }

        return (hasLiquidity, isActive, reserveBalance, utilizationRate);
    }

    /**
     * @dev Exemplo 8: Batch operations - Comprar em múltiplos pools
     */
    function example8_BatchBuy(address[] calldata pools, address[] calldata reserveTokens, uint256[] calldata amounts)
        external
        returns (uint256[] memory giftsReceived)
    {
        require(pools.length == reserveTokens.length && pools.length == amounts.length, "Array length mismatch");

        giftsReceived = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            IERC20(reserveTokens[i]).approve(pools[i], amounts[i]);
            giftsReceived[i] = ReservePool(pools[i]).buyGiftToken(amounts[i]);
        }

        return giftsReceived;
    }
}

/**
 * @title AdminHelper
 * @dev Contrato auxiliar para operações administrativas
 */
contract AdminHelper {
    GiftTokenFactory public factory;

    constructor(address _factory) {
        factory = GiftTokenFactory(_factory);
    }

    /**
     * @dev Adiciona o mesmo merchant a múltiplos pools
     */
    function addMerchantToMultiplePools(address[] calldata pools, address merchant) external {
        for (uint256 i = 0; i < pools.length; i++) {
            factory.addMerchantToPool(pools[i], merchant);
        }
    }

    /**
     * @dev Atualiza taxas de múltiplos pools em batch
     */
    function updateMultipleRates(address[] calldata pools, uint256[] calldata newRates) external {
        require(pools.length == newRates.length, "Array length mismatch");

        for (uint256 i = 0; i < pools.length; i++) {
            factory.updatePoolExchangeRate(pools[i], newRates[i]);
        }
    }

    /**
     * @dev Pausa múltiplos pools (emergência)
     */
    function emergencyPauseMultiplePools(address[] calldata pools) external {
        for (uint256 i = 0; i < pools.length; i++) {
            factory.disablePool(pools[i]);
        }
    }

    /**
     * @dev Relatório consolidado do sistema
     */
    function getSystemReport()
        external
        view
        returns (
            uint256 totalPools,
            uint256 activePools,
            uint256 totalGiftSupply,
            uint256 totalReserveValueUSD, // Precisaria oracle de preço
            uint256 averageUtilization
        )
    {
        (totalPools, activePools, totalGiftSupply,) = factory.getSystemStats();

        // totalReserveValueUSD precisaria de oracle de preços
        totalReserveValueUSD = 0; // Placeholder

        // Calcula utilização média
        address[] memory pools = factory.getAllPools();
        uint256 totalUtilization = 0;
        uint256 validPools = 0;

        for (uint256 i = 0; i < pools.length; i++) {
            (uint256 bought, uint256 redeemed,,,,) = ReservePool(pools[i]).getPoolMetrics();

            if (bought > 0) {
                totalUtilization += (redeemed * 100) / bought;
                validPools++;
            }
        }

        if (validPools > 0) {
            averageUtilization = totalUtilization / validPools;
        }

        return (totalPools, activePools, totalGiftSupply, totalReserveValueUSD, averageUtilization);
    }
}

/**
 * @title UserDashboard
 * @dev Contrato para facilitar consultas de informações do usuário
 */
contract UserDashboard {
    GiftToken public giftToken;
    GiftTokenFactory public factory;

    struct UserPoolInfo {
        address pool;
        address reserveToken;
        uint256 reserveBalance;
        uint256 giftBalance;
        uint256 reserveAllowance;
        uint256 giftAllowance;
        uint256 exchangeRate;
        bool isMerchant;
        bool isPaused;
    }

    constructor(address _giftToken, address _factory) {
        giftToken = GiftToken(_giftToken);
        factory = GiftTokenFactory(_factory);
    }

    /**
     * @dev Retorna informações completas do usuário para todos os pools
     */
    function getUserCompleteInfo(address user) external view returns (UserPoolInfo[] memory) {
        address[] memory pools = factory.getAllPools();
        UserPoolInfo[] memory infos = new UserPoolInfo[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            ReservePool pool = ReservePool(pools[i]);
            address reserveToken = pool.RESERVE_TOKEN();

            (uint256 rate,) = pool.getExchangeRate();

            infos[i] = UserPoolInfo({
                pool: pools[i],
                reserveToken: reserveToken,
                reserveBalance: IERC20(reserveToken).balanceOf(user),
                giftBalance: giftToken.balanceOf(user),
                reserveAllowance: IERC20(reserveToken).allowance(user, pools[i]),
                giftAllowance: giftToken.allowance(user, pools[i]),
                exchangeRate: rate,
                isMerchant: pool.isMerchant(user),
                isPaused: pool.paused()
            });
        }

        return infos;
    }

    /**
     * @dev Calcula o melhor pool para o usuário comprar GIFT
     */
    function findBestPoolToBuy(address user, uint256 desiredGiftAmount)
        external
        view
        returns (address bestPool, address reserveToken, uint256 reserveCost)
    {
        address[] memory pools = factory.getAllPools();
        uint256 lowestCost = type(uint256).max;

        for (uint256 i = 0; i < pools.length; i++) {
            ReservePool pool = ReservePool(pools[i]);

            if (pool.paused()) continue;

            uint256 cost = pool.calculateRedeemOutput(desiredGiftAmount);
            address reserve = pool.RESERVE_TOKEN();

            // Verifica se usuário tem saldo suficiente
            if (IERC20(reserve).balanceOf(user) >= cost && cost < lowestCost) {
                lowestCost = cost;
                bestPool = pools[i];
                reserveToken = reserve;
                reserveCost = cost;
            }
        }

        return (bestPool, reserveToken, reserveCost);
    }
}
