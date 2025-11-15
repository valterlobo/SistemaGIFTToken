// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReservePool} from "./ReservePool.sol";
import {GiftToken} from "./GiftToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GiftTokenFactory
 * @dev Factory para criar e gerenciar Reserve Pools
 */
contract GiftTokenFactory is Ownable {
    // Endereço do GIFT Token
    address public immutable GIFT_TOKEN;

    // Lista de todos os pools criados
    address[] public allPools;

    // Verifica se um endereço é um pool válido
    mapping(address => bool) public isValidPool;

    // Pools por Reserve Token
    mapping(address => address[]) public poolsByReserveToken;

    // Informações adicionais dos pools
    struct PoolInfo {
        address poolAddress;
        address reserveToken;
        uint256 exchangeRate;
        uint256 createdAt;
        bool isActive;
    }

    mapping(address => PoolInfo) public poolInfo;

    // Eventos
    event PoolCreated(address indexed pool, address indexed reserveToken, uint256 exchangeRate, uint256 timestamp);

    event PoolDisabled(address indexed pool, uint256 timestamp);
    event PoolEnabled(address indexed pool, uint256 timestamp);

    /**
     * @dev Construtor
     * @param _giftToken Endereço do GIFT Token
     */
    constructor(address _giftToken) Ownable(msg.sender) {
        require(_giftToken != address(0), "Factory: zero gift token address");
        GIFT_TOKEN = _giftToken;
    }

    /**
     * @dev Cria um novo Reserve Pool
     * @param reserveToken Endereço do token de reserva
     * @param exchangeRate Taxa de câmbio (com 18 decimais)
     * @param minBuyAmount Valor mínimo para compra
     * @param minRedeemAmount Valor mínimo para resgate
     * @return newPool Endereço do pool criado
     */
    function createReservePool(
        address reserveToken,
        uint256 exchangeRate,
        uint256 minBuyAmount,
        uint256 minRedeemAmount
    ) external onlyOwner returns (address newPool) {
        require(reserveToken != address(0), "Factory: zero reserve token address");
        require(reserveToken != GIFT_TOKEN, "Factory: reserve cannot be GIFT token");
        require(exchangeRate > 0, "Factory: exchange rate must be greater than 0");

        // Cria novo pool
        ReservePool pool = new ReservePool(GIFT_TOKEN, reserveToken, exchangeRate, minBuyAmount, minRedeemAmount);

        newPool = address(pool);

        // Autoriza o pool no GIFT Token
        GiftToken(GIFT_TOKEN).addAuthorizedPool(newPool);

        // Registra o pool
        allPools.push(newPool);
        isValidPool[newPool] = true;
        poolsByReserveToken[reserveToken].push(newPool);

        // Salva informações
        poolInfo[newPool] = PoolInfo({
            poolAddress: newPool,
            reserveToken: reserveToken,
            exchangeRate: exchangeRate,
            createdAt: block.timestamp,
            isActive: true
        });

        emit PoolCreated(newPool, reserveToken, exchangeRate, block.timestamp);

        return newPool;
    }

    /**
     * @dev Desabilita um pool (não deleta, apenas marca como inativo)
     * @param pool Endereço do pool
     */
    function disablePool(address pool) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        require(poolInfo[pool].isActive, "Factory: pool already disabled");

        poolInfo[pool].isActive = false;

        // Pausa o pool
        ReservePool(pool).pause();

        emit PoolDisabled(pool, block.timestamp);
    }

    /**
     * @dev Reabilita um pool desabilitado
     * @param pool Endereço do pool
     */
    function enablePool(address pool) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        require(!poolInfo[pool].isActive, "Factory: pool already enabled");

        poolInfo[pool].isActive = true;

        // Despausa o pool
        ReservePool(pool).unpause();

        emit PoolEnabled(pool, block.timestamp);
    }

    /**
     * @dev Retorna todos os pools
     * @return address[] Array com endereços dos pools
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /**
     * @dev Retorna quantidade de pools
     * @return uint256 Número total de pools
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    /**
     * @dev Retorna pools de um Reserve Token específico
     * @param reserveToken Endereço do Reserve Token
     * @return address[] Array com endereços dos pools
     */
    function getPoolsByReserveToken(address reserveToken) external view returns (address[] memory) {
        return poolsByReserveToken[reserveToken];
    }

    /**
     * @dev Retorna informações detalhadas de um pool
     * @param pool Endereço do pool
     * @return info Estrutura com informações do pool
     */
    function getPoolInfo(address pool) external view returns (PoolInfo memory info) {
        require(isValidPool[pool], "Factory: invalid pool");
        return poolInfo[pool];
    }

    /**
     * @dev Retorna métricas consolidadas de um pool
     * @param pool Endereço do pool
     * return Estrutura com todas as métricas
     */
    function getPoolMetrics(address pool)
        external
        view
        returns (
            address reserveToken,
            uint256 exchangeRate,
            uint256 totalBought,
            uint256 totalRedeemed,
            uint256 reserveBalance,
            bool isPaused,
            bool isActive
        )
    {
        require(isValidPool[pool], "Factory: invalid pool");

        ReservePool poolContract = ReservePool(pool);

        (uint256 bought, uint256 redeemed, uint256 balance,,,) = poolContract.getPoolMetrics();
        (uint256 rate,) = poolContract.getExchangeRate();
        isActive = poolInfo[pool].isActive;

        return (poolInfo[pool].reserveToken, rate, bought, redeemed, balance, poolContract.paused(), isActive);
    }

    /**
     * @dev Retorna estatísticas globais do sistema
     * return (uint256 totalPools,
     *     uint256 activePools,
     *     uint256 totalGiftSupply,
     *     uint256 authorizedPoolsCount)
     */
    function getSystemStats()
        external
        view
        returns (uint256 totalPools, uint256 activePools, uint256 totalGiftSupply, uint256 authorizedPoolsCount)
    {
        uint256 active = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (poolInfo[allPools[i]].isActive) {
                active++;
            }
        }

        return
            (allPools.length, active, IERC20(GIFT_TOKEN).totalSupply(), GiftToken(GIFT_TOKEN).getAuthorizedPoolCount());
    }

    /**
     * @dev Transfere ownership de um pool
     * @param pool Endereço do pool
     * @param newOwner Novo proprietário
     */
    function transferPoolOwnership(address pool, address newOwner) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        require(newOwner != address(0), "Factory: zero address");

        ReservePool(pool).transferOwnership(newOwner);
    }

    /**
     * @dev Adiciona merchant em um pool
     * @param pool Endereço do pool
     * @param merchant Endereço do merchant
     */
    function addMerchantToPool(address pool, address merchant) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        ReservePool(pool).addMerchant(merchant);
    }

    /**
     * @dev Remove merchant de um pool
     * @param pool Endereço do pool
     * @param merchant Endereço do merchant
     */
    function removeMerchantFromPool(address pool, address merchant) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        ReservePool(pool).removeMerchant(merchant);
    }

    /**
     * @dev Atualiza taxa de câmbio de um pool
     * @param pool Endereço do pool
     * @param newRate Nova taxa
     */
    function updatePoolExchangeRate(address pool, uint256 newRate) external onlyOwner {
        require(isValidPool[pool], "Factory: invalid pool");
        ReservePool(pool).updateExchangeRate(newRate);
        poolInfo[pool].exchangeRate = newRate;
    }
}
