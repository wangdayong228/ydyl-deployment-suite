#!/bin/bash
set -Eueo pipefail

########################################
# 使用说明（简要）
# 1. 必须传入（用户提供）的环境变量：
#    - L1_CHAIN_ID: L1 链 chain id（用于部署/元数据记录/区分网络）
#    - L2_CHAIN_ID: L2 链 chain id（用于部署/元数据记录/区分网络）
#    - L1_RPC_URL: 连接 L1 的 RPC 地址（用于 L1 转账、以及 jsonrpc-proxy 上游）
#    - L1_VAULT_PRIVATE_KEY: L1 主资金账户私钥（用于给部署相关账户转 L1 ETH）
#    - L1_BRIDGE_HUB_CONTRACT: L1 bridgeHub/中继合约地址（注册 bridge 时使用）
#    - L1_REGISTER_BRIDGE_PRIVATE_KEY: 在 L1 上注册 bridge 的私钥（调用 bridgeHub.addBridgeService）
#    - ENABLE_GEN_ACC: 是否执行 step9 生成账户（必须显式传 true/false）
#
# 2. 可选传入（可覆盖默认）的环境变量：
#    - ENCLAVE_NAME: kurtosis enclave 名（默认 cdk-gen）
#    - L2_TYPE: L2 类型编号（默认 0=zk；会传递给注册脚本）
#    - L2_RPC_URL: L2 RPC（默认 http://127.0.0.1/l2rpc；由 kurtosis 暴露到本机）
#    - YDYL_SCRIPTS_LIB_DIR: 脚本库路径（默认 $DIR/ydyl-scripts-lib）
#    - DRYRUN: true 时只打印不转账/不执行链上操作（由 step 函数读取）
#    - DEPLOY_RESULT_FILE: 部署产物路径（默认 $DIR/cdk-work/output/deploy-result-$NETWORK.json）
#    - L2_VAULT_PRIVATE_KEY: L2 faucet/admin 私钥（默认从 DEPLOY_RESULT_FILE 解析）
#
# 3. 自动生成/推导（无需手动提供，除非想固定值复用）的变量：
#    - KURTOSIS_L1_PREALLOCATED_MNEMONIC: step1 自动生成（kurtosis 预分配账户助记词）
#    - KURTOSIS_L1_FUND_VAULT_ADDRESS: 由助记词推导（用于 step2 接收 L1 资金）
#    - CLAIM_SERVICE_PRIVATE_KEY: step1 自动生成（claim-service EOA）
#    - L2_PRIVATE_KEY: step1 自动生成（用途：L2 部署 Counter、ydyl-gen-accounts 付款/部署账户）
#    - L2_ADDRESS: 由 L2_PRIVATE_KEY 推导（用于 step5 接收 L2 充值）
#    - L1_RPC_URL_PROXY: step3 启动 jsonrpc-proxy 后生成（用于 kurtosis deploy）
#    - 其他产物：L2_VAULT_PRIVATE_KEY、METADATA_FILE、COUNTER_BRIDGE_REGISTER_RESULT_FILE 等在运行过程中生成/写入
# 4. 步骤控制：
#    - 默认：从上次完成步骤的下一步开始执行（读取 output/cdk_pipe.state）
#    - 指定起始步骤：
#        START_STEP=3 ./cdk_pipe.sh
#      或：
#        ./cdk_pipe.sh 3
#    - 彻底重来（包括环境变量与状态）：
#        rm output/cdk_pipe.state && ./cdk_pipe.sh
# 5. 状态与环境变量持久化：
#    - 关键变量会写入 output/cdk_pipe.state
#    - 脚本启动时自动 source 该文件，实现从中间步骤续跑
########################################

# 该文件为本机环境注入（不同机器路径/是否存在不一致），ShellCheck 无法在静态分析时跟随
# shellcheck disable=SC1091
source "$HOME/.ydyl-env"

init_paths() {
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  STATE_FILE="$DIR/output/cdk_pipe.state"
  mkdir -p "$DIR"/output
}

