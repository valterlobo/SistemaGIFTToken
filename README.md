# 📋 Especificação Técnica Completa - Sistema GIFT Token

## 🎯 Visão Geral do Sistema

Sistema de token de garantia real (GIFT) baseado em múltiplos pools de reserva, permitindo conversão bidirecional entre GIFT e diferentes tokens de reserva (BR, USDT, HEAD, etc.) com taxas de câmbio configuráveis.

### Arquitetura de 3 Camadas

```
┌─────────────────────────────────────────┐
│         Factory/Manager Contract        │
│  (Criação e gestão de Reserve Pools)   │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
┌───────▼────────┐  ┌──────▼─────────┐
│ Reserve Pool 1 │  │ Reserve Pool 2 │  ...
│  (BR Token)    │  │  (USDT Token)  │
└───────┬────────┘  └──────┬─────────┘
        │                   │
        └─────────┬─────────┘
                  │
        ┌─────────▼─────────┐
        │   GIFT Token      │
        │   (ERC-20)        │
        └───────────────────┘
```

---

## 🎁 1. GIFT Token Contract (ERC-20 Extendido)

### Especificações Básicas

| Propriedade | Valor | Descrição |
|-------------|-------|-----------|
| **Standard** | ERC-20 | Totalmente compatível com padrão ERC-20 |
| **Name** | `string` | "GIFT TOKEN" (configurável) |
| **Symbol** | `string` | "GIFT" (configurável) |
| **Decimals** | `uint8` | 18 (padrão recomendado) |
| **Total Supply** | `uint256` | Dinâmico (mint/burn conforme necessidade) |

### Funções Principais

#### Funções ERC-20 Padrão
```solidity
function transfer(address to, uint256 amount) external returns (bool)
function approve(address spender, uint256 amount) external returns (bool)
function transferFrom(address from, address to, uint256 amount) external returns (bool)
function balanceOf(address account) external view returns (uint256)
function allowance(address owner, address spender) external view returns (uint256)
```

#### Funções Estendidas para Pools

```solidity
function mint(address to, uint256 amount) external onlyAuthorizedPool
function burn(address from, uint256 amount) external onlyAuthorizedPool
```

### Controle de Acesso

| Função | Acesso | Descrição |
|--------|--------|-----------|
| `addAuthorizedPool(address pool)` | `onlyOwner` | Autoriza um Reserve Pool a fazer mint/burn |
| `removeAuthorizedPool(address pool)` | `onlyOwner` | Remove autorização de um Pool |
| `isAuthorizedPool(address pool)` | `public view` | Verifica se um endereço é Pool autorizado |

### Eventos

```solidity
event PoolAuthorized(address indexed pool, uint256 timestamp)
event PoolRevoked(address indexed pool, uint256 timestamp)
event EmergencyPause(address indexed by, uint256 timestamp)
event EmergencyUnpause(address indexed by, uint256 timestamp)
```

---

## 🏦 2. Reserve Pool Contract

### Estado do Contrato

| Variável | Tipo | Visibilidade | Descrição |
|----------|------|--------------|-----------|
| `giftToken` | `address` | `immutable` | Endereço do contrato GIFT Token |
| `reserveToken` | `address` | `immutable` | Endereço do token de reserva (BR, USDT, HEAD) |
| `exchangeRate` | `uint256` | `public` | Taxa: quantos GIFT por 1 Reserve Token (com decimais) |
| `rateDecimals` | `uint8` | `public` | Decimais da taxa de câmbio (padrão: 18) |
| `merchants` | `mapping(address => bool)` | `private` | Comerciantes autorizados para resgate |
| `totalBought` | `uint256` | `public` | Total de GIFT comprado através deste pool |
| `totalRedeemed` | `uint256` | `public` | Total de GIFT resgatado através deste pool |
| `isPaused` | `bool` | `public` | Estado de pausa do contrato |
| `owner` | `address` | `public` | Proprietário do pool |

### Função: Buy GIFT Token

```solidity
function buyGiftToken(uint256 reserveAmountIn) 
    external 
    whenNotPaused 
    nonReentrant 
    returns (uint256 giftAmountOut)
```

**Parâmetros:**
- `reserveAmountIn`: Quantidade do Reserve Token a ser depositada

