## 私链 IP
- 34.219.245.189
- 52.12.11.65
- 16.148.64.138

## 私链 有钱账户
```sh
Successfully created new keypair.
CFX Address: 0x111C290704B850d2be9aC5F486fD7073B7ce4Ad9
Address:     0x311C290704B850d2be9aC5F486fD7073B7ce4Ad9
Private key: 0xb4810523501eec2591a2652c4394feb884129f78c940a2bf23efdf6046d08677
 
Successfully created new keypair.
CFX Address: 0x16e9E556252146E09419ce9590E6F178a9D6D88B
Address:     0x86e9E556252146E09419ce9590E6F178a9D6D88B
Private key: 0x37398ebb49943b3326a7bb4e8c3aed4b3aed6c4b09b1b197b8c85a6686e774ad
 
Successfully created new keypair.
CFX Address: 0x19619a70899B445859Fc86120CD9Ff74e6252A2D
Address:     0x09619a70899B445859Fc86120CD9Ff74e6252A2D
Private key: 0x53bfe542f225644873d7dfc74306e91c192e782f39d52e5b07dc4127dc6328b2
```

## confura 
```sh
# Example .env file
# cfxbridge
INFURA_RPC_CFXBRIDGE_ETHNODE='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_LOG_LEVEL=debug
# core space cluster nodes
INFURA_NODE_URLS='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_CFXFULLSTATE='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_WSURLS='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_LOGNODES='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
# evm space cluster nodes
INFURA_NODE_FILTERNODES='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_ETHURLS='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_ETHFULLSTATEURLS='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_ETHLOGNODES='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_ETHFILTERNODES='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_NODE_ETHWSURLS='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
INFURA_ETH_REQUESTTIMEOUT=10s
# ethrpc
INFURA_ETHRPC_WSENDPOINT=:28535
# ethsync
INFURA_ETH_HTTP='http://34.219.245.189:8545,http://52.12.11.65:8545,http://16.148.64.138:8545'
```

## 修改记录

### 2026.3.5 辰星总结

跨链性能和单笔互操作性能开销基本上搞清楚了，大概是

首先是单笔交易的性能优化：

21000 (交易硬开销，可以通过 batch 成一个 tx 均摊) + 1000（tx data 硬开销）+ 61000 （第一层调用，其中 50000 来自于写数据）+ 32000（第二层调用）+8000（第三层调用，其中 5000 可能来自于 counter 写数据），总计约 12 万开销

其中，batch 操作可以通过 EIP-2929 优化节省一些开销。

 @Cooper 需要大幅删减合约写数据操作，通过 confura 改成 emit event & eth_getLogs 的操作，或者 batch 均摊掉。新增数据开销 20000 gas，修改数据开销 5000 gas，我们的总预算可能只有 20000 gas / 条消息。
 @S1m0n 需要修改第二层调用中不必要的循环 mem copy
 @小蜗牛 下次重启底链时，部署一个 confura，这个好像是个 docker 可以直接部署。
另外，L1 上互操作交易的 gas limit 偏高，向荣需要找一个尽可能低的能通过的 gas limit。

然后是跨链的性能优化

1. 参数 max_block_size_in_bytes 增加至 1MB
2. 关闭 CIP-130, 目前没有单独控制 CIP-130 的参数， @Pana 可以加一下。
3. 有一处逻辑不受参数 evm_transaction_gas_ratio 控制，就是 函数 pack_transactions_1559 里，let gas_target = block_gas_limit * 5 / 10 / ELASTICITY_MULTIPLIER; 导致事实上的打包 capacity 还是一半，这里应该修一下，根据参数来，pana 可以一起修一下。

以上三点修改后需要清库重启整条链。
