# TPS getLogs too-many-logs 递归折半

`tps` 监控在压测高峰对 `eth_getLogs` / `cfx_getLogs` 一次拉太多匹配日志时，RPC 返回 `too many logs, max limitation is 5000`。缩小 job `block_range` 解决不了「游标已追上、本轮只落后一百多块」的窗口。对当前区间递归折半，直到单次请求不再超限；仅单块（或单 epoch）仍超限才放弃。

## 背景

现网失败示例（Conflux eSpace / EVM RPC）：

- 方法：`eth_getLogs`
- 错误：`-32602` `too many logs, max limitation is 5000, please use a smaller block range`
- 窗口：`fromBlock 0x113e18`（1121816）→ `toBlock 0x113e8d`（1121933）= **117 块**

CLI `--block-range` 默认已是 300（`ydyl-deploy-client/cmd/gen_cross_tx_config.go`）。117 < 300，把默认改成 200/100 **不会改变这次请求**。

`job#0 network type xjst blk range to query: 261,480` 不是 range=261480。日志写 `${blockbatches}` 时 `[[261, 480]].toString()` 变成 `"261,480"`，即 epoch 261 到 480。

`block_range` 被同时当成：

1. 首次追赶 lookback
2. `blockBatch()` 的 getLogs 切分大小

游标追上后，一轮若只落后 117 块，就打成一批 117。压测时每个块匹配日志很多（多个 topic OR），容易超过 5000。外层 monitor 只对同一窗口 retry，不会变小。

L1 旧 `getLogsWithPagination` 只从错误文案解析 `[from, to]`。eSpace 文案没有建议区间，解析失败后原样抛错。

xjst L2 走 `cfx_getLogs`（epoch 区间），同样可能超限；与 EVM 用同一套递归折半，只是 `fetchLogs` 把数字区间编成 `fromEpoch`/`toEpoch`。

## 目标

- lookback 与 getLogs 切分分离：`--block-range` 继续只当 lookback / `blockBatch` 上限，**不改**默认 300
- 对当前 `[from, to]`（EVM 块号或 xjst epoch）做 getLogs；too-many-logs 时递归折半，直到成功
- L2 `pollEvm`（op/cdk）与 `pollConflux`（xjst）、L1 `pollEvm` 都走同一 helper
- 日志用 `JSON.stringify(blockbatches)`，避免把 `[261, 480]` 看成 261480
- 已生成的 `all.json` 不必重跑 `gen-cross-tx-config`

## 非目标

- 不改 `--block-range` CLI 默认值
- 不改 `g_L2eventmonitor.js` 等非 TPS 脚本
- 不改编排：Go `tps` 仍只起 compose tps service

## 行为

对当前闭区间 `[from, to]`：

1. 调用一次 `fetchLogs(from, to)`
2. 成功 → 返回这批 logs
3. 若是 too-many-logs：
   - 错误文案里若有建议区间 `[n, m]`，可作为快路径：先拉 `[from, min(m, to)]`，再处理剩余；该快路径若仍 too-many-logs，回退到折半
   - `from === to`（已是单块 / 单 epoch）→ 无法再拆，上抛
   - 否则 `mid = floor((from + to) / 2)`，先 `[from, mid]`，再 `[mid+1, to]`；**每一半若再报同样错误，继续对自己折半**
4. 其它错误原样上抛，不折半

识别 too-many-logs：错误链上 `code === -32602`，或 message/data 含 `too many logs` / `smaller block range`（覆盖 eSpace 无 `[from, to]` 的文案）。

例：117 块超限 → 约 58+59 → 左半仍超限再拆约 29+29，直到单次日志数 ≤ 5000。不是只折一次。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `zk-claim-service/scripts/lib/getLogsPaginated.js` | 递归折半 + 建议区间快路径 |
| `zk-claim-service/scripts/lib/getLogsPaginated.test.js` | mock `fetchLogs`：一次折半、嵌套折半、单块失败、eSpace 文案 |
| `zk-claim-service/scripts/h_L2TPSCalulation.js` | `pollEvm` / `pollConflux` 走 helper；`JSON.stringify(blockbatches)` |
| `zk-claim-service/scripts/i_L1TPSCalulation.js` | 替换无效 pagination；`pollEvm` / `pollConflux` 走 helper；同样改日志 |

## 验证

```bash
cd zk-claim-service
node --test scripts/lib/getLogsPaginated.test.js
```
