# bench-cross-tx `tps` 汇总写入 TOTALTPS.json

`go run . tps` 启动的监控在 `ydyl-deploy-client/output/jobs/TOTALTPS.json` 给出一份可读快照：压测启动时间、当前时间、经历时长、链数量、每条链用户数、L1/L2/TOTAL TPS。

## 背景

`tps` compose service 跑 `h_TPSjob.js` → `totalTPS()`，每约 10s 覆盖写 `TOTALTPS.json`。旧内容只有 `L1TOTALTPS` / `L2TOTALTPS` / `TOTALTPS` / `timestamp`，不够一次读完压测口径。

发送侧 `7r_multisend.js` 开始发交易时把 unix `start_timestamp` 写入 `{hash}-l1.json`。链与 `wallet_amount` 已在 `all.json` jobs 里。

## 目标

- 继续由 `totalTPS()` 覆盖写同一文件 `output/jobs/TOTALTPS.json`（compose 已 bind-mount 该目录）
- 时钟时间（启动、当前）用 ISO 8601（`Date#toISOString()`）
- 压测启动时间 = 各发送 job `{hash}-l1.json` 的 `start_timestamp` 最早值，再转 ISO
- 链数量 / 每链用户数从 `all.json` jobs 按不重复 `source_l2_rpc` 统计
- 保留现有 `L1TOTALTPS` / `L2TOTALTPS` / `TOTALTPS` / `timestamp`

## 非目标

- 不另开汇总文件、不追加历史（JSONL/CSV）
- 不改编排：Go `tps` 仍只 `docker compose up --build tps`
- 不改 `L1TOTALTPS.json` 格式
- 不改 `7r_multisend.js` 的 unix `start_timestamp` 写入
- 不把 xjst 预生成钱包长度当作用户数（用户数 = job `wallet_amount`）

## TOTALTPS.json

每次轮询覆盖最新快照。

| 需求 | 字段 | 格式 |
|------|------|------|
| 压测启动时间 | `bench_start_time` | ISO，如 `2026-09-10T03:00:00.000Z`；尚无任何 `-l1.json` 的有限 `start_timestamp` 则为 `null` |
| 当前时间 | `current_time` | ISO；与 `timestamp` 同值 |
| 经历时长 | `elapsed_seconds` | 非负整数；`floor(now/1000) - min(start_timestamp)`；无启动时间则为 `null` |
| 链数量 | `chain_count` | jobs 中不重复 `source_l2_rpc` 个数（跳过空 rpc） |
| 每条链用户数 | `users_per_chain` + `chains` | 各链 `wallet_amount` 相同则为该数字，否则 `null`；`chains[]` 含 `source_l2_rpc`、`source_l2_chain_type`、`wallet_amount` |
| L1 TPS | `L1TOTALTPS` | 既有：读 `L1TOTALTPS.json` 的 `TOTALTPS`；缺失或非法则为 `0` |
| L2 TPS | `L2TOTALTPS` | 既有：各 job L2 TPS 之和 |
| TOTAL TPS | `TOTALTPS` | `L1TOTALTPS + L2TOTALTPS` |
| 当前时间（兼容） | `timestamp` | 与 `current_time` 同值 |

同一 `source_l2_rpc` 出现多次只计一条链，保留首次出现的 `source_l2_chain_type` 与 `wallet_amount`。部分 job 已开始发送时，启动时间仍取已出现的最早 `start_timestamp`。缺 `source_l2_rpc` 的 job 不计入链统计。

## 数据流

1. `h_TPSjob.js` 加载 `all.json`，把**原始 jobs**（不含占位空对象）传给 `totalTPS(..., { jobs })`
2. `totalTPS()` 按既有逻辑汇总 L1/L2 TPS；同时读各 `{hash}-l1.json` 收集有限的 `start_timestamp`
3. 调用 `buildTotalTpsSummary` 写出 `TOTALTPS.json`

## 涉及文件

| 文件 | 改动 |
|------|------|
| `zk-claim-service/scripts/lib/tpsSummary.js` | `buildChainStats`、`buildTotalTpsSummary` |
| `zk-claim-service/scripts/lib/tpsSummary.test.js` | ISO、去重、users_per_chain、无/部分启动时间、L1+L2 |
| `zk-claim-service/scripts/h_L2TPSCalulation.js` | `totalTPS` 读 `-l1.json` 并写扩展字段 |
| `zk-claim-service/scripts/h_TPSjob.js` | 传入原始 `jobs` |
| `ydyl-deploy-client/README.md` | `tps` 说明指向 `TOTALTPS.json` |

## 用法

```bash
cd ydyl-deploy-client
go run . tps --config ./7s_jobs.gen.json
# 读 output/jobs/TOTALTPS.json
```
