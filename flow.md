# Flujo Completo de Tests - YieldDonating Strategy

## Arquitectura de Contratos

```
┌─────────────────────────────────────────────────────────────────┐
│                        CAPA DE TESTS                             │
│  YieldDonatingOperation.t.sol / YieldDonatingShutdown.t.sol     │
│                             ↓                                     │
│                   YieldDonatingSetup.sol                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    CONTRATOS DESPLEGADOS                         │
│                                                                   │
│  ┌──────────────────────────────────────────────────┐          │
│  │  YieldDonatingStrategy (Tu implementación)       │          │
│  │  - Hereda de BaseStrategy                        │          │
│  │  - Implementa _deployFunds, _freeFunds, etc.    │          │
│  └──────────────────┬───────────────────────────────┘          │
│                     │ usa                                        │
│  ┌──────────────────▼───────────────────────────────┐          │
│  │  BaseStrategy (@octant-core)                     │          │
│  │  - Lógica core de deposit/withdraw/report        │          │
│  │  - Manejo de profit/loss                         │          │
│  │  - Minting/burning de shares                     │          │
│  └──────────────────┬───────────────────────────────┘          │
│                     │ usa                                        │
│  ┌──────────────────▼───────────────────────────────┐          │
│  │  YieldDonatingTokenizedStrategy (@octant-core)   │          │
│  │  - Implementación ERC4626                        │          │
│  │  - Manejo de dragonRouter                        │          │
│  │  - Roles (management, keeper, emergencyAdmin)    │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                   │
│  ┌──────────────────────────────────────────────────┐          │
│  │  IYieldSource (Mock en tests)                    │          │
│  │  - Simula Aave/Compound/otros protocolos         │          │
│  └──────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Roles y Direcciones

```solidity
// Definidos en YieldDonatingSetup.sol
address user = 0x000000000000000000000000000000000000000a (address(10))
address management = 0x0000000000000000000000000000000000000001 (address(1))
address keeper = 0x0000000000000000000000000000000000000004 (address(4))
address dragonRouter = 0x0000000000000000000000000000000000000003 (address(3))
address emergencyAdmin = 0x0000000000000000000000000000000000000005 (address(5))
```

### Permisos por Rol

| Rol | Funciones que puede llamar | Propósito |
|-----|----------------------------|-----------|
| **user** | `deposit()`, `mint()`, `withdraw()`, `redeem()`, `transfer()` | Depositar/retirar fondos |
| **keeper** | `report()`, `tend()` | Ejecutar harvests y mantenimiento |
| **management** | `setDragonRouter()`, `setEnableBurning()`, `shutdown()`, etc. | Configurar estrategia |
| **emergencyAdmin** | `shutdownStrategy()`, `emergencyWithdraw()` | Emergencias y pausas |
| **dragonRouter** | (receptor pasivo) | Recibe shares de ganancias |

---

## Test 1: `test_profitableReport` - Flujo Completo

Este test simula el caso de uso principal: un usuario deposita, genera yield, y se reportan ganancias al dragonRouter.

### Setup Inicial (antes del test)

```solidity
// En YieldDonatingSetup.setUp()

1. Lee .env variables:
   - TEST_ASSET_ADDRESS (ej: USDC en mainnet)
   - TEST_YIELD_SOURCE (ej: Aave Pool)
   - ETH_RPC_URL (para fork de mainnet)

2. Despliega YieldDonatingTokenizedStrategy:
   tokenizedStrategyAddress = new YieldDonatingTokenizedStrategy()

3. Despliega YieldDonatingStrategy:
   strategy = new YieldDonatingStrategy(
       yieldSource,        // TEST_YIELD_SOURCE
       asset,              // TEST_ASSET_ADDRESS
       "YieldDonating Strategy",
       management,         // address(1)
       keeper,            // address(4)
       emergencyAdmin,    // address(5)
       dragonRouter,      // address(3)
       enableBurning = true,
       tokenizedStrategyAddress
   )
```

### Paso 1: Deposit (líneas 30-33)

```solidity
// Test llama:
mintAndDepositIntoStrategy(strategy, user, _amount)

// Internamente ejecuta:
function mintAndDepositIntoStrategy(strategy, user, _amount) {
    // 1. Airdrop tokens al user (simula que tiene fondos)
    deal(address(asset), user, _amount); // Foundry cheatcode

    // 2. User aprueba a la estrategia
    vm.prank(user);
    asset.approve(address(strategy), _amount);

    // 3. User deposita
    vm.prank(user);
    strategy.deposit(_amount, user);
}
```

**Flujo en `strategy.deposit(_amount, user)`:**

```
USER (0x...a)
   │
   │ 1. Llama deposit(_amount, user)
   ▼
