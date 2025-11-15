// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IGiftToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title ReservePool
 * @dev Pool de reserva para trocar entre Reserve Token e GIFT Token
 */
contract ReservePool is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Endereços dos tokens
    address public immutable GIFT_TOKEN;
    address public immutable RESERVE_TOKEN;

    // Taxa de câmbio: quantos GIFT por 1 Reserve Token (com decimais)
    uint256 public exchangeRate;
    uint8 public constant RATE_DECIMALS = 18;

    // Valor mínimo para operações (previne spam e dust)
    uint256 public minBuyAmount;
    uint256 public minRedeemAmount;

    // Comerciantes autorizados
    mapping(address => bool) private merchants;
    address[] private merchantList;

    // Estatísticas
    uint256 public totalBought; // Total de GIFT comprado
    uint256 public totalRedeemed; // Total de GIFT resgatado
    uint256 public buyCount; // Número de operações de compra
    uint256 public redeemCount; // Número de operações de resgate

    // Eventos
    event BuyExecuted(address indexed buyer, uint256 reserveAmountIn, uint256 giftAmountOut, uint256 timestamp);

    event RedeemExecuted(address indexed merchant, uint256 giftAmountIn, uint256 reserveAmountOut, uint256 timestamp);

    event MerchantAdded(address indexed merchant, uint256 timestamp);
    event MerchantRemoved(address indexed merchant, uint256 timestamp);
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event ReserveDeposited(uint256 amount, uint256 timestamp);
    event ReserveWithdrawn(uint256 amount, address indexed to, uint256 timestamp);
    event MinAmountsUpdated(uint256 minBuy, uint256 minRedeem, uint256 timestamp);

    // Modificadores
    modifier onlyMerchant() {
        _onlyMerchant();
        _;
    }

    /**
     * @dev Construtor
     * @param _giftToken Endereço do GIFT Token
     * @param _reserveToken Endereço do Reserve Token
     * @param _exchangeRate Taxa inicial (com RATE_DECIMALS)
     * @param _minBuyAmount Valor mínimo para compra
     * @param _minRedeemAmount Valor mínimo para resgate
     */
    constructor(
        address _giftToken,
        address _reserveToken,
        uint256 _exchangeRate,
        uint256 _minBuyAmount,
        uint256 _minRedeemAmount
    ) Ownable(msg.sender) {
        require(_giftToken != address(0), "ReservePool: zero gift token address");
        require(_reserveToken != address(0), "ReservePool: zero reserve token address");
        require(_giftToken != _reserveToken, "ReservePool: tokens must be different");
        require(_exchangeRate > 0, "ReservePool: exchange rate must be greater than 0");

        GIFT_TOKEN = _giftToken;
        RESERVE_TOKEN = _reserveToken;
        exchangeRate = _exchangeRate;
        minBuyAmount = _minBuyAmount;
        minRedeemAmount = _minRedeemAmount;
    }

    /**
     * @dev Compra GIFT Token usando Reserve Token
     * @param reserveAmountIn Quantidade de Reserve Token a depositar
     * @return giftAmountOut Quantidade de GIFT recebida
     */
    function buyGiftToken(uint256 reserveAmountIn) external whenNotPaused nonReentrant returns (uint256 giftAmountOut) {
        require(reserveAmountIn >= minBuyAmount, "ReservePool: amount below minimum");

        // Calcula quantidade de GIFT a emitir
        giftAmountOut = (reserveAmountIn * exchangeRate) / (10 ** RATE_DECIMALS);
        require(giftAmountOut > 0, "ReservePool: output amount is zero");

        // Transfere Reserve Token do usuário para o pool
        IERC20(RESERVE_TOKEN).safeTransferFrom(msg.sender, address(this), reserveAmountIn);

        // Mint GIFT Token para o usuário
        IGiftToken(GIFT_TOKEN).mint(msg.sender, giftAmountOut);

        // Atualiza estatísticas
        totalBought += giftAmountOut;
        buyCount++;

        emit BuyExecuted(msg.sender, reserveAmountIn, giftAmountOut, block.timestamp);

        return giftAmountOut;
    }

    /**
     * @dev Resgata Reserve Token usando GIFT Token (apenas merchants)
     * @param giftAmountIn Quantidade de GIFT a resgatar
     * @return reserveAmountOut Quantidade de Reserve Token recebida
     */
    function redeemGiftToken(uint256 giftAmountIn)
        external
        onlyMerchant
        whenNotPaused
        nonReentrant
        returns (uint256 reserveAmountOut)
    {
        require(giftAmountIn >= minRedeemAmount, "ReservePool: amount below minimum");

        // Calcula quantidade de Reserve Token a pagar
        reserveAmountOut = (giftAmountIn * (10 ** RATE_DECIMALS)) / exchangeRate;
        require(reserveAmountOut > 0, "ReservePool: output amount is zero");

        // Verifica liquidez
        uint256 poolBalance = IERC20(RESERVE_TOKEN).balanceOf(address(this));
        require(poolBalance >= reserveAmountOut, "ReservePool: insufficient reserve liquidity");

        // Transfere GIFT do merchant para o pool
        IERC20(GIFT_TOKEN).safeTransferFrom(msg.sender, address(this), giftAmountIn);

        // Burn do GIFT
        IGiftToken(GIFT_TOKEN).burn(address(this), giftAmountIn);

        // Transfere Reserve Token para o merchant
        IERC20(RESERVE_TOKEN).safeTransfer(msg.sender, reserveAmountOut);

        // Atualiza estatísticas
        totalRedeemed += giftAmountIn;
        redeemCount++;

        emit RedeemExecuted(msg.sender, giftAmountIn, reserveAmountOut, block.timestamp);

        return reserveAmountOut;
    }

    /**
     * @dev Adiciona um comerciante autorizado
     * @param merchantAddress Endereço do comerciante
     */
    function addMerchant(address merchantAddress) external onlyOwner {
        require(merchantAddress != address(0), "ReservePool: zero address");
        require(!merchants[merchantAddress], "ReservePool: merchant already exists");

        merchants[merchantAddress] = true;
        merchantList.push(merchantAddress);

        emit MerchantAdded(merchantAddress, block.timestamp);
    }

    /**
     * @dev Remove um comerciante autorizado
     * @param merchantAddress Endereço do comerciante
     */
    function removeMerchant(address merchantAddress) external onlyOwner {
        require(merchants[merchantAddress], "ReservePool: merchant does not exist");

        merchants[merchantAddress] = false;

        // Remove do array
        for (uint256 i = 0; i < merchantList.length; i++) {
            if (merchantList[i] == merchantAddress) {
                merchantList[i] = merchantList[merchantList.length - 1];
                merchantList.pop();
                break;
            }
        }

        emit MerchantRemoved(merchantAddress, block.timestamp);
    }

    /**
     * @dev Verifica se um endereço é merchant
     * @param account Endereço a verificar
     * @return bool True se é merchant
     */
    function isMerchant(address account) external view returns (bool) {
        return merchants[account];
    }

    /**
     * @dev Retorna todos os merchants
     * @return address[] Array de merchants
     */
    function getAllMerchants() external view returns (address[] memory) {
        return merchantList;
    }

    /**
     * @dev Retorna quantidade de merchants
     * @return uint256 Número de merchants
     */
    function getMerchantCount() external view returns (uint256) {
        return merchantList.length;
    }

    /**
     * @dev Atualiza a taxa de câmbio
     * @param newRate Nova taxa
     */
    function updateExchangeRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "ReservePool: rate must be greater than 0");

        uint256 oldRate = exchangeRate;
        exchangeRate = newRate;

        emit ExchangeRateUpdated(oldRate, newRate, block.timestamp);
    }

    /**
     * @dev Atualiza valores mínimos
     * @param _minBuyAmount Novo mínimo para compra
     * @param _minRedeemAmount Novo mínimo para resgate
     */
    function updateMinAmounts(uint256 _minBuyAmount, uint256 _minRedeemAmount) external onlyOwner {
        minBuyAmount = _minBuyAmount;
        minRedeemAmount = _minRedeemAmount;

        emit MinAmountsUpdated(_minBuyAmount, _minRedeemAmount, block.timestamp);
    }

    /**
     * @dev Retorna informações da taxa de câmbio
     * @return rate Taxa atual
     * @return decimals Decimais da taxa
     */
    function getExchangeRate() external view returns (uint256 rate, uint8 decimals) {
        return (exchangeRate, RATE_DECIMALS);
    }

    /**
     * @dev Deposita Reserve Token no pool (adiciona liquidez)
     * @param amount Quantidade a depositar
     */
    function depositReserve(uint256 amount) external onlyOwner {
        require(amount > 0, "ReservePool: amount must be greater than 0");

        IERC20(RESERVE_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        emit ReserveDeposited(amount, block.timestamp);
    }

    /**
     * @dev Retira Reserve Token do pool
     * @param amount Quantidade a retirar
     */
    function withdrawReserve(uint256 amount) external onlyOwner {
        require(amount > 0, "ReservePool: amount must be greater than 0");

        uint256 balance = IERC20(RESERVE_TOKEN).balanceOf(address(this));
        require(balance >= amount, "ReservePool: insufficient balance");

        IERC20(RESERVE_TOKEN).safeTransfer(msg.sender, amount);

        emit ReserveWithdrawn(amount, msg.sender, block.timestamp);
    }

    /**
     * @dev Retorna saldo de Reserve Token no pool
     * @return uint256 Saldo disponível
     */
    function getReserveBalance() external view returns (uint256) {
        return IERC20(RESERVE_TOKEN).balanceOf(address(this));
    }

    /**
     * @dev Retorna saldo de GIFT Token no pool
     * @return uint256 Saldo disponível
     */
    function getGiftTokenBalance() external view returns (uint256) {
        return IERC20(GIFT_TOKEN).balanceOf(address(this));
    }

    /**
     * @dev Retorna métricas do pool
     * return PoolMetrics Estrutura com todas as métricas
     */
    function getPoolMetrics()
        external
        view
        returns (
            uint256 _totalBought,
            uint256 _totalRedeemed,
            uint256 _reserveBalance,
            uint256 _merchantCount,
            uint256 _buyCount,
            uint256 _redeemCount
        )
    {
        return (
            totalBought,
            totalRedeemed,
            IERC20(RESERVE_TOKEN).balanceOf(address(this)),
            merchantList.length,
            buyCount,
            redeemCount
        );
    }

    /**
     * @dev Calcula quanto GIFT você recebe por uma quantidade de Reserve Token
     * @param reserveAmount Quantidade de Reserve Token
     * @return giftAmount Quantidade de GIFT que será recebida
     */
    function calculateBuyOutput(uint256 reserveAmount) external view returns (uint256 giftAmount) {
        return (reserveAmount * exchangeRate) / (10 ** RATE_DECIMALS);
    }

    /**
     * @dev Calcula quanto Reserve Token você recebe por uma quantidade de GIFT
     * @param giftAmount Quantidade de GIFT
     * @return reserveAmount Quantidade de Reserve Token que será recebida
     */
    function calculateRedeemOutput(uint256 giftAmount) external view returns (uint256 reserveAmount) {
        return (giftAmount * (10 ** RATE_DECIMALS)) / exchangeRate;
    }

    /**
     * @dev Pausa operações do pool
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Despausa operações do pool
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Retira tokens ERC20 enviados por engano
     * @param token Endereço do token
     * @param amount Quantidade
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != RESERVE_TOKEN, "ReservePool: use withdrawReserve for reserve token");
        require(token != GIFT_TOKEN, "ReservePool: cannot withdraw GIFT token");

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _onlyMerchant() internal view {
        require(merchants[msg.sender], "ReservePool: caller is not a merchant");
    }
}
