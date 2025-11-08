# Guía Rápida de Deployment - YieldDonating Strategy

## Resumen

Este script despliega **dos contratos** en una sola transacción:
1. **YieldDonatingTokenizedStrategy** - Implementación base del sistema tokenizado
2. **YieldDonatingStrategy** - Estrategia específica que usa la implementación anterior

## Pasos Rápidos

### 1. Configurar el archivo `.env`

Copia `.env.example` a `.env` y configura:

```bash
cp .env.example .env
```

Edita `.env` con tus valores:

```bash
# RPC URL - Elige la red donde desplegar
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY

# Tu private key (NUNCA la compartas)
PRIVATE_KEY=0xYOUR_PRIVATE_KEY

# Configuración de la estrategia
YIELD_SOURCE=0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951    # Aave Pool u otro
ASSET=0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a           # Token (USDC, DAI, etc)
STRATEGY_NAME="YieldDonating Strategy"
MANAGEMENT=0xYOUR_MANAGEMENT_ADDRESS
KEEPER=0xYOUR_KEEPER_ADDRESS
EMERGENCY_ADMIN=0xYOUR_EMERGENCY_ADMIN_ADDRESS
DONATION_ADDRESS=0xYOUR_DONATION_ADDRESS                    # Dragon Router
ENABLE_BURNING=true
```

### 2. Compilar

```bash
forge build
```

### 3. Simular (Dry-run)

```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $SEPOLIA_RPC_URL
```

### 4. Desplegar

```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 5. Verificar en Etherscan (Opcional)

El script te mostrará las direcciones desplegadas. Anótalas y verifica:

**TokenizedStrategy:**
```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --compiler-version v0.8.25 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <TOKENIZED_STRATEGY_ADDRESS> \
  dependencies/octant-v2-core/src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol:YieldDonatingTokenizedStrategy
```

**Strategy:**
```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --compiler-version v0.8.25 \
  --constructor-args $(cast abi-encode "constructor(address,address,string,address,address,address,address,bool,address)" $YIELD_SOURCE $ASSET "$STRATEGY_NAME" $MANAGEMENT $KEEPER $EMERGENCY_ADMIN $DONATION_ADDRESS $ENABLE_BURNING <TOKENIZED_STRATEGY_ADDRESS>) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <STRATEGY_ADDRESS> \
  src/strategies/yieldDonating/YieldDonatingStrategy.sol:YieldDonatingStrategy
```

## Desplegar en Otras Redes

### Ethereum Mainnet
```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol \
  --rpc-url $ETH_RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Arbitrum
```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol \
  --rpc-url $ARBI_RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Polygon
```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol \
  --rpc-url $MATIC_RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Estructura del Deployment

```
DeployYieldDonatingStrategy.s.sol
├── 1. Lee variables del .env
├── 2. Despliega YieldDonatingTokenizedStrategy
├── 3. Despliega YieldDonatingStrategy
│   └── Usa la dirección del TokenizedStrategy
└── 4. Retorna ambas direcciones
```

## Parámetros Explicados

| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `YIELD_SOURCE` | Dirección del protocolo que genera yield | Aave Pool, Compound, etc. |
| `ASSET` | Token base de la estrategia | USDC, DAI, USDT |
| `STRATEGY_NAME` | Nombre de la estrategia | "YieldDonating Strategy" |
| `MANAGEMENT` | Dirección con permisos de management | EOA o multisig |
| `KEEPER` | Dirección que ejecuta harvests | EOA o bot |
| `EMERGENCY_ADMIN` | Dirección para emergencias | Multisig recomendado |
| `DONATION_ADDRESS` | Dirección que recibe donaciones (yield) | Dirección del Dragon Router |
| `ENABLE_BURNING` | Habilitar burning para pérdidas | true/false |

## Salida del Script

El script mostrará:

```
=================================================
=== YieldDonating Deployment Parameters ===
=================================================
Deployer: 0x...
Yield Source: 0x...
Asset: 0x...
Strategy Name: YieldDonating Strategy
Management: 0x...
Keeper: 0x...
Emergency Admin: 0x...
Donation Address (Dragon Router): 0x...
Enable Burning: true
=================================================

[1/2] Deploying YieldDonatingTokenizedStrategy...
YieldDonatingTokenizedStrategy deployed at: 0x...

[2/2] Deploying YieldDonatingStrategy...
YieldDonatingStrategy deployed at: 0x...

=================================================
=== Deployment Summary ===
=================================================
YieldDonatingTokenizedStrategy: 0x...
YieldDonatingStrategy: 0x...
=================================================
Deployment completed successfully!
=================================================
```

## Notas Importantes

1. **Seguridad**: NUNCA commitees tu archivo `.env` con la private key real
2. **Gas**: Ten suficiente ETH/token nativo para el gas del deployment
3. **Testing**: Siempre prueba primero en testnet (Sepolia)
4. **Verificación**: Verifica los contratos en Etherscan para transparencia
5. **Backup**: Guarda las direcciones desplegadas en un lugar seguro

## Troubleshooting

### Error: "insufficient funds"
- Verifica que tienes ETH suficiente para gas

### Error: "nonce too low"
- Ya desplegaste antes, revisa el broadcast folder para las direcciones

### Error: "contract creation code storage out of gas"
- Aumenta el gas limit en el script

### Error: "invalid opcode"
- Verifica que la versión del compilador sea compatible (0.8.25)

## Archivos Generados

Después del deployment encontrarás:

```
broadcast/
└── DeployYieldDonatingStrategy.s.sol/
    └── <CHAIN_ID>/
        └── run-latest.json    # Info del deployment
```

Este archivo contiene todas las transacciones y direcciones desplegadas.

## Próximos Pasos

1. Verificar contratos en Etherscan
2. Configurar permisos y roles
3. Realizar deposits de prueba
4. Monitorear la estrategia
5. Configurar automation para harvests (keeper)

---

Para más detalles, consulta [DEPLOYMENT.md](./DEPLOYMENT.md)