**Lógica Detalhada:**

1. **Validações Iniciais**
   - ✅ Verificar se `reserveAmountIn > 0`
   - ✅ Verificar se contrato não está pausado
   - ✅ Verificar se caller não é um contrato (opcional, segurança)

2. **Transferência do Reserve Token**
   ```solidity
   require(
       IERC20(reserveToken).transferFrom(msg.sender, address(this), reserveAmountIn),
       "Transfer failed"
   )
   ```

3. **Cálculo do GIFT a Emitir**
   ```solidity
   giftAmountOut = (reserveAmountIn * exchangeRate) / (10 ** rateDecimals)
   ```

4. **Mint e Transferência do GIFT**
   ```solidity
   IGiftToken(giftToken).mint(msg.sender, giftAmountOut)
   ```

5. **Atualização de Estatísticas**
   ```solidity
   totalBought += giftAmountOut
   ```

6. **Emissão de Evento**
   ```solidity
   emit BuyExecuted(msg.sender, reserveAmountIn, giftAmountOut, block.timestamp)
   ```

**Retorno:**
- `giftAmountOut`: Quantidade de GIFT recebida

---

### Função: Redeem GIFT Token

```solidity
function redeemGiftToken(uint256 giftAmountIn) 
    external 
    onlyMerchant 
    whenNotPaused 
    nonReentrant 
    returns (uint256 reserveAmountOut)
```

**Parâmetros:**
- `giftAmountIn`: Quantidade de GIFT a ser resgatada

**Lógica Detalhada:**

1. **Validações Iniciais**
   - ✅ Verificar se `msg.sender` está em `merchants`
   - ✅ Verificar se `giftAmountIn > 0`
   - ✅ Verificar se contrato não está pausado

2. **Transferência do GIFT**
   ```solidity
   require(
       IERC20(giftToken).transferFrom(msg.sender, address(this), giftAmountIn),
       "GIFT transfer failed"
   )
   ```

3. **Cálculo do Reserve Token a Pagar**
   ```solidity
   reserveAmountOut = (giftAmountIn * (10 ** rateDecimals)) / exchangeRate
   ```

4. **Verificação de Liquidez**
   ```solidity
   uint256 poolBalance = IERC20(reserveToken).balanceOf(address(this))
   require(poolBalance >= reserveAmountOut, "Insufficient reserve liquidity")
   ```

5. **Transferência do Reserve Token**
   ```solidity
   require(
       IERC20(reserveToken).transfer(msg.sender, reserveAmountOut),
       "Reserve transfer failed"
   )
   ```

6. **Burn do GIFT**
   ```solidity
   IGiftToken(giftToken).burn(address(this), giftAmountIn)
   ```

7. **Atualização de Estatísticas**
   ```solidity
   totalRedeemed += giftAmountIn
   ```

8. **Emissão de Evento**
   ```solidity
   emit RedeemExecuted(msg.sender, giftAmountIn, reserveAmountOut, block.timestamp)
   ```

**Retorno:**
- `reserveAmountOut`: Quantidade de Reserve Token recebida

---

### Funções de Gerenciamento

#### Gerenciamento de Comerciantes

```solidity
function addMerchant(address merchantAddress) external onlyOwner
function removeMerchant(address merchantAddress) external onlyOwner
function isMerchant(address account) external view returns (bool)
function getMerchantCount() external view returns (uint256)
```

#### Gerenciamento de Taxa de Câmbio

```solidity
function updateExchangeRate(uint256 newRate) external onlyOwner
function getExchangeRate() external view returns (uint256 rate, uint8 decimals)
```

**Importante:** Alterações na taxa devem emitir evento e ter delay de segurança (timelock).

#### Gestão de Liquidez

```solidity
function depositReserve(uint256 amount) external onlyOwner
function withdrawReserve(uint256 amount) external onlyOwner
function getReserveBalance() external view returns (uint256)
```

#### Controles de Emergência

```solidity
function pause() external onlyOwner
function unpause() external onlyOwner
function emergencyWithdraw(address token, uint256 amount) external onlyOwner
```

---

### Eventos do Pool

