# bench-cross-tx 未打包上限 max_unconfirmed

覆盖 [2026-09-07 unique-targets](2026-09-07-gen-cross-tx-config-unique-targets-spec.md) 与 [2026-09-08 typed-targets](2026-09-08-gen-cross-tx-config-typed-targets-spec.md) 中「xjst 源 `WaitForReceipts=false`」的约定。覆盖此前「每 N 笔等窗口全部 receipt / `receipt_wait_every`」策略。

## 背景

`bench-cross-tx` 通过 `ydyl-bench-docker` 跑 `7s_multijob.js` → `7r_multisend.js`。xjst 源 job 曾被硬编码 `wait_for_receipts: false`，连续多批无 receipt 背压会把 xjst-node RPC 打到无响应。

HTTP 发交易的 superagent timeout 曾误用 `TX_RETRY_DELAY_MS`（默认 3000ms）。失败只打印 `Batch request error: Timeout of 3000ms exceeded`。

发送模型：一轮内遍历全部 wallet，每个账户发 **1 笔**。xjst 实际发送账户来自预生成钱包文件（常见 100 个），`wallet_amount` 只影响 HTTP `BATCH_SIZE`。未打包上限必须 **跨 round 累计**，否则一轮只有约 100 笔，N=1000 永远不会按「满 1000 再查 receipt」工作。

`receipt_wait_every`（满 N 等整窗 + 每轮 flush）与「未打包不超过 N」是两套规则，已删除。

## 目标

- `wait_for_receipts=true` 时：**未打包（已成功发出、尚无 receipt）条数 ≤ N 才允许继续发送**
- 未打包达到 N 后查 receipt：已打包 X 笔则还可再发 `N - (N-X)` = `N - 未打包`。例：发出 1000 且全在 in-flight，已打包 600 → 再发 400；再查若未打包还剩 X → 再发 `N-X`
- N 是全 job 累计 in-flight hash 数，**不是**每个钱包 N 笔
- 全部 round 发完后，等到剩余 in-flight **全部有 receipt** 再退出（超时打 unconfirmed 日志后仍结束，避免死锁）
- `wait_for_receipts=false`：仍 skip receipt wait 与上限
- **默认 N=1000**；N 可配置，不绑死 `wallet_amount`
- **所有链类型（含 xjst）默认 `wait_for_receipts=true`**
- N 与开关只通过 `gen-cross-tx-config` CLI 写入 job，**不提供环境变量覆盖**
- `Batch request error` 打印结构化详情
- HTTP timeout 使用独立常量（默认 30000ms），不再复用 `TX_RETRY_DELAY_MS`

## 非目标

- 不改 xjst 预生成 100 wallet 的逻辑
- 不改为按钱包 in-flight 上限
- 不把 N 绑死到 `wallet_amount`（HTTP batch 仍可用 `TX_BATCH_SIZE`）
- 不改写已生成的 `output/jobs/*.json`（重新跑 `gen-cross-tx-config` 后才会覆盖）

## 等待策略

`7r_multisend.js` 在外层 round 循环持有 `inflightHashes`，跨 round 不清空。

1. 每个 HTTP batch 发送前：若 in-flight ≥ N，对当前 in-flight **全部 hash** 做一次 receipt 轮询（不是等到全部确认才返回）。已打包的从 in-flight 去掉。若仍 ≥ N，sleep 后再查，直到 `inflight.length < N`
2. 本批发送条数 = `min(BATCH_SIZE, 队列剩余, N - inflight.length)`
3. 成功 hash 追加到 in-flight
4. 全部 round 结束后，轮询直到 in-flight 空（或 5 分钟超时）
5. 日志：`inflight=<k> packed=+<p> cap=<N> send=<q>`

receipt 轮询必须返回本次已打包 hash（不能把 confirmed 从 pending 删掉后丢弃）。xjst 仍用 `cfx_getTransactionReceipt` + `cfx_epochNumber`。

旧 job 字段 `receipt_wait_every` 忽略。缺 `max_unconfirmed` 或非法时默认 1000。

## 配置

### Job 字段

| 字段 | 类型 | 默认 | 含义 |
|------|------|------|------|
| `wait_for_receipts` | bool | `true`（所有源链类型） | 是否启用未打包上限与 receipt 轮询 |
| `max_unconfirmed` | int | `1000` | 未打包上限 N，必须 > 0 |

### `gen-cross-tx-config` CLI

- `--wait-for-receipts` 默认 `true`
- `--max-unconfirmed` 默认 `1000`（必须 > 0）

`7r_multisend.js` 只读 job 字段。不读取、不注入 `TX_WAIT_FOR_RECEIPTS` / `TX_RECEIPT_WAIT_EVERY` / `TX_MAX_UNCONFIRMED`。

HTTP 发交易 timeout 为代码常量 `30000` ms，与既有 `TX_RETRY_DELAY_MS`（仅失败后 sleep）分离。既有 `TX_BATCH_SIZE` 行为不变。

## 错误详情

`Batch request error` 必须包含：job index、rpc url、sourceType、batchSize、walletIndex 范围、attempts、配置的 HTTP timeout、`error.code` / `error.errno` / `error.timeout` / `error.status`、response 摘要、`error.stack`，并用 `util.inspect` 打印 error 对象。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go` | Job.`max_unconfirmed`；`WaitForReceipts` 默认 true；GenerateParams 传入开关与 N |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig_test.go` | xjst 也为 true；N 默认 1000；N 随参数变化 |
| `ydyl-deploy-client/cmd/gen_cross_tx_config.go` | `--wait-for-receipts` / `--max-unconfirmed` |
| `zk-claim-service/scripts/7r_multisend.js` | 跨 round in-flight、满 N 才 poll、按额度发送、结束等清零、错误详情、RPC timeout 常量 |
| `zk-claim-service/scripts/lib/benchSendPolicy.js` | job 字段解析、sendQuota、removePacked、receipt batch 解析已打包 hash |

## 用法

```bash
cd ydyl-deploy-client
go run . gen-cross-tx-config --servers ./output/servers.json --config ./config.deploy.yaml
# 可选：--wait-for-receipts=false  --max-unconfirmed 500
go run . bench-cross-tx
```