┌─────────────────────────────────────────┐
│  BaseStrategy.deposit()                 │
│  (heredado por YieldDonatingStrategy)   │
├─────────────────────────────────────────┤
│  2. asset.transferFrom(user,            │
│     strategy, _amount)                  │
│                                         │
│  3. shares = convertToShares(_amount)   │
│     Primera vez: shares = _amount (1:1) │
│                                         │
│  4. _mint(user, shares)                 │
│     User recibe shares                  │
│                                         │
│  5. 🔥 _deployFunds(_amount) 🔥        │
│     ↓                                   │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  YieldDonatingStrategy._deployFunds()   │
│  (TU IMPLEMENTACIÓN)                    │
├─────────────────────────────────────────┤
│  6. yieldSource.supply(                 │
│        address(asset),                  │
│        _amount,                         │
│        address(this),                   │
│        0                                │
│     )                                   │
│                                         │
│     → Aave recibe los tokens            │
│     → Aave mintea aTokens a strategy    │
└─────────────────────────────────────────┘
```

**Estado después del deposit:**

```javascript
// Estrategia
strategy.totalAssets() = _amount
strategy.totalSupply() = _amount
strategy.balanceOf(user) = _amount shares

// Aave (yield source)
aToken.balanceOf(strategy) = _amount aTokens

// User
asset.balanceOf(user) = 0 (transfirió todo)
strategy.balanceOf(user) = _amount shares
```

---

### Paso 2: Simular Yield (líneas 36-37)

```solidity
skip(30 days); // Foundry avanza el tiempo 30 días
```

**Durante estos 30 días:**
- Aave genera intereses automáticamente
- Los aTokens del strategy aumentan de valor
- `aToken.balanceOf(strategy)` aumenta (ej: de 1000 USDC a 1003 USDC)
- **NADIE llama a ninguna función**, es pasivo

**Estado después de 30 días:**

```javascript
// Aave ha generado yield (ej: 3 USDC para 1000 USDC @ 3% APY)
aToken.balanceOf(strategy) = _amount + yield (ej: 1003 USDC)

// Pero la estrategia todavía NO SABE de este yield
strategy.totalAssets() = _amount (valor viejo, sin actualizar)
```

---

### Paso 3: Report (líneas 40-41) ⭐ **PASO CRÍTICO**

```solidity
vm.prank(keeper);
(uint256 profit, uint256 loss) = strategy.report();
```

**Flujo completo del report:**

```
KEEPER (0x...4)
   │
   │ 1. Llama report()
   ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.report()                              │
├─────────────────────────────────────────────────────┤
│  2. oldTotalAssets = totalAssets()                  │
│     = _amount (ej: 1000 USDC)                       │
│                                                     │
│  3. 🔥 newTotalAssets = _harvestAndReport() 🔥     │
│     ↓                                               │
└──────┬──────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  YieldDonatingStrategy._harvestAndReport()          │
│  (TU IMPLEMENTACIÓN)                                │
├─────────────────────────────────────────────────────┤
│  4. deployedAssets = aToken.balanceOf(strategy)     │
│     = _amount + yield (ej: 1003 USDC)               │
│                                                     │
│  5. idleAssets = asset.balanceOf(strategy)          │
│     = 0 (todo está desplegado)                      │
│                                                     │
│  6. return deployedAssets + idleAssets              │
│     = 1003 USDC                                     │
└──────┬──────────────────────────────────────────────┘
       │
       │ Retorna 1003 USDC
       ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.report() (continúa)                   │
├─────────────────────────────────────────────────────┤
│  7. Compara valores:                                │
│     newTotalAssets = 1003 USDC                      │
│     oldTotalAssets = 1000 USDC                      │
│                                                     │
│  8. if (newTotalAssets > oldTotalAssets) {          │
│       profit = 1003 - 1000 = 3 USDC                 │
│                                                     │
│       // 💰 MINTEAR SHARES AL DRAGONROUTER 💰      │
│       sharesToMint = convertToShares(profit)        │
│                    = (3 * 1000) / 1003              │
│                    ≈ 2.991 shares                   │
│                                                     │
│       _mint(dragonRouter, 2.991 shares)             │
│     }                                               │
│                                                     │
│  9. emit Reported(profit=3, loss=0,                 │
│                   totalAssets=1003)                 │
│                                                     │
│ 10. return (profit=3, loss=0)                       │
└─────────────────────────────────────────────────────┘
```

**Estado después del report:**

```javascript
// Estrategia actualizada
strategy.totalAssets() = 1003 USDC (actualizado)
strategy.totalSupply() = 1002.991 shares
strategy.balanceOf(user) = 1000 shares (sin cambios)
strategy.balanceOf(dragonRouter) = 2.991 shares (¡ganancias!)