```solidity
event BuyExecuted(
    address indexed buyer,
    uint256 reserveAmountIn,
    uint256 giftAmountOut,
    uint256 timestamp
)

event RedeemExecuted(
    address indexed merchant,
    uint256 giftAmountIn,
    uint256 reserveAmountOut,
    uint256 timestamp
)

event MerchantAdded(address indexed merchant, uint256 timestamp)
event MerchantRemoved(address indexed merchant, uint256 timestamp)
event ExchangeRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp)
event ReserveDeposited(uint256 amount, uint256 timestamp)
event ReserveWithdrawn(uint256 amount, address indexed to, uint256 timestamp)
```

---

## 🏭 3. Factory/Manager Contract

### Responsabilidades

1. **Criação de Pools**: Deploy de novos Reserve Pools
2. **Registro**: Manter lista de todos os pools criados
3. **Governança**: Gestão centralizada de parâmetros globais

### Estado do Contrato

```solidity
address public giftToken;
address[] public allPools;
mapping(address => bool) public isValidPool;
mapping(address => address[]) public poolsByReserveToken;
uint256 public poolCount;
```

### Funções Principais

#### Criar Novo Pool

```solidity
function createReservePool(
    address reserveToken,
    uint256 exchangeRate,
    uint8 rateDecimals
) external onlyOwner returns (address newPool)
```

**Validações:**
- Reserve token não pode ser address(0)
- Exchange rate deve ser > 0
- Reserve token não pode ser o próprio GIFT
- Deve evitar pools duplicados para o mesmo reserve token

**Processo:**
1. Deploy do contrato ReservePool
2. Autorizar pool no GIFT Token
3. Registrar pool no Factory
4. Emitir evento
5. Retornar endereço do novo pool

#### Consultas

```solidity
function getAllPools() external view returns (address[] memory)
function getPoolsByReserveToken(address reserveToken) external view returns (address[] memory)
function getPoolInfo(address pool) external view returns (
    address reserveToken,
    uint256 exchangeRate,
    uint256 totalBought,
    uint256 totalRedeemed,
    bool isPaused
)
```

### Eventos do Factory

```solidity
event PoolCreated(
    address indexed pool,
    address indexed reserveToken,
    uint256 exchangeRate,
    uint256 timestamp
)

event PoolDisabled(address indexed pool, uint256 timestamp)
```

---

## 📊 Exemplos de Configuração de Taxas

### Modelo de Cálculo

**Formato:** `exchangeRate` com `rateDecimals` decimais representa quantos GIFT você recebe por 1 Reserve Token.

**Fórmula Buy:**
```
GIFT_out = (Reserve_in × exchangeRate) / (10^rateDecimals)
```

**Fórmula Redeem:**
```
Reserve_out = (GIFT_in × 10^rateDecimals) / exchangeRate
```

### Exemplos Práticos

| Reserve Token | Relação Desejada | exchangeRate | rateDecimals | Exemplo Buy | Exemplo Redeem |
|---------------|------------------|--------------|--------------|-------------|----------------|
| **BR** | 1 BR = 10 GIFT | 10 × 10¹⁸ | 18 | 100 BR → 1,000 GIFT | 1,000 GIFT → 100 BR |
| **USDT** | 1 USDT = 1 GIFT | 1 × 10¹⁸ | 18 | 100 USDT → 100 GIFT | 100 GIFT → 100 USDT |
| **HEAD** | 1 HEAD = 0.2 GIFT | 0.2 × 10¹⁸ | 18 | 100 HEAD → 20 GIFT | 100 GIFT → 500 HEAD |
| **ETH** | 1 ETH = 2000 GIFT | 2000 × 10¹⁸ | 18 | 1 ETH → 2,000 GIFT | 2,000 GIFT → 1 ETH |

---

## 🔒 Segurança e Boas Práticas

### Padrões de Segurança Implementados

1. **ReentrancyGuard**: Proteção contra ataques de reentrada
2. **Pausable**: Capacidade de pausar operações em emergências
3. **Access Control**: Controle granular de permissões
4. **Checks-Effects-Interactions**: Ordem correta de operações
5. **SafeMath**: Prevenção de overflow/underflow (Solidity 0.8+)

### Verificações Críticas

