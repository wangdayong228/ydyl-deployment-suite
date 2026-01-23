#!/bin/bash
set -Eueo pipefail

########################################
# 使用说明（简要）
# 1. 必须传入（用户提供）的环境变量：
#    - L1_CHAIN_ID: L1 链 chain id（用于部署/元数据记录/区分网络）
#    - L2_CHAIN_ID: L2 链 chain id（用于部署/元数据记录/区分网络）
#    - L1_RPC_URL: 连接 L1 的 RPC 地址（用于 L1 转账、以及 jsonrpc-proxy 上游）
#    - L1_VAULT_PRIVATE_KEY:
#        L1 主资金账户私钥（用于给部署相关账户转 L1 ETH）
#    - L1_BRIDGE_HUB_CONTRACT: L1 bridgeHub/中继合约地址（注册 bridge 时使用）
#    - L1_REGISTER_BRIDGE_PRIVATE_KEY: 在 L1 上注册 bridge 的私钥（调用 bridgeHub.addBridgeService）
#
# 2. 可选传入（可覆盖默认）的环境变量：
#    - ENCLAVE_NAME: kurtosis enclave 名（默认 op-gen）
#    - L2_TYPE: L2 类型编号（默认 1=op；会传递给注册脚本）
#    - L2_RPC_URL: L2 RPC（默认 http://127.0.0.1/l2rpc；由 kurtosis 暴露到本机）
#    - YDYL_SCRIPTS_LIB_DIR: 脚本库路径（默认 $DIR/ydyl-scripts-lib）
#    - DRYRUN: true 时只打印不转账/不执行链上操作（由 step 函数读取）
#    - ENABLE_L1_RPC_RROXY: true 时跳过 jsonrpc-proxy，直接用 L1_RPC_URL 作为 L1_RPC_URL_PROXY（变量名历史拼写保留）
#
# 3. 自动生成/推导（无需手动提供，除非想固定值复用）的变量：
#    - KURTOSIS_L1_PREALLOCATED_MNEMONIC: step1/生成函数自动生成（kurtosis 预分配账户助记词）
#    - KURTOSIS_L1_FUND_VAULT_ADDRESS: 由 KURTOSIS_L1_VAULT_PRIVATE_KEY 推导（用于 step2 接收 L1 资金）
#    - CLAIM_SERVICE_PRIVATE_KEY: step1 自动生成（claim-service EOA）
#    - L2_PRIVATE_KEY: step1 自动生成（用途：L2 部署 Counter、ydyl-gen-accounts 付款/部署账户）
#    - L2_ADDRESS: 由 L2_PRIVATE_KEY 推导（用于 step5 接收 L2 充值）
#    - L1_RPC_URL_PROXY: step3 启动 jsonrpc-proxy 后生成（用于 kurtosis deploy）
#    - L2_VAULT_PRIVATE_KEY: step4 从 op deploy 产物 wallets.json 解析（用于 step5 给 L2 账户充值）
# 2. 步骤控制：
#    - 默认：从上次完成步骤的下一步开始执行（读取 output/op_pipe.state）
#    - 指定起始步骤：
#        START_STEP=3 ./op_pipe.sh
#      或：
#        ./op_pipe.sh 3
# 3. 状态与环境变量持久化：
#    - 关键变量会写入 output/op_pipe.state
#    - 脚本启动时自动 source 该文件，实现从中间步骤续跑
########################################

# shellcheck disable=SC1091
source "$HOME/.ydyl-env"

init_paths() {
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    STATE_FILE="$DIR/output/op_pipe.state"
    mkdir -p "$DIR"/output
}

load_libs() {
    YDYL_SCRIPTS_LIB_DIR="${YDYL_SCRIPTS_LIB_DIR:-$DIR/ydyl-scripts-lib}"
    if [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/utils.sh" ]] || [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_utils.sh" ]] || [[ ! -f "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh" ]]; then
        echo "错误: 未找到 ydyl-scripts-lib（utils.sh/pipeline_utils.sh/pipeline_steps_lib.sh）"
        echo "请设置 YDYL_SCRIPTS_LIB_DIR 指向脚本库目录，例如: export YDYL_SCRIPTS_LIB_DIR=\"$DIR/ydyl-scripts-lib\""
        exit 1
    fi
    # shellcheck source=./ydyl-scripts-lib/utils.sh
    source "$YDYL_SCRIPTS_LIB_DIR/utils.sh"
    # shellcheck source=./ydyl-scripts-lib/pipeline_utils.sh
    source "$YDYL_SCRIPTS_LIB_DIR/pipeline_utils.sh"
    # shellcheck source=./ydyl-scripts-lib/pipeline_steps_lib.sh
    source "$YDYL_SCRIPTS_LIB_DIR/pipeline_steps_lib.sh"
}