// Valor por share
pricePerShare = 1003 / 1002.991 ≈ 1.0 USDC/share

// User mantiene su valor
user_value = 1000 shares * 1.0 = 1000 USDC (igual que depositó)

// DragonRouter tiene el yield
dragon_value = 2.991 shares * 1.0 ≈ 3 USDC (el profit)
```

---

### Paso 4: Verificaciones del Test (líneas 43-53)

```solidity
// 1. Verificar que hubo profit
assertGt(profit, 0, "!profit should equal expected yield");
// profit = 3 USDC ✓

// 2. Verificar que NO hubo loss
assertEq(loss, 0, "!loss should be 0");
// loss = 0 ✓

// 3. Verificar que dragonRouter recibió shares
uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
assertGt(dragonRouterShares, 0, "!dragon router shares");
// dragonRouterShares = 2.991 shares ✓

// 4. Verificar que esos shares valen el profit
uint256 dragonRouterAssets = strategy.convertToAssets(dragonRouterShares);
assertEq(dragonRouterAssets, profit, "!dragon router assets should equal profit");
// dragonRouterAssets = 2.991 * (1003/1002.991) ≈ 3 USDC ✓
```

---

### Paso 5: User Retira (líneas 55-61)

```solidity
uint256 balanceBefore = asset.balanceOf(user); // = 0

vm.prank(user);
strategy.redeem(_amount, user, user); // redeem 1000 shares

assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
```

**Flujo del redeem:**

```
USER (0x...a)
   │
   │ 1. Llama redeem(1000 shares, user, user)
   ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.redeem()                              │
├─────────────────────────────────────────────────────┤
│  2. Calcula assets a devolver:                      │
│     assets = convertToAssets(1000 shares)           │
│            = (1000 * 1003) / 1002.991               │
│            ≈ 1000 USDC                              │
│                                                     │
│  3. idle = asset.balanceOf(strategy) = 0            │
│     needed = 1000 - 0 = 1000 USDC                   │
│                                                     │
│  4. 🔥 _freeFunds(1000 USDC) 🔥                    │
│     ↓                                               │
└──────┬──────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  YieldDonatingStrategy._freeFunds()                 │
│  (TU IMPLEMENTACIÓN)                                │
├─────────────────────────────────────────────────────┤
│  5. yieldSource.withdraw(                           │
│        address(asset),                              │
│        1000 USDC,                                   │
│        address(this)                                │
│     )                                               │
│                                                     │
│     → Aave quema aTokens                            │
│     → Aave transfiere 1000 USDC a strategy          │
└──────┬──────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.redeem() (continúa)                   │
├─────────────────────────────────────────────────────┤
│  6. asset.transfer(user, 1000 USDC)                 │
│                                                     │
│  7. _burn(user, 1000 shares)                        │
│                                                     │
│  8. return 1000 USDC                                │
└─────────────────────────────────────────────────────┘
```

**Estado final:**

```javascript
// User recibió su capital
asset.balanceOf(user) = 1000 USDC ✓
strategy.balanceOf(user) = 0 shares

// DragonRouter mantiene las ganancias
strategy.balanceOf(dragonRouter) = 2.991 shares
dragonRouter_value = 2.991 * (3/2.991) ≈ 3 USDC

// Estrategia actualizada
strategy.totalAssets() = 3 USDC (solo quedan las ganancias)
strategy.totalSupply() = 2.991 shares
```

---

## Test 2: `test_shutdownCanWithdraw` - Flujo de Emergencia

Este test verifica que en caso de shutdown, los usuarios pueden retirar.

### Paso 1-2: Setup y Deposit (líneas 14-17)

```solidity
mintAndDepositIntoStrategy(strategy, user, _amount);
skip(30 days);
```

(Igual que en test anterior)

---

### Paso 3: Shutdown (líneas 22-24)

```solidity
vm.prank(emergencyAdmin);
strategy.shutdownStrategy();
```

**Flujo del shutdown:**

```
EMERGENCY ADMIN (0x...5)
   │
   │ 1. Llama shutdownStrategy()
   ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.shutdownStrategy()                    │
