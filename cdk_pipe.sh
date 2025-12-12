#!/bin/bash
set -xEueo pipefail
trap 'echo "🔴 cdk_pipe.sh 执行失败: 行 $LINENO, 错误信息: $BASH_COMMAND"; exit 1' ERR

# 必须有环境变量 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY
if [ -z "$L2_CHAIN_ID" ] || [ -z "$L1_CHAIN_ID" ] || [ -z "$L1_RPC_URL" ] || [ -z "$L1_VAULT_PRIVATE_KEY" ] || [ -z "$L1_BRIDGE_RELAY_CONTRACT" ] || [ -z "$L1_REGISTER_BRIDGE_PRIVATE_KEY" ]; then
  echo "错误: 请设置 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY,L1_BRIDGE_RELAY_CONTRACT,L1_REGISTER_BRIDGE_PRIVATE_KEY 环境变量"
  echo "变量说明:"
  echo "  L2_CHAIN_ID: L2 链的 chain id"
  echo "  L1_CHAIN_ID: L1 链的 chain id"
  echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
  echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户，用于给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY 转账 L1 ETH"
  echo "  L1_BRIDGE_RELAY_CONTRACT: L1 中继合约地址"
  echo "  L1_REGISTER_BRIDGE_PRIVATE_KEY: L1 注册 bridge 的私钥"
  exit 1
fi

