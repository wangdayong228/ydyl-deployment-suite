| 决策主题 | 已确认决策 | 来源 | 确认日期 |
| --- | --- | --- | --- |
| Core BatchSender 部署范围 | 为 Core Space 增加单合约 BatchSender 部署能力：扩展共享 deployBatchSender helper 和 scripts/1_deployBatchSender.ts；不修改 scripts/3_concurrency.ts，不接入多合约部署、付款账户充值或 PM2 编排。 | 用户明确回答 | 2026-09-04 |
| Core BatchSender 部署设计 | 采用方案 A：在 scripts/coreSpaceClient.ts 实现可复用的 deployCoreBatchSender，由 scripts/batchSenderClient.ts 的 deployBatchSender 在 l2type=3 时分派；scripts/1_deployBatchSender.ts 增加 Core CLI。部署显式使用 RPC status.chainId、nonce、epoch、gasPrice、估算 gas/storageLimit 及 20% 余量，value 固定为 0；等待 executed 回执，将 contractCreated 统一校验为 0x Core 合约地址，并读回 startAddressIndex 与 totalCount，一致后才成功。保留原 Hardhat/ethers 行为且不修改 scripts/3_concurrency.ts。 | 用户明确回答 | 2026-09-04 |