init_network_vars() {
    ENCLAVE_NAME="${ENCLAVE_NAME:-op-gen}"
    NETWORK="${NETWORK:-${ENCLAVE_NAME#op-}}" # 移除 "op-" 前缀
    # shellcheck disable=SC2034
    L2_RPC_URL="http://127.0.0.1/l2rpc"
    # OP 类型
    L2_TYPE="${L2_TYPE:-1}"
    export L2_TYPE
}

gen_op_enclave_deploy_accounts() {
    # step2_fund_l1_accounts 要求 KURTOSIS_L1_FUND_VAULT_ADDRESS 必须已存在
    # 说明：
    # - KURTOSIS_L1_VAULT_PRIVATE_KEY 用于 kurtosis deploy（与出资账户 L1_VAULT_PRIVATE_KEY 解耦）
    # - 若希望复用固定值，可在运行前手动 export 这些变量；脚本仅在缺失时生成
    if [[ -z "${KURTOSIS_L1_VAULT_PRIVATE_KEY:-}" ]]; then
        KURTOSIS_L1_VAULT_PRIVATE_KEY="0x$(openssl rand -hex 32)"
    fi
    export KURTOSIS_L1_VAULT_PRIVATE_KEY

    if [[ -z "${KURTOSIS_L1_FUND_VAULT_ADDRESS:-}" ]]; then
        KURTOSIS_L1_FUND_VAULT_ADDRESS=$(cast wallet address --private-key "$KURTOSIS_L1_VAULT_PRIVATE_KEY")
    fi
    export KURTOSIS_L1_FUND_VAULT_ADDRESS

    if [[ -z "${KURTOSIS_L1_PREALLOCATED_MNEMONIC:-}" ]]; then
        KURTOSIS_L1_PREALLOCATED_MNEMONIC=$(cast wallet new-mnemonic --json | jq -r '.mnemonic')
    fi
    export KURTOSIS_L1_PREALLOCATED_MNEMONIC
}

record_input_vars() {
    # shellcheck disable=SC2034
    INPUT_L1_CHAIN_ID="${L1_CHAIN_ID-}"
    # shellcheck disable=SC2034
    INPUT_L2_CHAIN_ID="${L2_CHAIN_ID-}"
    # shellcheck disable=SC2034
    INPUT_L1_RPC_URL="${L1_RPC_URL-}"
    # shellcheck disable=SC2034
    INPUT_L1_VAULT_PRIVATE_KEY="${L1_VAULT_PRIVATE_KEY-}"
    # shellcheck disable=SC2034
    INPUT_KURTOSIS_L1_VAULT_PRIVATE_KEY="${KURTOSIS_L1_VAULT_PRIVATE_KEY-}"
    # shellcheck disable=SC2034
    INPUT_KURTOSIS_L1_PREALLOCATED_MNEMONIC="${KURTOSIS_L1_PREALLOCATED_MNEMONIC-}"
    # shellcheck disable=SC2034
    INPUT_KURTOSIS_L1_FUND_VAULT_ADDRESS="${KURTOSIS_L1_FUND_VAULT_ADDRESS-}"
    # shellcheck disable=SC2034
    INPUT_L1_BRIDGE_HUB_CONTRACT="${L1_BRIDGE_HUB_CONTRACT-}"
    # shellcheck disable=SC2034
    INPUT_L1_REGISTER_BRIDGE_PRIVATE_KEY="${L1_REGISTER_BRIDGE_PRIVATE_KEY-}"
}

load_state_and_check_tools() {
    pipeline_load_state
    require_commands cast jq pm2 awk envsubst ip npm yarn node kurtosis openssl
}

