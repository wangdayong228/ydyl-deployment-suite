#!/bin/bash
set -Eueo pipefail
trap 'echo "命令失败: 行 $LINENO"; exit 1' ERR

# 必须有环境变量 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL
if [ -z "$L2_CHAIN_ID" ] || [ -z "$L1_CHAIN_ID" ] || [ -z "$L1_RPC_URL" ]; then
  echo "错误: 请设置 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL 环境变量"
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# 1. 部署 cdk 链、提取合约地址、设置 nginx
# L2_CHAIN_ID=20001 L1_CHAIN_ID=3151908 L1_RPC_URL=https://eth.yidaiyilu0.site/rpc L1_PREALLOCATED_MNEMONIC="praise library enforce wagon picnic kiss estate duck nephew strong seat autumn" 
# 创建助记词
export L1_PREALLOCATED_MNEMONIC=$(cast wallet new-mnemonic --json | jq -r '.mnemonic')
export ZK_CLAIM_SERVICE_PRIVATE_KEY=$(openssl rand -hex 32)
export GEN_ACCOUNTS_PRIVATE_KEY=$(openssl rand -hex 32)

echo "🔹 STEP1: 部署 kurtosis cdk"
cd $DIR/cdk-work && $DIR/cdk-work/scripts/deploy.sh cdk-gen
# 2. 为 zk-claim-service 生成.env文件
echo "🔹 STEP2: 为 zk-claim-service 生成.env文件"
cd $DIR/cdk-work && ./scripts/gen-zk-claim-service-env.sh $L1_RPC_URL $ZK_CLAIM_SERVICE_PRIVATE_KEY
# 3. 部署 counter 合约并注册 bridge 到 L1 中继合约
echo "🔹 STEP3: 部署 counter 合约并注册 bridge 到 L1 中继合约"
cd $DIR/zk-claim-service && node ./scripts/i_deployCounterAndRegisterBridge.js
# 4. 启动 zk-claim-service 服务
echo "🔹 STEP4: 启动 zk-claim-service 服务"
cp $DIR/cdk-work/output/zk-claim-service-env.env $DIR/zk-claim-service/.env
cd $DIR/zk-claim-service && yarn run start
# 5. 运行 ydyl-gen-accounts 脚本生成账户
echo "🔹 STEP5: 运行 ydyl-gen-accounts 脚本生成账户"
cd $DIR/ydyl-gen-accounts && yarn run start
# 6. 收集元数据、保存到文件，供外部查询
echo "🔹 STEP6: 收集元数据、保存到文件，供外部查询"
jq -n 'env | {L1_PREALLOCATED_MNEMONIC, ZK_CLAIM_SERVICE_PRIVATE_KEY, GEN_ACCOUNTS_PRIVATE_KEY, L1_CHAIN_ID, L2_CHAIN_ID, L1_RPC_URL}' > deploy_meta.json
