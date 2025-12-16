#!/bin/bash
set -xEueo pipefail
trap 'echo "🔴 cdk_pipe.sh 执行失败: 行 $LINENO, 错误信息: $BASH_COMMAND"; exit 1' ERR

########################################
# 使用说明（简要）
# 1. 必填环境变量：
#    - L1_CHAIN_ID, L2_CHAIN_ID, L1_RPC_URL, L1_VAULT_PRIVATE_KEY
#    - L1_BRIDGE_RELAY_CONTRACT, L1_REGISTER_BRIDGE_PRIVATE_KEY
# 2. 步骤控制：
#    - 默认：从上次完成步骤的下一步开始执行（读取 output/cdk_pipe.state）
#    - 指定起始步骤：
#        START_STEP=3 ./cdk_pipe.sh
#      或：
#        ./cdk_pipe.sh 3
#    - 彻底重来（包括环境变量与状态）：
#        rm output/cdk_pipe.state && ./cdk_pipe.sh
# 3. 状态与环境变量持久化：
#    - 关键变量会写入 output/cdk_pipe.state
#    - 脚本启动时自动 source 该文件，实现从中间步骤续跑
########################################

export L2_TYPE=0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$DIR/output/cdk_pipe.state"
mkdir -p "$DIR"/output

# 引入通用流水线工具函数
. "$DIR/pipeline_lib.sh"