init_persist_vars() {
    # shellcheck disable=SC2034
    PERSIST_VARS=(
        # 外部输入
        L1_CHAIN_ID
        L2_CHAIN_ID
        L1_RPC_URL
        L1_VAULT_PRIVATE_KEY
        KURTOSIS_L1_VAULT_PRIVATE_KEY
        KURTOSIS_L1_PREALLOCATED_MNEMONIC
        KURTOSIS_L1_FUND_VAULT_ADDRESS
        L1_BRIDGE_HUB_CONTRACT
        L1_REGISTER_BRIDGE_PRIVATE_KEY

        # 运行过程中生成/推导的变量
        ENCLAVE_NAME
        NETWORK
        CLAIM_SERVICE_PRIVATE_KEY
        # L2_PRIVATE_KEY 用途：
        # - L2 上部署 Counter 合约（bridge 注册流程依赖）
        # - ydyl-gen-accounts 的付款/部署账户（写入 ydyl-gen-accounts/.env 的 PRIVATE_KEY）
        L2_PRIVATE_KEY
        L2_ADDRESS
        CLAIM_SERVICE_ADDRESS
        L1_REGISTER_BRIDGE_ADDRESS
        L2_RPC_URL
        L1_RPC_URL_PROXY
        L2_VAULT_PRIVATE_KEY
        COUNTER_BRIDGE_REGISTER_RESULT_FILE
        METADATA_FILE
        L2_COUNTER_CONTRACT
    )
}

check_env_compat() {
    if [[ -f "$STATE_FILE" ]]; then
        check_input_env_consistency L1_CHAIN_ID
        check_input_env_consistency L2_CHAIN_ID
        check_input_env_consistency L1_RPC_URL
        check_input_env_consistency L1_VAULT_PRIVATE_KEY
        check_input_env_consistency KURTOSIS_L1_VAULT_PRIVATE_KEY
        check_input_env_consistency KURTOSIS_L1_PREALLOCATED_MNEMONIC
        check_input_env_consistency KURTOSIS_L1_FUND_VAULT_ADDRESS
        check_input_env_consistency L1_BRIDGE_HUB_CONTRACT
        check_input_env_consistency L1_REGISTER_BRIDGE_PRIVATE_KEY
    fi
}

require_inputs() {
    if [[ -z "${L2_CHAIN_ID:-}" ]] || [[ -z "${L1_CHAIN_ID:-}" ]] || [[ -z "${L1_RPC_URL:-}" ]] || [[ -z "${L1_VAULT_PRIVATE_KEY:-}" ]] || [[ -z "${L1_BRIDGE_HUB_CONTRACT:-}" ]] || [[ -z "${L1_REGISTER_BRIDGE_PRIVATE_KEY:-}" ]]; then
        echo "错误: 缺少必须的环境变量，请设置：L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY,L1_BRIDGE_HUB_CONTRACT,L1_REGISTER_BRIDGE_PRIVATE_KEY"
        echo "变量说明:"
        echo "  L2_CHAIN_ID: L2 链的 chain id"
        echo "  L1_CHAIN_ID: L1 链的 chain id"
        echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
        echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户私钥（用于 step2 给部署相关账户转 L1 ETH）"
        echo "  L1_BRIDGE_HUB_CONTRACT: L1 中继合约地址"
        echo "  L1_REGISTER_BRIDGE_PRIVATE_KEY: L1 注册 bridge 的私钥"
        exit 1
    fi

    # 注意：KURTOSIS_L1_VAULT_PRIVATE_KEY 不再默认与 L1_VAULT_PRIVATE_KEY 绑定；
    # 若未设置，会在 gen_op_enclave_deploy_accounts 中自动生成随机值。
}

parse_start_step_and_export_restored() {
    pipeline_parse_start_step "$@"
    if [[ -n "${KURTOSIS_L1_PREALLOCATED_MNEMONIC:-}" ]]; then export KURTOSIS_L1_PREALLOCATED_MNEMONIC; fi
    if [[ -n "${CLAIM_SERVICE_PRIVATE_KEY:-}" ]]; then export CLAIM_SERVICE_PRIVATE_KEY; fi
    # L2_PRIVATE_KEY 用途见上方 PERSIST_VARS 注释（部署 Counter、gen-accounts 付款/部署账户）
    if [[ -n "${L2_PRIVATE_KEY:-}" ]]; then export L2_PRIVATE_KEY; fi
    if [[ -n "${L2_ADDRESS:-}" ]]; then export L2_ADDRESS; fi
    if [[ -n "${L2_TYPE:-}" ]]; then export L2_TYPE; fi
}