├─────────────────────────────────────────────────────┤
│  2. require(msg.sender == emergencyAdmin)           │
│     ✓ Verificado                                    │
│                                                     │
│  3. isShutdown = true                               │
│                                                     │
│  4. emit StrategyShutdown()                         │
└─────────────────────────────────────────────────────┘
```

**Efectos del shutdown:**

- `deposit()` y `mint()` → REVERTIRÁN
- `withdraw()` y `redeem()` → SIGUEN FUNCIONANDO ✓
- `report()` → No se ejecuta más
- `emergencyWithdraw()` → Ahora disponible para management

---

### Paso 4: User Retira Después de Shutdown (líneas 29-35)

```solidity
uint256 balanceBefore = asset.balanceOf(user);

vm.prank(user);
strategy.redeem(_amount, user, user);

assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
```

**Flujo:** (Igual que redeem normal, pero sin posibilidad de nuevos deposits)

**Resultado:** User puede retirar sus fondos completamente ✓

---

## Test 3: `test_emergencyWithdraw_maxUint` - Retiro de Emergencia

### Paso 1-3: Setup, Deposit, Skip, Shutdown (líneas 41-51)

(Igual que test anterior)

---

### Paso 4: Emergency Withdraw (líneas 56-57)

```solidity
vm.prank(emergencyAdmin);
strategy.emergencyWithdraw(type(uint256).max);
```

**Flujo del emergency withdraw:**

```
EMERGENCY ADMIN (0x...5)
   │
   │ 1. Llama emergencyWithdraw(type(uint256).max)
   ▼
┌─────────────────────────────────────────────────────┐
│  BaseStrategy.emergencyWithdraw()                   │
├─────────────────────────────────────────────────────┤
│  2. require(isShutdown == true)                     │
│     ✓ Verificado                                    │
│                                                     │
│  3. require(msg.sender == emergencyAdmin)           │
│     ✓ Verificado                                    │
│                                                     │
│  4. 🔥 _emergencyWithdraw(type(uint256).max) 🔥    │
│     ↓                                               │
└──────┬──────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  YieldDonatingStrategy._emergencyWithdraw()         │
│  (TU IMPLEMENTACIÓN)                                │
├─────────────────────────────────────────────────────┤
│  5. yieldSource.withdraw(                           │
│        address(asset),                              │
│        type(uint256).max, // Retira todo            │
│        address(this)                                │
│     )                                               │
│                                                     │
│     → Aave retira todos los aTokens posibles        │
│     → Transfiere USDC a strategy                    │
└─────────────────────────────────────────────────────┘
```

**Propósito:**
- Liberar fondos de yield source en emergencia
- Permite luego hacer report() para actualizar accounting
- O permitir que users retiren directamente

---

## Resumen de Contratos Involucrados

### 1. **YieldDonatingStrategy** (Tu código)
- **Archivo:** `src/strategies/yieldDonating/YieldDonatingStrategy.sol`
- **Hereda:** `BaseStrategy`
- **Responsabilidad:** Implementar lógica específica de yield source
- **Funciones clave:**
  - `_deployFunds()` - Desplegar a Aave
  - `_freeFunds()` - Retirar de Aave
  - `_harvestAndReport()` - Calcular total assets
  - `_emergencyWithdraw()` - Retiro forzado

### 2. **BaseStrategy** (`@octant-core/core/BaseStrategy.sol`)
- **Origen:** Librería Octant Core
- **Responsabilidad:** Lógica core de la estrategia
- **Funciones clave:**
  - `deposit()` / `withdraw()` / `redeem()` - Interacción users
  - `report()` - Calcula profit/loss, mintea/quema shares
  - `shutdownStrategy()` - Pausa deposits
  - `emergencyWithdraw()` - Wrapper para emergencias

### 3. **YieldDonatingTokenizedStrategy** (`@octant-core`)
- **Origen:** Librería Octant Core
- **Responsabilidad:** Implementación ERC4626 con dragonRouter
- **Funciones clave:**
  - Manejo de `dragonRouter` address
  - Control de roles (management, keeper, etc.)
  - `setDragonRouter()` / `finalizeDragonRouterChange()`
  - `setEnableBurning()` / `enableBurning` flag

### 4. **IYieldSource** (Mock en tests)
- **En producción:** Aave, Compound, Yearn, etc.
- **En tests:** Mock que simula yield generation
- **Funciones:**
  - `supply()` / `deposit()` - Desplegar fondos
  - `withdraw()` / `redeem()` - Retirar fondos
  - `balanceOf()` - Consultar balance

### 5. **ERC20 Asset** (USDC, DAI, WETH, etc.)
- **En tests:** Token del fork de mainnet
- **Funciones:** `transfer()`, `approve()`, `balanceOf()`

---

## Diagrama de Flujo Completo - Caso Real

```
┌────────────────┐
│  SETUP (ONCE)  │
└────────┬───────┘
         │
         ├─→ Deploy YieldDonatingTokenizedStrategy
         ├─→ Deploy YieldDonatingStrategy(tokenizedStrategy, roles...)
         └─→ Strategy aprueba a YieldSource (Aave)

