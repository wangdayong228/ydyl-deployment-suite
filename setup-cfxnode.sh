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

echo "🚀 [1/5] Run cross script..."
(cd "${DIR}/cfxnode-work/jsscripts" && npm run cross)
echo "✅ [1/5] Run cross script done"

echo "🚀 [2/5] Deploy deterministic contract..."
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 100ether 0x3fab184622dc19b6109349b94811493bf2a45362
cast rpc eth_sendRawTransaction 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 --rpc-url "${L1_RPC_URL}" || true
echo "✅ [2/5] Deploy deterministic contract done"

echo "🌉 [3/5] Deploy bridge contract..."
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 100ether 0xef431755Bb97ed53874E3e27cAD2cD3399558e25
cd "${DIR}/zk-claim-service" && yarn && PRIVATE_KEY=0xa3d9e98f0ba98960bf3755b7519d18b2250b0b8be5e38d5483dcfa3875df2d6f npx hardhat ignition deploy ignition/modules/4_deployzkBR.js --network espacedev --reset
echo "✅ [3/5] Deploy bridge contract done"

echo "🛰️ [4/5] Start jsonrpc-proxy-op..."
ssh ubuntu@184.32.182.132 'zsh -ic "cd ~/workspace/ydyl-deployment-suite/jsonrpc-proxy && (npm run clear || true) && (pm2 delete jsonrpc-proxy-op || true) && npm run start:op"'
echo "✅ [4/5] Start jsonrpc-proxy-op done"

echo "🔄 [5/5] Fund zh and xjst accounts..."
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 10000000ether 0x0f9B62bA159D889A9413Fd0DD742C409a9841793 # xr
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 10000000ether 0x4b2a49E584da4a9F7332d9877B07c0b3198B4c0E # zh
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 10000000ether 0x2Ac47Df8DC45AAcc0FfBDb285477C79c54F17169 # xr
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 10000000ether 0xcE4CC6E76635FfAAD91a587f204011D3d3B96EB9 # dy
cast send --legacy --rpc-url "${L1_RPC_URL}" --private-key "${L1_VAULT_PRIVATE_KEY}" --value 10000000ether 0x5E145d90C81656F151aabd5fd1ff5339AA8C95c1 # dy
echo "✅ [5/5] Fund zh and xjst accounts done"