########################################
# STEP3: 启动 jsonrpc-proxy（L1/L2 RPC 代理） - OP 专属
########################################
step3_start_jsonrpc_proxy() {
    if [[ "${ENABLE_L1_RPC_RROXY:-}" = "true" ]]; then
        echo "🔹 跳过启动 jsonrpc-proxy, 直接使用 L1_RPC_URL 作为 L1_RPC_URL_PROXY"
        L1_RPC_URL_PROXY=$L1_RPC_URL
        export L1_RPC_URL_PROXY
        return 0
    fi

    cd "$DIR"/jsonrpc-proxy || return 1
    # shellcheck disable=SC2153
    cat >.env_op <<EOF
CORRECT_BLOCK_HASH=true
LOOP_CORRECT_BLOCK_HASH=true
PORT=3030
JSONRPC_URL=$L1_RPC_URL
L2_RPC_URL=$L2_RPC_URL
EOF
    npm i
    npm run start:op
    L1_RPC_URL_PROXY=http://$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'):3030
    export L1_RPC_URL_PROXY
}

########################################
# STEP4: 部署 kurtosis op - OP 专属
########################################
step4_deploy_kurtosis_op() {
    : "${L1_RPC_URL_PROXY:?L1_RPC_URL_PROXY 未设置，请先运行 STEP3 启动 jsonrpc-proxy}"
    # 只对 deploy.sh 这一条命令临时注入 L1_RPC_URL，不污染当前 shell 的 L1_RPC_URL
    L1_RPC_URL="$L1_RPC_URL_PROXY" "$DIR"/op-work/scripts/deploy.sh "$ENCLAVE_NAME"

    local wallet_path="$DIR/op-work/output/op-deployer-configs-$ENCLAVE_NAME/wallets.json"
    require_file "$wallet_path"
    L2_VAULT_PRIVATE_KEY=$(jq -r ".[$L2_CHAIN_ID|tostring].l2FaucetPrivateKey" "$wallet_path")
    if [[ -z "${L2_VAULT_PRIVATE_KEY:-}" ]] || [[ "$L2_VAULT_PRIVATE_KEY" = "null" ]]; then
        echo "错误: wallet.json 缺少 l2FaucetPrivateKey: $wallet_path" >&2
        return 1
    fi
    export L2_VAULT_PRIVATE_KEY
}

########################################
# STEP6: 生成 OP 相关 env（op-work/scripts 下生成，再拷贝到服务目录） - OP 专属
########################################
step6_gen_op_claim_env() {
    "$DIR/op-work/scripts/gen-op-claim-service-env.sh" "$ENCLAVE_NAME"

    require_file "$DIR/op-work/output/op-claim-service.env"
    require_file "$DIR/op-work/output/op-counter-bridge-register.env"

    mkdir -p "$DIR/op-claim-service" || return 1
    cp "$DIR/op-work/output/op-claim-service.env" "$DIR/op-claim-service/.env"

    mkdir -p "$DIR/zk-claim-service" || return 1
    cp "$DIR/op-work/output/op-counter-bridge-register.env" "$DIR/zk-claim-service/.env.counter-bridge-register"
}

########################################
# STEP8: 启动 op-claim-service 服务 - OP 专属
########################################
step8_start_op_claim_service() {
    cd "$DIR"/op-claim-service || return 1
    npm i
    npm run start
}

run_all_steps() {
    ENABLE_L1_RPC_RROXY=true
    run_step 1 "初始化身份和密钥" step1_init_identities
    gen_op_enclave_deploy_accounts
    run_step 2 "从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH" step2_fund_l1_accounts
    run_step 3 "启动 jsonrpc-proxy（L1/L2 RPC 代理）" step3_start_jsonrpc_proxy
    run_step 4 "部署 kurtosis op" step4_deploy_kurtosis_op
    run_step 5 "给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH" step5_fund_l2_accounts
    run_step 6 "生成 OP 相关 env 并拷贝到服务目录" step6_gen_op_claim_env
    run_step 7 "部署 counter 合约并注册 bridge 到 L1 中继合约" step7_deploy_counter_and_register_bridge
    run_step 8 "启动 op-claim-service 服务" step8_start_op_claim_service
    run_step 9 "运行 ydyl-gen-accounts 脚本生成账户" step9_gen_accounts
    run_step 10 "收集元数据、保存到文件，供外部查询" step10_collect_metadata
    run_step 11 "启动 ydyl-console-service 服务" step11_start_ydyl_console_service
    run_step 12 "检查 PM2 进程是否有失败" step12_check_pm2_online
    echo "🔹 所有步骤完成"
}

main() {
    init_paths
    load_libs
    ydyl_enable_traps
    # echo "test exit trap" && exit 1
    init_network_vars
    record_input_vars
    load_state_and_check_tools
    init_persist_vars
    check_env_compat
    require_inputs
    parse_start_step_and_export_restored "$@"
    run_all_steps
}

main "$@"