load_libs() {
  # 引入通用流水线工具函数（已迁移到 ydyl-scripts-lib）
  YDYL_SCRIPTS_LIB_DIR="${YDYL_SCRIPTS_LIB_DIR:-$DIR/ydyl-scripts-lib}"
  if [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/utils.sh" ]] || [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_utils.sh" ]]; then
    echo "错误: 未找到 ydyl-scripts-lib（utils.sh/pipeline_utils.sh）"
    echo "请设置 YDYL_SCRIPTS_LIB_DIR 指向脚本库目录，例如: export YDYL_SCRIPTS_LIB_DIR=\"$DIR/ydyl-scripts-lib\""
    exit 1
  fi
  # shellcheck source=./ydyl-scripts-lib/utils.sh
  source "$YDYL_SCRIPTS_LIB_DIR/utils.sh"
  # shellcheck source=./ydyl-scripts-lib/pipeline_utils.sh
  source "$YDYL_SCRIPTS_LIB_DIR/pipeline_utils.sh"
}

init_network_vars() {
  ENCLAVE_NAME="${ENCLAVE_NAME:-cdk-gen}"
  NETWORK="${NETWORK:-${ENCLAVE_NAME#cdk-}}" # 移除 "cdk-" 前缀
  # shellcheck disable=SC2034  # 该变量会被 pipeline_steps_lib.sh 的 step3_start_jsonrpc_proxy 读取
  L2_RPC_URL="http://127.0.0.1/l2rpc"

  L2_TYPE="${L2_TYPE:-0}"
  export L2_TYPE
}

generate_cdk_fund_vault_address() {
  # step2_fund_l1_accounts 要求 KURTOSIS_L1_FUND_VAULT_ADDRESS 必须已存在
  if [[ -z "${KURTOSIS_L1_FUND_VAULT_ADDRESS:-}" ]]; then
    KURTOSIS_L1_FUND_VAULT_ADDRESS=$(cast wallet address --mnemonic "$KURTOSIS_L1_PREALLOCATED_MNEMONIC")
    export KURTOSIS_L1_FUND_VAULT_ADDRESS
  fi
}

########################################
# STEP3: 启动 jsonrpc-proxy（L1/L2 RPC 代理） - CDK 专属
########################################
step3_start_jsonrpc_proxy() {
  cd "$DIR"/jsonrpc-proxy || return 1
  # shellcheck disable=SC2153 # 相关变量由调用方负责初始化与校验
  cat >.env_cdk <<EOF
CORRECT_BLOCK_HASH=false
LOOP_CORRECT_BLOCK_HASH=false
PORT=3030
JSONRPC_URL=$L1_RPC_URL
L2_RPC_URL=$L2_RPC_URL
EOF
  npm i
  npm run start:cdk
  L1_RPC_URL_PROXY=http://$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'):3030
  export L1_RPC_URL_PROXY
}

########################################
# STEP4: 部署 kurtosis cdk - CDK 专属
########################################
step4_deploy_kurtosis_cdk() {
  : "${L1_RPC_URL_PROXY:?L1_RPC_URL_PROXY 未设置，请先运行 STEP3 启动 jsonrpc-proxy}"
  # 只对 deploy.sh 这一条命令临时注入 L1_RPC_URL，不污染当前 shell 的 L1_RPC_URL
  pushd "$DIR/cdk-work" >/dev/null
  YDYL_NO_TRAP=1 L1_RPC_URL="$L1_RPC_URL_PROXY" "$DIR"/cdk-work/scripts/deploy.sh "$ENCLAVE_NAME"
  popd >/dev/null

  if [[ -z "${DEPLOY_RESULT_FILE:-}" ]]; then
    DEPLOY_RESULT_FILE="$DIR/cdk-work/output/deploy-result-$NETWORK.json"
  fi

  if [[ -z "${L2_VAULT_PRIVATE_KEY:-}" ]]; then
    L2_VAULT_PRIVATE_KEY=$(jq -r '.zkevm_l2_admin_private_key' "$DEPLOY_RESULT_FILE")
    export L2_VAULT_PRIVATE_KEY
  fi
}

########################################
# STEP6: 为 zk-claim-service 生成 .env - CDK 专属
########################################
step6_gen_zk_claim_env() {
  cd "$DIR"/cdk-work && ./scripts/gen-zk-claim-service-env.sh "$ENCLAVE_NAME"
  cp "$DIR"/cdk-work/output/zk-claim-service.env "$DIR"/zk-claim-service/.env
  cp "$DIR"/cdk-work/output/counter-bridge-register.env "$DIR"/zk-claim-service/.env.counter-bridge-register
}

