# `ydyl-gen-accounts` by-contract `--retryUntilSuccess`

## 背景

`npm run start`（`scripts/3_concurrency.ts`）默认拉起 by-contract worker。当前失败语义：

- 提交失败：`sendSingleChunk` 内部最多重试 10 次，仍失败则停止后续 chunk。
- 回执失败：`waitLastReceipt` 对窗口最后一笔只告警并结束本次 flush，继续下一窗口。

需要一个 opt-in flag：打开后卡住**当前这笔**，直到提交成功且回执成功才向前推进。默认行为保持不变。

本 spec 不改变 [2026-09-03 Core Space spec](2026-09-03-gen-accounts-core-space-support-spec.md) 的默认失败、窗口与进度语义；仅增加 by-contract 的 opt-in。

## 目标

- 为 `scripts/2_genAccsByContract.ts` 增加 `--retryUntilSuccess`（默认关闭）。
- `scripts/3_concurrency.ts` / `npm run start` 把该 flag 透传给 PM2 by-contract worker。
- 关闭时行为与现在完全一致。
- 打开后：提交失败与回执失败都无限重试当前这笔，成功才推进。

## 非目标

- 不改 `scripts/2_genAccsByEoa.ts`。
- 不改 `op_pipe.sh`、`xjst_pipe.sh`、deploy-client 远端 `gen-accounts start`。
- 不把公共 `retry()` 改成无限重试。
- 不改变 `txQueueLimit` 窗口大小、只等最后一笔、`DEBUG_SENT_CHECK`。
- `ydyl-gen-accounts` CLI 默认仍关闭；仅 CDK 流水线默认打开。

## 方案选择

采用：在现有发送 / flush 控制流上加分支。默认路径保留 `break` / `return`。发送与 flush 抽到 `scripts/byContractSend.ts`，供 worker 与单测共用；`2_genAccsByContract.ts` 负责 CLI / 运行时并调用它。

不采用：修改公共 `retry()`。部署与充值调用方会被波及。

不采用：重写独立发送器。会替换已验证的窗口与超时补发。

## 行为

### Flag

- CLI：`--retryUntilSuccess`（boolean，默认 `false`）。
- 环境变量：`RETRY_UNTIL_SUCCESS`，沿用 `envToBool`（`1` / `true` / `yes` / `y` / `on`）。
- `3_concurrency.ts` 增加同名 option；为 true 时向 by-contract worker args 追加 `--retryUntilSuccess`；为 false 时不追加。dryRun 预览命令同步。
- 不传给 by-eoa worker。

### CDK 流水线

`cdk_pipe.sh` 将 `RETRY_UNTIL_SUCCESS` 默认设为 `true` 并 export，step9 的 `npm run start` 继承该环境变量，`3_concurrency.ts` 再透传给 PM2 by-contract worker。调用方可显式设 `RETRY_UNTIL_SUCCESS=false` 覆盖。不写入 `PERSIST_VARS`，不做 `check_input_env_consistency`。`op_pipe.sh` / `xjst_pipe.sh` 不设该默认。

### CLI 默认关闭（未开 flag 且无环境变量）

- 提交失败：内部 10 次后停发后续 chunk，进度可标 `fail`，进程不因该失败 `exit 1`。
- 回执失败：告警并结束本次 flush，继续下一窗口；不刷新 nonce、不重发该 batch。

### 打开后

成功定义：该笔 `batchSendETH` 已提交，且 `isTxReceiptSuccess` 为 true。

- **提交失败：** `sendSingleChunk` 仍每次内部最多 10 次；外层按约 1s 间隔重复调用，直到 `tx != null`。不再 `break`。
  - 瞬时 RPC 错误：沿用当前 `assignedNonce`。
  - `nonce too low` / `nonce has already been used`：该 nonce 已被占用。调用 `prepareWindowTxParams` 取当前 pending nonce；若已前进，改用新 nonce 再发，禁止钉死原 nonce。
  - `already known` / `known transaction`：优先从错误中提取交易 hash，当作该笔已提交并等待回执。提取不到 hash 时先查 pending nonce：已前进则按 nonce 占用处理，否则仍用原 nonce 重试提交。
- **回执失败：** 交易已上链，nonce 已消耗。只重试窗口**最后一条**对应的 batch（按下标 `length-1` 钉死，不按「谁还握着 tx 对象」重选）。即使该条补发提交失败写成 `tx: null`，后续仍只重试这一条。调用 `prepareWindowTxParams` 取新 nonce，再 `batchSendETH`，然后继续等回执。不得复用失败交易的 nonce，也不得把窗口内更早的已上链交易再发一遍。等待回执时同样只等这一条。
- **超时 / 链上找不到交易：** 仍走现有同 nonce 补发。
- 进程不因「一直重试」而 `exit 1`。SIGINT / SIGTERM 仍可中断。

## 测试

用 mock `BatchSenderWriterLike` 覆盖：

1. 默认：提交失败后不再对后续 chunk 调用 `batchSendETH`。
2. flag：提交先失败再成功，继续后续 chunk。
3. 默认：最后一笔回执失败，不调用 `prepareWindowTxParams` 重发。
4. flag：最后一笔回执失败后取新 nonce 并只重发该 batch，成功后结束 flush。
5. `3_concurrency`：flag 为 true 时 worker args 含 `--retryUntilSuccess`，为 false 时不含。
6. flag：最后一笔回执失败后补发提交先失败再成功，全程只重发最后一条 batch，不打到窗口内更早的交易。
7. flag：提交报 `nonce too low` 且 pending nonce 已前进时，后续 `batchSendETH` 使用新 nonce。
8. flag：提交报 `already known` 且错误含交易 hash 时，当作已提交等待回执，不再用新 nonce 重发同一 batch。