ENCLAVE_NAME="${ENCLAVE_NAME:-cdk-gen}"
NETWORK="${NETWORK:-${ENCLAVE_NAME#cdk-}}" # 移除 "cdk-" 前缀
NETWORK=${NETWORK//-/_}                    # 将 "-" 替换为 "_"

# 记录本次执行时用户传入的关键环境变量（用于与历史状态对比）
ORIG_L1_CHAIN_ID="${L1_CHAIN_ID-}"
ORIG_L2_CHAIN_ID="${L2_CHAIN_ID-}"
ORIG_L1_RPC_URL="${L1_RPC_URL-}"
ORIG_L1_VAULT_PRIVATE_KEY="${L1_VAULT_PRIVATE_KEY-}"
ORIG_L1_BRIDGE_RELAY_CONTRACT="${L1_BRIDGE_RELAY_CONTRACT-}"
ORIG_L1_REGISTER_BRIDGE_PRIVATE_KEY="${L1_REGISTER_BRIDGE_PRIVATE_KEY-}"

# 加载上次执行状态
pipeline_load_state

# 查看命令相关工具是否都存在
command -v cast >/dev/null 2>&1 || { echo "未找到 cast"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "未找到 jq"; exit 1; }
command -v pm2 >/dev/null 2>&1 || { echo "未找到 pm2"; exit 1; }
command -v polycli >/dev/null 2>&1 || { echo "未找到 polycli"; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "未找到 awk"; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "未找到 envsubst"; exit 1; }

# 需要持久化的环境变量白名单（每行一个，便于维护）
PERSIST_VARS=(
  # 外部输入
  L1_CHAIN_ID
  L2_CHAIN_ID
  L1_RPC_URL
  L1_VAULT_PRIVATE_KEY
  L1_BRIDGE_RELAY_CONTRACT
  L1_REGISTER_BRIDGE_PRIVATE_KEY

  # 运行过程中生成/推导的变量
  ENCLAVE_NAME
  NETWORK
  KURTOSIS_L1_PREALLOCATED_MNEMONIC
  CLAIM_SERVICE_PRIVATE_KEY
  L2_PRIVATE_KEY
  L2_ADDRESS
  CDK_FUND_VAULT_ADDRESS
  CLAIM_SERVICE_ADDRESS
  L1_REGISTER_BRIDGE_ADDRESS
  L2_RPC_URL
  L2_VAULT_PRIVATE_KEY
  COUNTER_BRIDGE_REGISTER_RESULT_FILE
  DEPLOY_RESULT_FILE
  METADATA_FILE
  L2_COUNTER_CONTRACT
  CLAIM_SERVICE_PRIVATE_KEY
)

if [ -f "$STATE_FILE" ]; then
  check_input_env_compat L1_CHAIN_ID
  check_input_env_compat L2_CHAIN_ID
  check_input_env_compat L1_RPC_URL
  check_input_env_compat L1_VAULT_PRIVATE_KEY
  check_input_env_compat L1_BRIDGE_RELAY_CONTRACT
  check_input_env_compat L1_REGISTER_BRIDGE_PRIVATE_KEY
fi

# 必须有环境变量 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY
if [ -z "${L2_CHAIN_ID:-}" ] || [ -z "${L1_CHAIN_ID:-}" ] || [ -z "${L1_RPC_URL:-}" ] || [ -z "${L1_VAULT_PRIVATE_KEY:-}" ] || [ -z "${L1_BRIDGE_RELAY_CONTRACT:-}" ] || [ -z "${L1_REGISTER_BRIDGE_PRIVATE_KEY:-}" ]; then
  echo "错误: 请设置 L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY,L1_BRIDGE_RELAY_CONTRACT,L1_REGISTER_BRIDGE_PRIVATE_KEY 环境变量"
  echo "变量说明:"
  echo "  L2_CHAIN_ID: L2 链的 chain id"
  echo "  L1_CHAIN_ID: L1 链的 chain id"
  echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
  echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户，用于给 KURTOSIS_L1_PREALLOCATED_MNEMONIC 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L1 ETH"
  echo "  L1_BRIDGE_RELAY_CONTRACT: L1 中继合约地址"
  echo "  L1_REGISTER_BRIDGE_PRIVATE_KEY: L1 注册 bridge 的私钥"
  exit 1
fi

# 解析 START_STEP 并输出当前状态
pipeline_parse_start_step "$@"

########################################
# STEP1: 生成助记词和关键私钥（只在缺失时生成）
########################################
step1_init_identities() {
  if [ -z "${KURTOSIS_L1_PREALLOCATED_MNEMONIC:-}" ]; then
    KURTOSIS_L1_PREALLOCATED_MNEMONIC=$(cast wallet new-mnemonic --json | jq -r '.mnemonic')
  fi
  export KURTOSIS_L1_PREALLOCATED_MNEMONIC

  if [ -z "${CLAIM_SERVICE_PRIVATE_KEY:-}" ]; then
    CLAIM_SERVICE_PRIVATE_KEY="0x$(openssl rand -hex 32)"
  fi
  export CLAIM_SERVICE_PRIVATE_KEY

  if [ -z "${L2_PRIVATE_KEY:-}" ]; then
    L2_PRIVATE_KEY="0x$(openssl rand -hex 32)"
  fi
  export L2_PRIVATE_KEY

  if [ -z "${L2_ADDRESS:-}" ]; then
    L2_ADDRESS=$(cast wallet address --private-key "$L2_PRIVATE_KEY")
  fi
  export L2_ADDRESS

  echo "生成/加载身份："
  echo "KURTOSIS_L1_PREALLOCATED_MNEMONIC: $KURTOSIS_L1_PREALLOCATED_MNEMONIC"
  echo "CLAIM_SERVICE_PRIVATE_KEY: $CLAIM_SERVICE_PRIVATE_KEY"
  echo "L2_PRIVATE_KEY: $L2_PRIVATE_KEY"
  echo "L2_ADDRESS: $L2_ADDRESS"
  echo "L2_ADDRESS 用于给 CLAIM_SERVICE_PRIVATE_KEY 部署 counter 合约 和 ydyl-gen-accounts 服务创建账户"
}

########################################
# STEP2: 从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH
########################################
step2_fund_l1_accounts() {
  if [ -z "${CDK_FUND_VAULT_ADDRESS:-}" ]; then
    CDK_FUND_VAULT_ADDRESS=$(cast wallet address --mnemonic "$KURTOSIS_L1_PREALLOCATED_MNEMONIC")
  fi
  if [ -z "${CLAIM_SERVICE_ADDRESS:-}" ]; then
    CLAIM_SERVICE_ADDRESS=$(cast wallet address --private-key "$CLAIM_SERVICE_PRIVATE_KEY")
  fi
  if [ -z "${L1_REGISTER_BRIDGE_ADDRESS:-}" ]; then
    L1_REGISTER_BRIDGE_ADDRESS=$(cast wallet address --private-key "$L1_REGISTER_BRIDGE_PRIVATE_KEY")
  fi

  if [ "${DRYRUN:-}" = "true" ]; then
    echo "🔹 DRYRUN 模式: 转账 L1 ETH 给 KURTOSIS_L1_PREALLOCATED_MNEMONIC 和 CLAIM_SERVICE_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
  else
    echo "🔹 实际转账 L1 ETH 给 KURTOSIS_L1_PREALLOCATED_MNEMONIC 和 CLAIM_SERVICE_PRIVATE_KEY"
    cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 100ether "$CDK_FUND_VAULT_ADDRESS" --rpc-timeout 60
    cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 100ether "$CLAIM_SERVICE_ADDRESS" --rpc-timeout 60
    cast send --legacy --rpc-url "$L1_RPC_URL" --private-key "$L1_VAULT_PRIVATE_KEY" --value 10ether "$L1_REGISTER_BRIDGE_ADDRESS" --rpc-timeout 60
  fi
}

########################################
# STEP3: 部署 kurtosis cdk
########################################
step3_deploy_kurtosis_cdk() {
  cd "$DIR"/cdk-work && "$DIR"/cdk-work/scripts/deploy.sh "$ENCLAVE_NAME"

  if [ -z "${L2_RPC_URL:-}" ]; then
    L2_RPC_URL=http://127.0.0.1/l2rpc
  fi

  if [ -z "${DEPLOY_RESULT_FILE:-}" ]; then
    DEPLOY_RESULT_FILE="$DIR/cdk-work/output/deploy-result-$NETWORK.json"
  fi

  if [ -z "${L2_VAULT_PRIVATE_KEY:-}" ]; then
    L2_VAULT_PRIVATE_KEY=$(jq -r '.zkevm_l2_admin_private_key' "$DEPLOY_RESULT_FILE")
  fi
}

########################################
# STEP4: 给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH
########################################
step4_fund_l2_accounts() {
  if [ "${DRYRUN:-}" = "true" ]; then
    echo "🔹 DRYRUN 模式: 转账 L2 ETH 给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY (DRYRUN 模式下不执行实际转账)"
  else
    echo "🔹 实际转账 L2 ETH 给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY"
    cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_VAULT_PRIVATE_KEY" --value 100ether "$L2_ADDRESS" --rpc-timeout 60
    cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$L2_VAULT_PRIVATE_KEY" --value 100ether "$CLAIM_SERVICE_ADDRESS" --rpc-timeout 60
  fi
}

########################################
# STEP5: 为 zk-claim-service 生成 .env
########################################
step5_gen_zk_claim_env() {
  cd "$DIR"/cdk-work && ./scripts/gen-zk-claim-service-env.sh "$ENCLAVE_NAME"
  cp "$DIR"/cdk-work/output/zk-claim-service.env "$DIR"/zk-claim-service/.env
  cp "$DIR"/cdk-work/output/counter-bridge-register.env "$DIR"/zk-claim-service/.env.counter-bridge-register
}

########################################
# STEP6: 部署 counter 合约并注册 bridge
########################################
step6_deploy_counter_and_register_bridge() {
  cd "$DIR"/zk-claim-service
  yarn
  npx hardhat compile

  if [ -z "${COUNTER_BRIDGE_REGISTER_RESULT_FILE:-}" ]; then
    COUNTER_BRIDGE_REGISTER_RESULT_FILE="$DIR"/output/counter-bridge-register-result-"$NETWORK".json
  fi

  node ./scripts/i_deployCounterAndRegisterBridge.js --out "$COUNTER_BRIDGE_REGISTER_RESULT_FILE"
}

########################################
# STEP7: 启动 zk-claim-service 服务
########################################
step7_start_zk_claim_service() {
  cd "$DIR"/zk-claim-service && yarn && yarn run start
}

########################################
# STEP8: 运行 ydyl-gen-accounts 生成账户
########################################
step8_gen_accounts() {
  cd "$DIR"/ydyl-gen-accounts
  echo "🔹 STEP7.1: 清理旧文件"
  npm i
  npm run clean

  echo "🔹 STEP7.1: 创建 .env 文件"
  cat >.env <<EOF
PRIVATE_KEY=$L2_PRIVATE_KEY
RPC=$L2_RPC_URL
EOF

  echo "🔹 STEP7.2: 启动生成账户服务"
  npm run build
  npm run start -- --fundAmount 5
}

########################################
# STEP9: 收集元数据并保存
########################################
step9_collect_metadata() {
  if [ -z "${COUNTER_BRIDGE_REGISTER_RESULT_FILE:-}" ]; then
    COUNTER_BRIDGE_REGISTER_RESULT_FILE="$DIR"/output/counter-bridge-register-result-"$NETWORK".json
  fi

  L2_COUNTER_CONTRACT=$(jq -r '.counter' "$COUNTER_BRIDGE_REGISTER_RESULT_FILE")

  METADATA_FILE=$DIR/output/$ENCLAVE_NAME-meta.json
  export L2_RPC_URL L2_VAULT_PRIVATE_KEY L2_COUNTER_CONTRACT
  jq -n 'env | {L1_VAULT_PRIVATE_KEY, L2_RPC_URL, L2_VAULT_PRIVATE_KEY, KURTOSIS_L1_PREALLOCATED_MNEMONIC, CLAIM_SERVICE_PRIVATE_KEY, L2_PRIVATE_KEY, L1_CHAIN_ID, L2_CHAIN_ID, L1_RPC_URL, L2_COUNTER_CONTRACT}' >"$METADATA_FILE"
  echo "文件已保存到 $METADATA_FILE"
}

########################################
# STEP10: 启动 ydyl-console-service 服务
########################################
step10_start_ydyl_console_service() {
  cd "$DIR"/ydyl-console-service
  cp config.sample.yaml config.yaml
  go build .
  pm2 restart ydyl-console-service || pm2 start ./ydyl-console-service --name ydyl-console-service
  echo "ydyl-console-service 服务已启动"
}

# STEP11: 检查 PM2 进程是否有失败
########################################
step11_check_pm2_online() {
  pm2_check_all_online
}

########################################
# 主执行流程
########################################

run_step 1 "初始化身份和密钥" step1_init_identities
run_step 2 "从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH" step2_fund_l1_accounts
run_step 3 "部署 kurtosis cdk" step3_deploy_kurtosis_cdk
run_step 4 "给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH" step4_fund_l2_accounts
run_step 5 "为 zk-claim-service 生成 .env 和 .env.counter-bridge-register 文件" step5_gen_zk_claim_env
run_step 6 "部署 counter 合约并注册 bridge 到 L1 中继合约" step6_deploy_counter_and_register_bridge
run_step 7 "启动 zk-claim-service 服务" step7_start_zk_claim_service
run_step 8 "运行 ydyl-gen-accounts 脚本生成账户" step8_gen_accounts
run_step 9 "收集元数据、保存到文件，供外部查询" step9_collect_metadata
run_step 10 "启动 ydyl-console-service 服务" step10_start_ydyl_console_service
run_step 11 "检查 PM2 进程是否有失败" step11_check_pm2_online

echo "🔹 所有步骤完成"