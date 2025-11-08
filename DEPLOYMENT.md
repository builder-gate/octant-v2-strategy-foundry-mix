# YieldDonatingStrategy Deployment

## Deployment Information

### Sepolia Testnet

**Contract Address:** `0xE120B9566F05d006228D5D1778C9d31477C1C14B`

**Deployment Parameters:**
- **Yield Source:** `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951`
- **Asset:** `0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a`
- **Strategy Name:** "Builder Gate"
- **Management:** `0xEBdf70B26e5e7520B8B79e1D01eD832f48972B09`
- **Keeper:** `0xEBdf70B26e5e7520B8B79e1D01eD832f48972B09`
- **Emergency Admin:** `0xEBdf70B26e5e7520B8B79e1D01eD832f48972B09`
- **Donation Address:** `0xEBdf70B26e5e7520B8B79e1D01eD832f48972B09`
- **Enable Burning:** `true`
- **Tokenized Strategy Address:** `0xEBdf70B26e5e7520B8B79e1D01eD832f48972B09`

**Network:** Sepolia (Chain ID: 11155111)

**View on Etherscan:** https://sepolia.etherscan.io/address/0xE120B9566F05d006228D5D1778C9d31477C1C14B

## How to Deploy

### Prerequisites
1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
2. Configure your `.env` file with the required parameters (see `.env.example`)

### Deployment Steps

El script desplegará automáticamente ambos contratos en orden:
1. **YieldDonatingTokenizedStrategy** (implementación/singleton)
2. **YieldDonatingStrategy** (estrategia que usa la implementación anterior)

#### 1. Compilar los contratos
```bash
forge build
```

#### 2. Simular deployment (dry-run)
```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $SEPOLIA_RPC_URL
```

#### 3. Desplegar a Sepolia
```bash
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

O con otra red:
```bash
# Ethereum Mainnet
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $ETH_RPC_URL --broadcast --private-key $PRIVATE_KEY

# Arbitrum
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $ARBI_RPC_URL --broadcast --private-key $PRIVATE_KEY

# Polygon
source .env && forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $MATIC_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### 4. Verificar contratos en Etherscan (opcional)

**YieldDonatingTokenizedStrategy:**
```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --compiler-version v0.8.25 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <TOKENIZED_STRATEGY_ADDRESS> \
  dependencies/octant-v2-core/src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol:YieldDonatingTokenizedStrategy
```

**YieldDonatingStrategy:**
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

## Environment Variables

Variables requeridas en el archivo `.env`:

```bash
# RPC URLs
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
ETH_RPC_URL=https://rpc.ankr.com/eth
ARBI_RPC_URL=https://arb1.arbitrum.io/rpc
MATIC_RPC_URL=https://rpc.ankr.com/polygon

# Private Key (NO COMPARTIR, NO COMMITEAR)
PRIVATE_KEY=0xYOUR_PRIVATE_KEY

# Etherscan API Key (para verificación)
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY

# Parámetros de la Estrategia
YIELD_SOURCE=0xYOUR_YIELD_SOURCE_ADDRESS        # Dirección del protocolo de yield (ej: Aave Pool)
ASSET=0xYOUR_ASSET_ADDRESS                      # Token base (ej: USDC, DAI)
STRATEGY_NAME="YieldDonating Strategy"          # Nombre de la estrategia
MANAGEMENT=0xYOUR_MANAGEMENT_ADDRESS            # Dirección con rol de management
KEEPER=0xYOUR_KEEPER_ADDRESS                    # Dirección con rol de keeper
EMERGENCY_ADMIN=0xYOUR_EMERGENCY_ADMIN_ADDRESS  # Dirección con rol de emergency admin
DONATION_ADDRESS=0xYOUR_DONATION_ADDRESS        # Dirección que recibe las donaciones (Dragon Router)
ENABLE_BURNING=true                              # Habilitar burning para protección de pérdidas
```

**NOTA:** El parámetro `TOKENIZED_STRATEGY_ADDRESS` ya NO es necesario, ya que el script despliega automáticamente el contrato YieldDonatingTokenizedStrategy.

## Gas Usage

- **Estimated Gas:** 677,755 units
- **Gas Price:** 0.001000016 gwei
- **Total Cost:** ~0.00000067776584408 ETH

## Transaction Details

The deployment transaction can be found in:
- `/broadcast/DeployYieldDonatingStrategy.s.sol/11155111/run-latest.json`

## Next Steps

After deployment, you may want to:

1. Verify the contract on Etherscan for transparency
2. Test the strategy functions (deposit, withdraw, harvest)
3. Set up proper permissions and roles
4. Monitor the strategy performance

## Security Considerations

- Ensure all role addresses are correct before deployment
- Keep your private keys secure and never commit them to version control
- Test thoroughly on testnet before mainnet deployment
- Consider a security audit for production deployments