#### No Buy:
- ✅ Aprovação prévia do Reserve Token
- ✅ Saldo suficiente do usuário
- ✅ Valor mínimo de compra (evitar spam)
- ✅ Verificação de slippage (opcional)

#### No Redeem:
- ✅ Autorização de merchant
- ✅ Liquidez suficiente no pool
- ✅ Aprovação prévia do GIFT Token
- ✅ Valor mínimo de resgate

### Auditoria e Testes

**Recomendações:**
- [ ] Auditoria de segurança profissional
- [ ] Testes unitários com 100% de cobertura
- [ ] Testes de integração entre contratos
- [ ] Testes de stress (limites e edge cases)
- [ ] Simulação de ataques conhecidos
- [ ] Análise estática de código (Slither, Mythril)

---

## 📈 Métricas e Monitoramento

### Métricas por Pool

```solidity
struct PoolMetrics {
    uint256 totalBought;        // Total GIFT comprado
    uint256 totalRedeemed;      // Total GIFT resgatado
    uint256 reserveBalance;     // Saldo atual de reserva
    uint256 merchantCount;      // Número de merchants ativos
    uint256 buyTransactionCount;    // Número de compras
    uint256 redeemTransactionCount; // Número de resgates
}
```

### Views Úteis

```solidity
function getPoolHealth(address pool) external view returns (
    uint256 reserveRatio,      // Reserve / GIFT em circulação
    uint256 utilizationRate,   // GIFT resgatado / GIFT comprado
    bool isHealthy
)

function getSystemStats() external view returns (
    uint256 totalPools,
    uint256 totalGiftSupply,
    uint256 totalReserveValue,
    uint256 totalMerchants
)
```

---

## 🚀 Fluxo de Implantação

### Ordem de Deploy

1. **Deploy GIFT Token**
   ```
   GiftToken.sol → Endereço: 0x...
   ```

2. **Deploy Factory**
   ```
   Factory.sol(giftTokenAddress) → Endereço: 0x...
   ```

3. **Criar Reserve Pools via Factory**
   ```
   factory.createReservePool(BR_ADDRESS, 10e18, 18)
   factory.createReservePool(USDT_ADDRESS, 1e18, 18)
   factory.createReservePool(HEAD_ADDRESS, 0.2e18, 18)
   ```

4. **Configuração Inicial dos Pools**
   ```
   pool.addMerchant(merchant1)
   pool.addMerchant(merchant2)
   pool.depositReserve(initialLiquidity)
   ```

### Checklist Pós-Deploy

- [ ] Verificar ownership dos contratos
- [ ] Autorizar pools no GIFT Token
- [ ] Adicionar comerciantes iniciais
- [ ] Depositar liquidez inicial nos pools
- [ ] Testar função buy com pequenos valores
- [ ] Testar função redeem com merchant autorizado
- [ ] Verificar eventos emitidos
- [ ] Configurar sistema de monitoramento
- [ ] Publicar ABIs e endereços

---

## 📚 Interfaces Solidity

### IGiftToken.sol
```solidity
interface IGiftToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
```

### IReservePool.sol
```solidity
interface IReservePool {
    function buyGiftToken(uint256 reserveAmountIn) external returns (uint256);
    function redeemGiftToken(uint256 giftAmountIn) external returns (uint256);
    function getExchangeRate() external view returns (uint256, uint8);
    function isMerchant(address account) external view returns (bool);
}
```

---

## ⚠️ Considerações Importantes

### Gestão de Liquidez
- Os pools precisam de liquidez suficiente em Reserve Token para honrar resgates
- Implementar mecanismos de alerta quando liquidez estiver baixa
- Considerar limites máximos de resgate por transação/período

### Atualização de Taxas
- Mudanças na exchangeRate devem ser graduais
- Implementar timelock para mudanças críticas
- Notificar usuários com antecedência

### Escalabilidade
- Considerar custos de gas nas operações
- Otimizar storage para reduzir custos
- Avaliar uso de Layer 2 para redução de taxas

### Conformidade
- Avaliar requisitos regulatórios por jurisdição
- Implementar KYC/AML se necessário
- Manter logs auditáveis de todas as transações

---


---

**Versão:** 2.0  
**Última Atualização:** Novembro 2025  
**Status:** Especificação Completa - Pronto para Implementação