┌──────────────────────────────────────────────────────────┐
│  OPERACIÓN NORMAL (CICLO REPETITIVO)                     │
└──────────────────────────────────────────────────────────┘

1. USER DEPOSIT
   User → strategy.deposit(1000 USDC)
      → BaseStrategy.deposit()
         → asset.transferFrom(user, strategy, 1000)
         → _mint(user, 1000 shares)
         → _deployFunds(1000)
            → YieldSource.supply(1000 USDC)
               → Aave mintea aTokens

   [Estado: User tiene 1000 shares, Strategy tiene aTokens]

2. TIEMPO PASA (yield acumula pasivamente)
   skip(30 days)
   [Aave genera yield: aTokens ahora valen 1003 USDC]

3. KEEPER REPORT
   Keeper → strategy.report()
      → BaseStrategy.report()
         → _harvestAndReport()
            → aToken.balanceOf(strategy) = 1003
            → return 1003
         → profit = 1003 - 1000 = 3 USDC
         → _mint(dragonRouter, 2.991 shares)

   [Estado: User=1000 shares, Dragon=2.991 shares]

4. USER WITHDRAW
   User → strategy.redeem(1000 shares)
      → BaseStrategy.redeem()
         → assets = convertToAssets(1000) ≈ 1000 USDC
         → _freeFunds(1000)
            → YieldSource.withdraw(1000 USDC)
         → asset.transfer(user, 1000 USDC)
         → _burn(user, 1000 shares)

   [Estado: User tiene 1000 USDC, Dragon mantiene 2.991 shares]

┌──────────────────────────────────────────────────────────┐
│  FLUJO DE EMERGENCIA                                     │
└──────────────────────────────────────────────────────────┘

5. EMERGENCY SHUTDOWN
   EmergencyAdmin → strategy.shutdownStrategy()
      → isShutdown = true
      → Deposits bloqueados, withdrawals permitidos

6. EMERGENCY WITHDRAW (opcional)
   EmergencyAdmin → strategy.emergencyWithdraw(max)
      → _emergencyWithdraw(max)
         → YieldSource.withdraw(max)
      → Fondos liberados a strategy

7. USERS WITHDRAW (después de shutdown)
   User → strategy.redeem(shares)
      → (funciona normalmente)
```

---

## Matemáticas Clave

### Conversión Shares ↔ Assets

```solidity
// De assets a shares (en deposit)
shares = (assets * totalSupply) / totalAssets

// Primera deposición especial
if (totalSupply == 0) {
    shares = assets; // 1:1 ratio
}

// De shares a assets (en withdraw)
assets = (shares * totalAssets) / totalSupply
```

### Ejemplo Numérico

**Estado inicial:**
```
totalAssets = 1000 USDC
totalSupply = 1000 shares
User balance = 1000 shares
```

**Después de yield (3 USDC):**
```
aToken balance = 1003 USDC
```

**Después de report():**
```
profit = 1003 - 1000 = 3 USDC
sharesToMint = (3 * 1000) / 1003 = 2.991 shares

Nueva state:
totalAssets = 1003 USDC
totalSupply = 1002.991 shares
User balance = 1000 shares (sin cambios)
Dragon balance = 2.991 shares (nuevo)

Price per share = 1003 / 1002.991 ≈ 1.000009 USDC/share
```

**User retira:**
```
User wants to redeem: 1000 shares
Assets = (1000 * 1003) / 1002.991 ≈ 1000.009 USDC

User recibe: ~1000 USDC (recupera su capital)
Dragon mantiene: 2.991 shares ≈ 3 USDC (el yield)
```

---

## Puntos Clave

1. **`_deployFunds`**: Automática en deposits, despliega a yield source
2. **`_freeFunds`**: Automática en withdrawals, retira de yield source
3. **`_harvestAndReport`**: Manual por keeper, calcula profit/loss y distribuye
4. **Profit → dragonRouter**: Todas las ganancias se mintean como shares al dragon
5. **User protegido**: Los users siempre recuperan su capital (o más con shield)
6. **Shield (burning)**: En caso de loss, quema shares del dragon para proteger users
7. **Shutdown**: Emergencia que bloquea deposits pero permite withdrawals

¿Necesitas que profundice en alguna parte específica? 🎯
