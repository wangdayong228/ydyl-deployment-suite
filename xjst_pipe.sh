#!/bin/bash
set -Eueo pipefail
# set -x

########################################
# 使用说明（简要）
# 1. 必须传入（用户提供）的环境变量：
#    - L1_CHAIN_ID: L1 链 chain id（用于部署/元数据记录/区分网络）
#    - L2_CHAIN_ID: L2 链 chain id（用于部署/元数据记录/区分网络）
#    - L1_RPC_URL: 连接 L1 的 RPC 地址（用于 L1 转账、以及 jsonrpc-proxy 上游）
#    - L1_VAULT_PRIVATE_KEY（或 KURTOSIS_L1_VAULT_PRIVATE_KEY 二选一）:
#        L1 主资金账户私钥（用于给部署相关账户转 L1 ETH；同时用于推导 KURTOSIS_L1_FUND_VAULT_ADDRESS）
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
#    - KURTOSIS_L1_FUND_VAULT_ADDRESS: 由 L1_VAULT_PRIVATE_KEY 推导（用于 step2 接收 L1 资金）
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
	STATE_FILE="$DIR/output/xjst_pipe.state"
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

gen_xjst_deploy_accounts() {
	# 直接使用 L1_VAULT_PRIVATE_KEY 作为 KURTOSIS_L1_VAULT_PRIVATE_KEY，因为 xjst 只有一个持续使用L1私钥发交易的地方，就是调用 l1_unified_bridge
	# 也是为了简化 node2-4 从 node-1 获取 L1 私钥
	KURTOSIS_L1_VAULT_PRIVATE_KEY="${L1_VAULT_PRIVATE_KEY}"
	export KURTOSIS_L1_VAULT_PRIVATE_KEY
	KURTOSIS_L1_FUND_VAULT_ADDRESS=$(cast wallet address --private-key "$KURTOSIS_L1_VAULT_PRIVATE_KEY")
	export KURTOSIS_L1_FUND_VAULT_ADDRESS
}

# reset_l2_private_key() {
# 	L2_PRIVATE_KEY=""
# 	export L2_PRIVATE_KEY

# 	L2_ADDRESS=""
# 	export L2_ADDRESS
# }

record_input_vars() {
	# shellcheck disable=SC2034
	INPUT_L1_CHAIN_ID="${L1_CHAIN_ID-}"
	# shellcheck disable=SC2034
	INPUT_L2_CHAIN_ID="${L2_CHAIN_ID-}"
	# shellcheck disable=SC2034
	INPUT_L1_RPC_URL="${L1_RPC_URL-}"
	# shellcheck disable=SC2034
	INPUT_L1_RPC_URL_WS="${L1_RPC_URL_WS-}"
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
	# shellcheck disable=SC2034
	INPUT_CHAIN_NODE_IPS="${CHAIN_NODE_IPS-}"
	# shellcheck disable=SC2034
	INPUT_NODE_ID="${NODE_ID-}"
	# shellcheck disable=SC2034
	INPUT_GROUP_ID="${GROUP_ID-}"
}

load_state_and_check_tools() {
	pipeline_load_state
	
	# install python venv and dependencies
	python3 -m venv .venv
	source "$DIR/.venv/bin/activate"
	python -m pip install -U pip
	pip install web3==6.20.1 eth-account==0.10.0

	require_commands cast jq pm2 awk envsubst ip npm yarn node python
}

init_persist_vars() {
	# shellcheck disable=SC2034
	PERSIST_VARS=(
		# 外部输入
		L1_CHAIN_ID
		L2_CHAIN_ID
		L1_RPC_URL
		L1_RPC_URL_WS
		L1_VAULT_PRIVATE_KEY
		KURTOSIS_L1_VAULT_PRIVATE_KEY
		KURTOSIS_L1_PREALLOCATED_MNEMONIC
		KURTOSIS_L1_FUND_VAULT_ADDRESS
		L1_BRIDGE_HUB_CONTRACT
		L1_REGISTER_BRIDGE_PRIVATE_KEY
		CHAIN_NODE_IPS
		NODE_ID
		GROUP_ID

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
		L2_VAULT_PRIVATE_KEY
		COUNTER_BRIDGE_REGISTER_RESULT_FILE
		METADATA_FILE
		L2_COUNTER_CONTRACT
		L1_SIMPLE_CALCULATOR_ADDR
		L1_STATE_SENDER_ADDR
		L1_UNIFIED_BRIDGE_ADDR
	)
}