export L2_TYPE=0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCLAVE_NAME="cdk-gen"
NETWORK=${ENCLAVE_NAME#cdk-} # 移除 "cdk-" 前缀
NETWORK=${NETWORK//-/_} # 将 "-" 替换为 "_"
mkdir -p "$DIR"/output

# 查看命令相关工具是否都存在
command -v cast >/dev/null 2>&1 || { echo "未找到 cast"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "未找到 jq"; exit 1; }
command -v pm2 >/dev/null 2>&1 || { echo "未找到 pm2"; exit 1; }
command -v polycli >/dev/null 2>&1 || { echo "未找到 polycli"; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "未找到 awk"; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "未找到 envsubst"; exit 1; }

# 1. 部署 cdk 链、提取合约地址、设置 nginx
# L2_CHAIN_ID=20001 L1_CHAIN_ID=3151908 L1_RPC_URL=https://eth.yidaiyilu0.site/rpc L1_PREALLOCATED_MNEMONIC="praise library enforce wagon picnic kiss estate duck nephew strong seat autumn" 
# 创建助记词
L1_PREALLOCATED_MNEMONIC=$(cast wallet new-mnemonic --json | jq -r '.mnemonic')
export L1_PREALLOCATED_MNEMONIC
ZK_CLAIM_SERVICE_PRIVATE_KEY="0x$(openssl rand -hex 32)"
export ZK_CLAIM_SERVICE_PRIVATE_KEY
L2_PRIVATE_KEY="0x$(openssl rand -hex 32)"
export L2_PRIVATE_KEY
L2_ADDRESS=$(cast wallet address --private-key "$L2_PRIVATE_KEY")
echo "生成了："
echo "L1_PREALLOCATED_MNEMONIC: $L1_PREALLOCATED_MNEMONIC"
echo "ZK_CLAIM_SERVICE_PRIVATE_KEY: $ZK_CLAIM_SERVICE_PRIVATE_KEY"
echo "L2_PRIVATE_KEY: $L2_PRIVATE_KEY"
echo "L2_ADDRESS: $L2_ADDRESS"
echo "L2_ADDRESS 用于给 ZK_CLAIM_SERVICE_PRIVATE_KEY 部署 counter 合约 和 ydyl-gen-accounts 服务创建账户"

# 1. 从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY
echo "🔹 STEP1: 从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY"
CDK_FUND_VAULT_ADDRESS=$(cast wallet address --mnemonic "$L1_PREALLOCATED_MNEMONIC")
ZK_CLAIM_SERVICE_ADDRESS=$(cast wallet address --private-key "$ZK_CLAIM_SERVICE_PRIVATE_KEY")
L1_REGISTER_BRIDGE_ADDRESS=$(cast wallet address --private-key "$L1_REGISTER_BRIDGE_PRIVATE_KEY")

if [ "${DRYRUN:-}" = "true" ]; then
  echo "🔹 DRYRUN 模式: 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
else
  echo "🔹 实际转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY"
  cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 100ether "$CDK_FUND_VAULT_ADDRESS" --rpc-timeout 60
  cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 100ether "$ZK_CLAIM_SERVICE_ADDRESS" --rpc-timeout 60
  cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 10ether "$L1_REGISTER_BRIDGE_ADDRESS" --rpc-timeout 60
fi

# 2. 部署 kurtosis cdk
echo "🔹 STEP2: 部署 kurtosis cdk"
cd "$DIR"/cdk-work && "$DIR"/cdk-work/scripts/deploy.sh "$ENCLAVE_NAME"
L2_RPC_URL=http://127.0.0.1/l2rpc
# L2_VAULT_PRIVATE_KEY=$(cast wallet private-key --mnemonic "$L1_PREALLOCATED_MNEMONIC" --mnemonic-index 5)

DEPLOY_RESULT_FILE="$DIR/cdk-work/output/deploy-result-$NETWORK.json"
L2_VAULT_PRIVATE_KEY=$(jq -r '.zkevm_l2_admin_private_key' "$DEPLOY_RESULT_FILE")

# 3. 给 L2_PRIVATE_KEY 和 ZK_CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH
echo "🔹 STEP3: 给 L2_PRIVATE_KEY 和 ZK_CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH"
if [ "${DRYRUN:-}" = "true" ]; then
  echo "🔹 DRYRUN 模式: 转账 L2 ETH 给 L2_PRIVATE_KEY 和 ZK_CLAIM_SERVICE_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
else
  echo "🔹 实际转账 L2 ETH 给 L2_PRIVATE_KEY 和 ZK_CLAIM_SERVICE_PRIVATE_KEY"
  cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_VAULT_PRIVATE_KEY" --value 100ether "$L2_ADDRESS" --rpc-timeout 60
  cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_VAULT_PRIVATE_KEY" --value 100ether "$ZK_CLAIM_SERVICE_ADDRESS" --rpc-timeout 60
fi

# 4. 为 zk-claim-service 生成.env文件
echo "🔹 STEP4: 为 zk-claim-service 生成 .env 和 .env.counter-bridge-register 文件"
cd "$DIR"/cdk-work && ./scripts/gen-zk-claim-service-env.sh "$ENCLAVE_NAME"
cp "$DIR"/cdk-work/output/zk-claim-service.env "$DIR"/zk-claim-service/.env
cp "$DIR"/cdk-work/output/counter-bridge-register.env "$DIR"/zk-claim-service/.env.counter-bridge-register

# 5. 部署 counter 合约并注册 bridge 到 L1 中继合约
echo "🔹 STEP5: 部署 counter 合约并注册 bridge 到 L1 中继合约"
cd "$DIR"/zk-claim-service 
yarn
npx hardhat compile
COUNTER_BRIDGE_REGISTER_RESULT_FILE="$DIR"/output/counter-bridge-register-result-$NETWORK.json
node ./scripts/i_deployCounterAndRegisterBridge.js --out "$COUNTER_BRIDGE_REGISTER_RESULT_FILE"

# 6. 启动 zk-claim-service 服务
echo "🔹 STEP6: 启动 zk-claim-service 服务"
cd "$DIR"/zk-claim-service && yarn && yarn run start

# 7. 运行 ydyl-gen-accounts 脚本生成账户
echo "🔹 STEP7: 运行 ydyl-gen-accounts 脚本生成账户"
cd "$DIR"/ydyl-gen-accounts

echo "🔹 STEP7.1: 创建 .env 文件"
cat > .env <<EOF
PRIVATE_KEY=$L2_PRIVATE_KEY
RPC=$L2_RPC_URL
EOF

echo "🔹 STEP7.2: 安装依赖并运行脚本"
npm i
npm run build
npm run start -- --fundAmount 5

# 8. 收集元数据、保存到文件，供外部查询
echo "🔹 STEP8: 收集元数据、保存到文件，供外部查询"
COUNTER_CONTRACT=$(jq -r '.counter' "$COUNTER_BRIDGE_REGISTER_RESULT_FILE")
METADATA_FILE=$DIR/output/$ENCLAVE_NAME-meta.json
export L2_VAULT_PRIVATE_KEY, COUNTER_CONTRACT
jq -n 'env | {L1_VAULT_PRIVATE_KEY, L2_VAULT_PRIVATE_KEY, L1_PREALLOCATED_MNEMONIC, ZK_CLAIM_SERVICE_PRIVATE_KEY, L2_PRIVATE_KEY, L1_CHAIN_ID, L2_CHAIN_ID, L1_RPC_URL, COUNTER_CONTRACT}' > "$METADATA_FILE"
echo "文件已保存到 $METADATA_FILE"

echo "🔹 所有步骤完成"