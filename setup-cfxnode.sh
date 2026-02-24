#!/bin/bash
set -Eueo pipefail
set -x

########################################
#	-1.1 启动后自动部署 deterministic 合约
#		- 1.1.1 `cast send --legacy --rpc-url $L1_RPC_URL --private-key $L1_VAULT_PRIVATE_KEY --value 100ether 0x3fab184622dc19b6109349b94811493bf2a45362`
#		- 1.1.2 `cast rpc eth_sendRawTransaction 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 --rpc-url`
#	-1.2 部署 bridge 合约
#		- 1.2.1 `cast send --legacy --rpc-url $L1_RPC_URL --private-key $L1_VAULT_PRIVATE_KEY --value 100ether 0xef431755Bb97ed53874E3e27cAD2cD3399558e25`
#		- 1.2.2 `PRIVATE_KEY=0xa3d9e98f0ba98960bf3755b7519d18b2250b0b8be5e38d5483dcfa3875df2d6f npx hardhat ignition deploy ignition/modules/4_deployzkBR.js --network espacedev`
#	-1.3 启动 jsonrpc-proxy-op `ssh root@47.83.135.176 'zsh -ic "cd ~/workspace/jsonrpc-proxy && (npm run clear || true) && (pm2 delete jsonrpc-proxy-op || true) && npm run start:op"'`
########################################

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 [1/3] Deploy deterministic contract..."
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 100ether 0x3fab184622dc19b6109349b94811493bf2a45362
cast rpc eth_sendRawTransaction 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 --rpc-url "${L1_RPC_URL}" || true
echo "✅ [1/3] Deploy deterministic contract done"

echo "🌉 [2/3] Deploy bridge contract..."
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 100ether 0xef431755Bb97ed53874E3e27cAD2cD3399558e25
cd "${DIR}/zk-claim-service" && PRIVATE_KEY=0xa3d9e98f0ba98960bf3755b7519d18b2250b0b8be5e38d5483dcfa3875df2d6f npx hardhat ignition deploy ignition/modules/4_deployzkBR.js --network espacedev --reset
echo "✅ [2/3] Deploy bridge contract done"

echo "🛰️ [3/3] Start jsonrpc-proxy-op..."
ssh root@47.83.135.176 'zsh -ic "cd ~/workspace/jsonrpc-proxy && (npm run clear || true) && (pm2 delete jsonrpc-proxy-op || true) && npm run start:op"'
echo "✅ [3/3] Start jsonrpc-proxy-op done"