########################################
# STEP8: 启动 zk-claim-service 服务 - CDK 专属
########################################
step8_start_zk_claim_service() {
  cd "$DIR"/zk-claim-service && yarn && yarn run start
}

record_input_vars() {
  # 记录本次执行时用户传入的关键环境变量（用于与历史状态对比）
  # 这些 INPUT_* 变量会在 pipeline_utils.sh 的 check_input_env_consistency 中通过间接变量引用读取，
  # ShellCheck 无法静态推导其用途，属于有意保留
  # shellcheck disable=SC2034
  INPUT_L1_CHAIN_ID="${L1_CHAIN_ID-}"
  # shellcheck disable=SC2034
  INPUT_L2_CHAIN_ID="${L2_CHAIN_ID-}"
  # shellcheck disable=SC2034
  INPUT_L1_RPC_URL="${L1_RPC_URL-}"
  # shellcheck disable=SC2034
  INPUT_L1_VAULT_PRIVATE_KEY="${L1_VAULT_PRIVATE_KEY-}"
  # shellcheck disable=SC2034
  INPUT_L1_BRIDGE_HUB_CONTRACT="${L1_BRIDGE_HUB_CONTRACT-}"
  # shellcheck disable=SC2034
  INPUT_L1_REGISTER_BRIDGE_PRIVATE_KEY="${L1_REGISTER_BRIDGE_PRIVATE_KEY-}"
}

load_state_and_check_tools() {
  pipeline_load_state
  require_commands cast jq pm2 polycli awk envsubst ip npm yarn
}

init_persist_vars() {
  # 需要持久化的环境变量白名单（每行一个，便于维护）
  # shellcheck disable=SC2034  # 该变量会被 pipeline_utils.sh 的 save_state 间接读取
  PERSIST_VARS=(
    # 外部输入
    L1_CHAIN_ID
    L2_CHAIN_ID
    L1_RPC_URL
    L1_VAULT_PRIVATE_KEY
    L1_BRIDGE_HUB_CONTRACT
    L1_REGISTER_BRIDGE_PRIVATE_KEY

    # 运行过程中生成/推导的变量
    ENCLAVE_NAME
    NETWORK
    KURTOSIS_L1_PREALLOCATED_MNEMONIC
    CLAIM_SERVICE_PRIVATE_KEY
    # L2_PRIVATE_KEY 用途：
    # - L2 上部署 Counter 合约（bridge 注册流程依赖）
    # - ydyl-gen-accounts 的付款/部署账户（写入 ydyl-gen-accounts/.env 的 PRIVATE_KEY）
    L2_PRIVATE_KEY
    L2_ADDRESS
    KURTOSIS_L1_FUND_VAULT_ADDRESS
    CLAIM_SERVICE_ADDRESS
    L1_REGISTER_BRIDGE_ADDRESS
    L2_RPC_URL
    L2_VAULT_PRIVATE_KEY
    COUNTER_BRIDGE_REGISTER_RESULT_FILE
    DEPLOY_RESULT_FILE
    METADATA_FILE
    L2_COUNTER_CONTRACT
    CLAIM_SERVICE_PRIVATE_KEY

    # 流水线状态：running/success/failed
    PIPELINE_STATUS
  )
}

check_env_compat() {
  if [[ -f "$STATE_FILE" ]]; then
    check_input_env_consistency L1_CHAIN_ID
    check_input_env_consistency L2_CHAIN_ID
    check_input_env_consistency L1_RPC_URL
    check_input_env_consistency L1_VAULT_PRIVATE_KEY
    check_input_env_consistency L1_BRIDGE_HUB_CONTRACT
    check_input_env_consistency L1_REGISTER_BRIDGE_PRIVATE_KEY
  fi
}

