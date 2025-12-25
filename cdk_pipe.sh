#!/bin/bash
set -Eueo pipefail
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
  if [ ! -f "$YDYL_SCRIPTS_LIB_DIR/utils.sh" ] || [ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_lib.sh" ]; then
    echo "错误: 未找到 ydyl-scripts-lib（utils.sh/pipeline_lib.sh）"
    echo "请设置 YDYL_SCRIPTS_LIB_DIR 指向脚本库目录，例如: export YDYL_SCRIPTS_LIB_DIR=\"$DIR/ydyl-scripts-lib\""
    exit 1
  fi
  # shellcheck source=./ydyl-scripts-lib/utils.sh
  source "$YDYL_SCRIPTS_LIB_DIR/utils.sh"
  # shellcheck source=./ydyl-scripts-lib/pipeline_lib.sh
  source "$YDYL_SCRIPTS_LIB_DIR/pipeline_lib.sh"
}

init_network_vars() {
  ENCLAVE_NAME="${ENCLAVE_NAME:-cdk-gen}"
  NETWORK="${NETWORK:-${ENCLAVE_NAME#cdk-}}" # 移除 "cdk-" 前缀
  NETWORK=${NETWORK//-/_}                    # 将 "-" 替换为 "_"
  # shellcheck disable=SC2034  # 该变量会被 pipeline_steps_lib.sh 的 step3_start_jsonrpc_proxy 读取
  L2_RPC_URL="http://127.0.0.1/l2rpc"
}

record_input_vars() {
  # 记录本次执行时用户传入的关键环境变量（用于与历史状态对比）
  # 这些 INPUT_* 变量会在 pipeline_lib.sh 的 check_input_env_consistency 中通过间接变量引用读取，
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
  INPUT_L1_BRIDGE_RELAY_CONTRACT="${L1_BRIDGE_RELAY_CONTRACT-}"
  # shellcheck disable=SC2034
  INPUT_L1_REGISTER_BRIDGE_PRIVATE_KEY="${L1_REGISTER_BRIDGE_PRIVATE_KEY-}"
}

load_state_and_check_tools() {
  pipeline_load_state
  require_commands cast jq pm2 polycli awk envsubst ip
}

init_persist_vars() {
  # 需要持久化的环境变量白名单（每行一个，便于维护）
  # shellcheck disable=SC2034  # 该变量会被 pipeline_lib.sh 的 save_state 间接读取
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
}

check_env_compat() {
  if [ -f "$STATE_FILE" ]; then
    check_input_env_consistency L1_CHAIN_ID
    check_input_env_consistency L2_CHAIN_ID
    check_input_env_consistency L1_RPC_URL
    check_input_env_consistency L1_VAULT_PRIVATE_KEY
    check_input_env_consistency L1_BRIDGE_RELAY_CONTRACT
    check_input_env_consistency L1_REGISTER_BRIDGE_PRIVATE_KEY
  fi
}

require_inputs() {
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
}

parse_start_step_and_export_restored() {
  pipeline_parse_start_step "$@"
  # 把从 state 文件里恢复出来的关键变量导出到环境
  [ -n "${KURTOSIS_L1_PREALLOCATED_MNEMONIC:-}" ] && export KURTOSIS_L1_PREALLOCATED_MNEMONIC
  [ -n "${CLAIM_SERVICE_PRIVATE_KEY:-}" ] && export CLAIM_SERVICE_PRIVATE_KEY
  [ -n "${L2_PRIVATE_KEY:-}" ] && export L2_PRIVATE_KEY
  [ -n "${L2_ADDRESS:-}" ] && export L2_ADDRESS
  [ -n "${L2_TYPE:-}" ] && export L2_TYPE
}

load_steps() {
  if [ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh" ]; then
    echo "错误: 未找到 ydyl-scripts-lib/pipeline_steps_lib.sh"
    exit 1
  fi
  # Steps: 从 steps lib 引入（仅定义函数，不在顶层执行）
  # shellcheck source=./ydyl-scripts-lib/pipeline_steps_lib.sh
  source "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh"
}

run_all_steps() {
  run_step 1 "初始化身份和密钥" step1_init_identities
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
  run_step 12 "检查 PM2 进程是否有失败" step12_check_pm2_online
  echo "🔹 所有步骤完成"
}

main() {
  init_paths
  load_libs
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
