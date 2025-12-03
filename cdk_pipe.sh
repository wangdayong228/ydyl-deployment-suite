#!/bin/bash
set -xEueo pipefail
trap 'echo "命令失败: 行 $LINENO"; exit 1' ERR

# 必须有环境变量 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY
if [ -z "$L2_CHAIN_ID" ] || [ -z "$L1_CHAIN_ID" ] || [ -z "$L1_RPC_URL" ] || [ -z "$L1_VAULT_PRIVATE_KEY" ]; then
  echo "错误: 请设置 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY 环境变量"
  echo "变量说明:"
  echo "  L2_CHAIN_ID: L2 链的 chain id"
  echo "  L1_CHAIN_ID: L1 链的 chain id"
  echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
  echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户，用于给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY 转账 L1 ETH"
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCLAVE_NAME="cdk-gen"
mkdir -p $DIR/output

# 查看命令相关工具是否都存在
command -v cast >/dev/null 2>&1 || { echo "未找到 cast"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "未找到 jq"; exit 1; }

# 1. 部署 cdk 链、提取合约地址、设置 nginx
# L2_CHAIN_ID=20001 L1_CHAIN_ID=3151908 L1_RPC_URL=https://eth.yidaiyilu0.site/rpc L1_PREALLOCATED_MNEMONIC="praise library enforce wagon picnic kiss estate duck nephew strong seat autumn" 
# 创建助记词
export L1_PREALLOCATED_MNEMONIC=$(cast wallet new-mnemonic --json | jq -r '.mnemonic')
export ZK_CLAIM_SERVICE_PRIVATE_KEY="0x$(openssl rand -hex 32)"
export GEN_ACCOUNTS_PRIVATE_KEY="0x$(openssl rand -hex 32)"

# 1. 从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY
echo "🔹 STEP1: 从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY"
CDK_FUND_VAULT_ADDRESS=$(cast wallet address --mnemonic "$L1_PREALLOCATED_MNEMONIC")
ZK_CLAIM_SERVICE_ADDRESS=$(cast wallet address --private-key $ZK_CLAIM_SERVICE_PRIVATE_KEY)

if [ $DRYRUN == "true" ]; then
  echo "🔹 DRYRUN 模式: 转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
else
  echo "🔹 实际转账 L1 ETH 给 L1_PREALLOCATED_MNEMONIC 和 ZK_CLAIM_SERVICE_PRIVATE_KEY"
  cast send --legacy --rpc-url $L1_RPC_URL --private-key $L1_VAULT_PRIVATE_KEY --value 100ether $CDK_FUND_VAULT_ADDRESS
  cast send --legacy --rpc-url $L1_RPC_URL --private-key $L1_VAULT_PRIVATE_KEY --value 100ether $ZK_CLAIM_SERVICE_ADDRESS  
fi

# 2. 部署 kurtosis cdk
echo "🔹 STEP2: 部署 kurtosis cdk"
cd $DIR/cdk-work && $DIR/cdk-work/scripts/deploy.sh $ENCLAVE_NAME
L2_RPC_URL=http://127.0.0.1:10001
L2_VAULT_PRIVATE_KEY=$(cast wallet private-key --mnemonic "$L1_PREALLOCATED_MNEMONIC" --mnemonic-index 5)
L2_VAULT_ADDRESS=$(cast wallet address --private-key $L2_VAULT_PRIVATE_KEY)

# 给 GEN_ACCOUNTS_PRIVATE_KEY 转账 L2 ETH
if [ $DRYRUN == "true" ]; then
  echo "🔹 DRYRUN 模式: 转账 L2 ETH 给 GEN_ACCOUNTS_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
else
  echo "🔹 实际转账 L2 ETH 给 GEN_ACCOUNTS_PRIVATE_KEY"
  cast send --legacy --rpc-url $L2_RPC_URL --private-key $GEN_ACCOUNTS_PRIVATE_KEY --value 100ether $L2_VAULT_ADDRESS
fi

# 3. 为 zk-claim-service 生成.env文件
echo "🔹 STEP3: 为 zk-claim-service 生成.env文件"
cd $DIR/cdk-work && ./scripts/gen-zk-claim-service-env.sh $ENCLAVE_NAME

# 4. 部署 counter 合约并注册 bridge 到 L1 中继合约
echo "🔹 STEP4: 部署 counter 合约并注册 bridge 到 L1 中继合约"
cd $DIR/zk-claim-service 
yarn
npx hardhat compile
node ./scripts/i_deployCounterAndRegisterBridge.js

# 5. 启动 zk-claim-service 服务
echo "🔹 STEP5: 启动 zk-claim-service 服务"
cp $DIR/cdk-work/output/zk-claim-service.env $DIR/zk-claim-service/.env
cd $DIR/zk-claim-service && yarn && yarn run start

# 6. 运行 ydyl-gen-accounts 脚本生成账户
echo "🔹 STEP6: 运行 ydyl-gen-accounts 脚本生成账户"
cd $DIR/ydyl-gen-accounts

echo "🔹 STEP6.1: 创建 .env 文件"
cat > .env <<EOF
PRIVATE_KEY=$GEN_ACCOUNTS_PRIVATE_KEY
RPC=$L1_RPC_URL
EOF

echo "🔹 STEP6.2: 安装依赖并运行脚本"
npm i
npm run build
npm run start

# 7. 收集元数据、保存到文件，供外部查询
echo "🔹 STEP7: 收集元数据、保存到文件，供外部查询"
export L2_VAULT_PRIVATE_KEY=$L2_VAULT_PRIVATE_KEY
jq -n 'env | {L1_VAULT_PRIVATE_KEY, L2_VAULT_PRIVATE_KEY, L1_PREALLOCATED_MNEMONIC, ZK_CLAIM_SERVICE_PRIVATE_KEY, GEN_ACCOUNTS_PRIVATE_KEY, L1_CHAIN_ID, L2_CHAIN_ID, L1_RPC_URL}' > $DIR/output/$ENCLAVE_NAME-meta.json