check_env_compat() {
	if [[ -f "$STATE_FILE" ]]; then
		check_input_env_consistency L1_CHAIN_ID
		check_input_env_consistency L2_CHAIN_ID
		check_input_env_consistency L1_RPC_URL
		check_input_env_consistency L1_RPC_URL_WS
		check_input_env_consistency L1_VAULT_PRIVATE_KEY
		check_input_env_consistency KURTOSIS_L1_VAULT_PRIVATE_KEY
		check_input_env_consistency KURTOSIS_L1_PREALLOCATED_MNEMONIC
		check_input_env_consistency KURTOSIS_L1_FUND_VAULT_ADDRESS
		check_input_env_consistency L1_BRIDGE_HUB_CONTRACT
		check_input_env_consistency L1_REGISTER_BRIDGE_PRIVATE_KEY
		check_input_env_consistency CHAIN_NODE_IPS
		check_input_env_consistency NODE_ID
		check_input_env_consistency GROUP_ID
	fi
}

require_inputs() {
	if [[ -z "${L2_CHAIN_ID:-}" ]] || [[ -z "${L1_CHAIN_ID:-}" ]] || [[ -z "${L1_RPC_URL:-}" ]] || [ -z "${L1_RPC_URL_WS:-}" ] || [[ -z "${L1_VAULT_PRIVATE_KEY:-}" ]] || [[ -z "${L1_BRIDGE_HUB_CONTRACT:-}" ]] || [[ -z "${L1_REGISTER_BRIDGE_PRIVATE_KEY:-}" ]] || [[ -z "${CHAIN_NODE_IPS:-}" ]] || [[ -z "${NODE_ID:-}" ]] || [[ -z "${GROUP_ID:-}" ]]; then
		echo "错误: 缺少必须的环境变量，请设置：L2_CHAIN_ID,L1_CHAIN_ID,L1_RPC_URL,L1_VAULT_PRIVATE_KEY,L1_BRIDGE_HUB_CONTRACT,L1_REGISTER_BRIDGE_PRIVATE_KEY,CHAIN_NODE_IPS,NODE_ID"
		echo "变量说明:"
		echo "  L2_CHAIN_ID: L2 链的 chain id"
		echo "  L1_CHAIN_ID: L1 链的 chain id"
		echo "  L1_RPC_URL: 连接 L1 的 RPC 地址"
		echo "  L1_RPC_URL_WS: 连接 L1 的 WS 地址"
		echo "  L1_VAULT_PRIVATE_KEY: L1 主资金账户私钥（用于 step2 给部署相关账户转 L1 ETH）"
		echo "  L1_BRIDGE_HUB_CONTRACT: L1 中继合约地址"
		echo "  L1_REGISTER_BRIDGE_PRIVATE_KEY: L1 注册 bridge 的私钥"
		echo "  CHAIN_NODE_IPS: 链节点 IP 地址数组"
		echo "  NODE_ID: 链节点 ID"
		echo "  GROUP_ID: 链组 ID"
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

# ########################################
# # STEP3: 启动 jsonrpc-proxy（L1/L2 RPC 代理） - OP 专属
# ########################################
# step3_start_jsonrpc_proxy() {
#     if [[ "${ENABLE_L1_RPC_RROXY:-}" = "true" ]]; then
#         echo "🔹 跳过启动 jsonrpc-proxy, 直接使用 L1_RPC_URL 作为 L1_RPC_URL_PROXY"
#         L1_RPC_URL_PROXY=$L1_RPC_URL
#         export L1_RPC_URL_PROXY
#         return 0
#     fi

#     cd "$DIR"/jsonrpc-proxy || return 1
#     # shellcheck disable=SC2153
#     cat >.env_op <<EOF
# CORRECT_BLOCK_HASH=true
# LOOP_CORRECT_BLOCK_HASH=true
# PORT=3030
# JSONRPC_URL=$L1_RPC_URL
# L2_RPC_URL=$L2_RPC_URL
# EOF
#     npm i
#     npm run start:op
#     L1_RPC_URL_PROXY=http://$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'):3030
#     export L1_RPC_URL_PROXY
# }

########################################
# STEP3: 部署 l1 合约 - XJST 专属
########################################
step3_deploy_l1_contracts() {
	if [[ "${NODE_ID}" != "node-1" ]]; then
		echo "🔹 跳过部署 l1 合约, 因为不是 node-1"
		return 0
	fi
	source "$DIR/.venv/bin/activate"
	deploy_l1_contracts_py="$DIR/xjst-work/docker_builder/deploy_l1_contracts.py"
	python "$deploy_l1_contracts_py" --rpc-url "${L1_RPC_URL}" --chain-id "${L1_CHAIN_ID}" --private-key "${KURTOSIS_L1_VAULT_PRIVATE_KEY}"

	local l1_contracts_file="$DIR"/xjst-work/output/contracts.json
	local l1_contracts
	l1_contracts=$(cat "$l1_contracts_file")

	L1_SIMPLE_CALCULATOR_ADDR=$(echo "$l1_contracts" | jq -r '.simple_calculator // empty')
	export L1_SIMPLE_CALCULATOR_ADDR
	L1_STATE_SENDER_ADDR=$(echo "$l1_contracts" | jq -r '.state_sender // empty')
	export L1_STATE_SENDER_ADDR
	L1_UNIFIED_BRIDGE_ADDR=$(echo "$l1_contracts" | jq -r '.unified_bridge // empty')
	export L1_UNIFIED_BRIDGE_ADDR

	require_var L1_SIMPLE_CALCULATOR_ADDR
	require_var L1_STATE_SENDER_ADDR
	require_var L1_UNIFIED_BRIDGE_ADDR

	echo "🔹 L1_SIMPLE_CALCULATOR_ADDR: $L1_SIMPLE_CALCULATOR_ADDR"
	echo "🔹 L1_STATE_SENDER_ADDR: $L1_STATE_SENDER_ADDR"
	echo "🔹 L1_UNIFIED_BRIDGE_ADDR: $L1_UNIFIED_BRIDGE_ADDR"
}

########################################
# STEP4: 部署 kurtosis op - OP 专属
########################################
step5_deploy_xjst_node() {
	deploy_node_script="$DIR/xjst-work/client/deploy_node.sh"

	# 如果当前是 node-1, 则传合约地址，否则只设置 fetch_l1_from_node1 为 true
	L2_RPC_URL="http://$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'):30010"
	export L2_RPC_URL

	if [[ "${DRYRUN:-false}" = "true" ]]; then
		echo "🔹 DRYRUN=true，跳过部署 l1 合约"
		return 0
	fi

	if [[ "${NODE_ID}" == "node-1" ]]; then
		L1_SIMPLE_CALCULATOR_ADDR="${L1_SIMPLE_CALCULATOR_ADDR}" \
			L1_STATE_SENDER_ADDR="${L1_STATE_SENDER_ADDR}" \
			L1_UNIFIED_BRIDGE_ADDR="${L1_UNIFIED_BRIDGE_ADDR}" \
			CHAIN_NODE_IPS="${CHAIN_NODE_IPS}" \
			NODE_ID="$NODE_ID" \
			L1_ESPACE_RPC_URL="${L1_RPC_URL_WS}" \
			AUTO_DEPLOY_L1_CONTRACTS="false" \
			L1_ADMIN_PRIVATE_KEY="${KURTOSIS_L1_VAULT_PRIVATE_KEY}" \
			L1_ADMIN_ADDRESS="${KURTOSIS_L1_FUND_VAULT_ADDRESS}" \
			"$deploy_node_script"
	else
		FETCH_L1_FROM_NODE1="true" \
			CHAIN_NODE_IPS="${CHAIN_NODE_IPS}" \
			NODE_ID="$NODE_ID" \
			L1_ESPACE_RPC_URL="${L1_RPC_URL_WS}" \
			AUTO_DEPLOY_L1_CONTRACTS="false" \
			L1_ADMIN_PRIVATE_KEY="${KURTOSIS_L1_VAULT_PRIVATE_KEY}" \
			L1_ADMIN_ADDRESS="${KURTOSIS_L1_FUND_VAULT_ADDRESS}" \
			"$deploy_node_script"
	fi
}

step_wait_for_other_nodes_to_start() {
	node "$DIR"/xjst-work/js-scripts/checkNodePeers.js "${CHAIN_NODE_IPS}" 3
}

########################################
# STEP6: 生成 OP 相关 env（op-work/scripts 下生成，再拷贝到服务目录） - OP 专属
########################################
step6_gen_counter_bridge_register_env() {
	# "$DIR/op-work/scripts/gen-op-claim-service-env.sh" "$ENCLAVE_NAME"

	# require_file "$DIR/op-work/output/op-claim-service.env"
	# require_file "$DIR/op-work/output/op-counter-bridge-register.env"

	# mkdir -p "$DIR/op-claim-service" || return 1
	# cp "$DIR/op-work/output/op-claim-service.env" "$DIR/op-claim-service/.env"

	# mkdir -p "$DIR/zk-claim-service" || return 1
	# cp "$DIR/op-work/output/op-counter-bridge-register.env" "$DIR/zk-claim-service/.env.counter-bridge-register"

	echo "L1_RPC_URL=${L1_RPC_URL}
L2_RPC_URL=${L2_RPC_URL}
BRIDGES=${L1_UNIFIED_BRIDGE_ADDR},${L1_STATE_SENDER_ADDR}
L1_BRIDGE_HUB_CONTRACT=${L1_BRIDGE_HUB_CONTRACT}
L1_REGISTER_BRIDGE_PRIVATE_KEY=${L1_REGISTER_BRIDGE_PRIVATE_KEY}
L2_PRIVATE_KEY=${L2_PRIVATE_KEY}
L2_TYPE=${L2_TYPE}
" >"$DIR"/zk-claim-service/.env.counter-bridge-register
	echo "🔹 counter-bridge-register.env 文件已保存到 $DIR/zk-claim-service/.env.counter-bridge-register"
}

step7_deploy_counter_and_register_bridge_if_node1() {
	if [[ "${NODE_ID}" == "node-1" ]]; then
		run_step 7 "部署 counter 合约并注册 bridge 到 L1 中继合约" step7_deploy_counter_and_register_bridge
	else
		run_step 7 "跳过部署 counter 合约并注册 bridge 到 L1 中继合约, 因为当前是 ${NODE_ID}"
	fi
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
	if [[ "${NODE_ID}" != "node-1" ]]; then
		echo "🔹 当前是 ${NODE_ID}，跳过初始化身份和密钥，直接部署 xjst 节点"
		gen_xjst_deploy_accounts
		run_step 1 "部署 xjst 节点" step5_deploy_xjst_node
		echo "🔹 所有步骤完成"
		return 0
	fi

	run_step 1 "初始化身份和密钥" step1_init_identities
	gen_xjst_deploy_accounts
	# reset_l2_private_key
	run_step 2 "从 L1_VAULT_PRIVATE_KEY 转账 L1 ETH" step2_fund_l1_accounts
	run_step 3 "启动 ydyl-console-service 服务" step11_start_ydyl_console_service
	# run_step 3 "启动 jsonrpc-proxy（L1/L2 RPC 代理）" step3_start_jsonrpc_proxy
	run_step 4 "部署 l1 合约" step3_deploy_l1_contracts
	run_step 5 "部署 xjst 节点" step5_deploy_xjst_node
	# run_step 5 "给 L2_PRIVATE_KEY 和 CLAIM_SERVICE_PRIVATE_KEY 转账 L2 ETH" step5_fund_l2_accounts

	# 等待其它节点启动完成后，再执行后续步骤
	run_step 6 "等待其它节点启动完成后，再执行后续步骤" step_wait_for_other_nodes_to_start

	run_step 7 "生成 OP 相关 env 并拷贝到服务目录" step6_gen_counter_bridge_register_env
	run_step 8 "部署 counter 合约并注册 bridge 到 L1 中继合约" step7_deploy_counter_and_register_bridge_if_node1
	# run_step 8 "启动 op-claim-service 服务" step8_start_op_claim_service
	run_step 9 "运行 ydyl-gen-accounts 脚本生成账户" step9_gen_accounts
	run_step 10 "收集元数据、保存到文件，供外部查询" step10_collect_metadata
	run_step 11 "检查 PM2 进程是否有失败" step12_check_pm2_online
	echo "🔹 所有步骤完成"
}

main() {
	# ENABLE_L1_RPC_RROXY=false
	# KURTOSIS_L1_FUND_VAULT_ADDRESS="0x0000000000000000000000000000000000000000"
	L2_CHAIN_ID=0
	L2_TYPE=2

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