require_inputs() {
  if [[ -z "${L2_CHAIN_ID:-}" ]] || [[ -z "${L1_CHAIN_ID:-}" ]] || [[ -z "${L1_RPC_URL:-}" ]] || [[ -z "${L1_VAULT_PRIVATE_KEY:-}" ]] || [[ -z "${L1_BRIDGE_HUB_CONTRACT:-}" ]] || [[ -z "${L1_REGISTER_BRIDGE_PRIVATE_KEY:-}" ]] || [[ -z "${ENABLE_GEN_ACC:-}" ]]; then
    echo "错误: 缺少必须的环境变量，请设置：L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY,L1_BRIDGE_HUB_CONTRACT,L1_REGISTER_BRIDGE_PRIVATE_KEY"
    echo "变量说明:"
    echo "  L2_CHAIN_ID: L2 链的 chain id"
    echo "  L1_CHAIN_ID: L1 链的 chain id"
    echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
    echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户，用于给 KURTOSIS_L1_PREALLOCATED_MNEMONIC 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L1 ETH"
    echo "  L1_BRIDGE_HUB_CONTRACT: L1 中继合约地址"
    echo "  L1_REGISTER_BRIDGE_PRIVATE_KEY: L1 注册 bridge 的私钥"
    echo "  ENABLE_GEN_ACC: 是否启用生成账户进程"
    exit 1
  fi
}

parse_start_step_and_export_restored() {
  pipeline_parse_start_step "$@"
  # 把从 state 文件里恢复出来的关键变量导出到环境
  if [[ -n "${KURTOSIS_L1_PREALLOCATED_MNEMONIC:-}" ]]; then export KURTOSIS_L1_PREALLOCATED_MNEMONIC; fi
  if [[ -n "${CLAIM_SERVICE_PRIVATE_KEY:-}" ]]; then export CLAIM_SERVICE_PRIVATE_KEY; fi
  # L2_PRIVATE_KEY 用途见上方 PERSIST_VARS 注释（部署 Counter、gen-accounts 付款/部署账户）
  if [[ -n "${L2_PRIVATE_KEY:-}" ]]; then export L2_PRIVATE_KEY; fi
  if [[ -n "${L2_ADDRESS:-}" ]]; then export L2_ADDRESS; fi
  if [[ -n "${L2_TYPE:-}" ]]; then export L2_TYPE; fi
}

load_steps() {
  if [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh" ]]; then
    echo "错误: 未找到 ydyl-scripts-lib/pipeline_steps_lib.sh"
    exit 1
  fi
  # Steps: 从 steps lib 引入（仅定义函数，不在顶层执行）
  # shellcheck source=./ydyl-scripts-lib/pipeline_steps_lib.sh
  source "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh"
}

run_all_steps() {
  run_step 1 "初始化身份和密钥" step1_init_identities
  generate_cdk_fund_vault_address
  run_step 2 "从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH" step2_fund_l1_accounts
  run_step 3 "启动 jsonrpc-proxy（L1/L2 RPC 代理）" step3_start_jsonrpc_proxy
  run_step 4 "部署 kurtosis cdk" step4_deploy_kurtosis_cdk
  run_step 5 "给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH" step5_fund_l2_accounts
  run_step 6 "为 zk-claim-service 生成 .env 和 .env.counter-bridge-register 文件" step6_gen_zk_claim_env
  run_step 7 "部署 counter 合约并注册 bridge 到 L1 中继合约" step7_deploy_counter_and_register_bridge
  run_step 8 "启动 zk-claim-service 服务" step8_start_zk_claim_service
  run_step 9 "运行 ydyl-gen-accounts 脚本生成账户" step9_gen_accounts
  run_step 10 "收集元数据、保存到文件，供外部查询" step10_collect_metadata
  run_step 11 "启动 ydyl-console-service 服务" step11_start_ydyl_console_service
  run_step 12 "检查 PM2 进程是否有失败" step12_check_pm2_unerror

  # shellcheck disable=SC2034  # 该变量通过 PERSIST_VARS 间接写入 state 文件
  PIPELINE_STATUS="success"
  # 全部完成时仅更新状态，不改变已完成步骤号
  save_state "${LAST_DONE_STEP:-0}"
  echo "🔹 所有步骤完成"
}

main() {
  init_paths
  load_libs
  ydyl_enable_traps
  init_network_vars
  record_input_vars
  load_state_and_check_tools
  init_persist_vars
  check_env_compat
  require_inputs
  parse_start_step_and_export_restored "$@"
  load_steps
  run_all_steps
}

main "$@"
