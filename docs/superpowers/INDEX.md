# Superpowers 文档索引

记录项目内所有 spec 与 plan 的对应关系，便于追溯改动来源。

约定参见 `CLAUDE.md` "Superpowers 工作流约定"：
- 改动涉及需求/设计 → 先改 spec，再改产物
- 改动是纯实施细节 → 改产物，但完成后扫一遍 spec 确认仍一致
- spec 与产物不一致 → 视为 bug，必须修复

---

## Specs

| 日期 | Spec | 对应报告章节 | 写作产物 | 负责人 |
|------|------|-------------|---------|--------|
| 2026-05-06 | [Rollup 侧链接入方案](specs/2026-05-06-rollup-sidechain-integration-spec.md) | 4.2 | `doc-report/4.2-rollup-sidechain-integration.md` | 大勇 |
| 2026-05-07 | [多类型侧链规模化部署](specs/2026-05-07-multi-sidechain-bulk-deployment-spec.md) | 4.4 | `doc-report/4.4-multi-sidechain-bulk-deployment.md`（待写） | 大勇 |
| 2026-06-10 | [deploy-client 日志收集与统计](specs/2026-06-10-deploy-client-log-collection-spec.md) | 4.4 扩展 | — | 大勇 |
| 2026-06-11 | [CDK `USE_REAL_PROVER` 环境变量](specs/2026-06-11-cdk-use-real-prover-env-spec.md) | — | `cdk-work/scripts/params.template.yml`、`cdk_pipe.sh`、`ydyl-deploy-client/internal/deploy/*` | 大勇 |
| 2026-06-11 | [Kurtosis 运行期日志白名单与 DEBUG/TRACE 过滤](specs/2026-06-11-kurtosis-runtime-log-filter-spec.md) | 4.4 扩展 | `ydyl-scripts-lib/log_monitor_runtime.sh`、`ydyl-deploy-client` | 大勇 |
| 2026-06-12 | [OP `FAULT_GAME_MAX_CLOCK_DURATION` 环境变量](specs/2026-06-12-op-fault-game-max-clock-duration-spec.md) | — | `op-work/scripts/params.template.yml`、`optimism-package`、`op_pipe.sh` | 大勇 |
| 2026-08-28 | [流水线 step2 L1 余额差额补足](specs/2026-08-28-l1-fund-top-up-spec.md) | — | `ydyl-scripts-lib/utils.sh`、`ydyl-scripts-lib/pipeline_steps_lib.sh` | 大勇 |
| 2026-08-30 | [XJST ENABLE_BRIDGE + step2 L1 金额可配置](specs/2026-08-30-xjst-enable-bridge-spec.md) | — | `xjst_pipe.sh`、`ydyl-scripts-lib/*`、`ydyl-deploy-client/internal/deploy/*` | 大勇 |
| 2026-08-31 | [Deploy 前预检（check）](specs/2026-08-31-deploy-precheck-spec.md) | — | `ydyl-deploy-client/internal/precheck`、`ydyl-deploy-client/cmd/check.go`、`ydyl-deploy-client/cmd/deploy.go` | 大勇 |
| 2026-09-03 | [`ydyl-gen-accounts` 支持 Conflux Core Space](specs/2026-09-03-gen-accounts-core-space-support-spec.md) | — | `ydyl-gen-accounts/scripts/2_genAccsByContract.ts`、`ydyl-gen-accounts/scripts/2_genAccsByEoa.ts` 及必要共享模块 | 大勇 |
| 2026-09-07 | [deploy-client 远端 gen-accounts 命令](specs/2026-09-07-deploy-client-gen-accounts-remote-commands-spec.md) | — | `ydyl-deploy-client/cmd/gen_accounts.go`、`ydyl-deploy-client/internal/genaccounts` | 大勇 |
| 2026-09-07 | [gen-cross-tx-config target 不可重复](specs/2026-09-07-gen-cross-tx-config-unique-targets-spec.md) | — | `ydyl-deploy-client/internal/crosstxconfig`、`ydyl-deploy-client/cmd/gen_cross_tx_config.go` | 大勇 |
| 2026-09-08 | [gen-cross-tx-config 分池目标与 wallet_amount 默认值](specs/2026-09-08-gen-cross-tx-config-typed-targets-spec.md) | — | `ydyl-deploy-client/internal/crosstxconfig`、`ydyl-deploy-client/cmd/gen_cross_tx_config.go` | 大勇 |
| 2026-09-08 | [bench-cross-tx 未打包上限 max_unconfirmed](specs/2026-09-08-bench-cross-tx-receipt-wait-spec.md) | — | `ydyl-deploy-client/internal/crosstxconfig`、`ydyl-deploy-client/cmd/gen_cross_tx_config.go`、`zk-claim-service/scripts/7r_multisend.js`、`zk-claim-service/scripts/lib/benchSendPolicy.js` | 大勇 |
| 2026-09-08 | [deploy-client sample-wallets 抽查确定性账户余额](specs/2026-09-08-deploy-client-sample-wallets-spec.md) | — | `ydyl-deploy-client/cmd/sample_wallets.go`、`ydyl-deploy-client/internal/samplewallets`、`ydyl-deploy-client/internal/utils/cryptoutil` | 大勇 |
| 2026-09-09 | [deploy-client gen-private-key 支持 Core Space CIP-37](specs/2026-09-09-deploy-client-gen-private-key-l2type3-spec.md) | — | `ydyl-deploy-client/cmd/gen_private_key.go`、`ydyl-deploy-client/internal/utils/cryptoutil` | 大勇 |
| 2026-09-09 | [gen:contract DEBUG 打印余额与 CIP-37](specs/2026-09-09-gen-accounts-debug-balance-base32-spec.md) | — | `ydyl-gen-accounts/scripts/2_genAccsByContract.ts`、`ydyl-gen-accounts/scripts/coreSpaceAddress.ts` | 大勇 |
| 2026-09-09 | [deploy-client monitor-gen-accounts 按链类型汇总](specs/2026-09-09-deploy-client-monitor-gen-accounts-by-type-spec.md) | 4.1.32 | `ydyl-deploy-client/internal/genaccmonitor`、`ydyl-deploy-client/cmd/monitor_gen_accounts.go` | 大勇 |
| 2026-09-10 | [deploy-client sample-wallets 可选 --rpc-url](specs/2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md) | — | `ydyl-deploy-client/cmd/sample_wallets.go`、`ydyl-deploy-client/internal/samplewallets` | 大勇 |
| 2026-09-10 | [deploy-client sample-wallets 支持 l2type=3 CIP-37](specs/2026-09-10-deploy-client-sample-wallets-l2type3-spec.md) | — | `ydyl-deploy-client/cmd/sample_wallets.go`、`ydyl-deploy-client/internal/samplewallets` | 大勇 |
| 2026-09-10 | [bench-cross-tx tps 汇总写入 TOTALTPS.json](specs/2026-09-10-bench-cross-tx-tps-summary-spec.md) | — | `zk-claim-service/scripts/lib/tpsSummary.js`、`zk-claim-service/scripts/h_L2TPSCalulation.js`、`zk-claim-service/scripts/h_TPSjob.js`、`ydyl-deploy-client/README.md` | 大勇 |
| 2026-09-10 | [gen:contract `--retryUntilSuccess`](specs/2026-09-10-gen-accounts-retry-until-success-spec.md) | — | `ydyl-gen-accounts/scripts/byContractSend.ts`、`ydyl-gen-accounts/scripts/2_genAccsByContract.ts`、`ydyl-gen-accounts/scripts/3_concurrency.ts`、`cdk_pipe.sh` | 大勇 |
| 2026-09-10 | [TPS getLogs too-many-logs 递归折半](specs/2026-09-10-tps-getlogs-too-many-logs-spec.md) | — | `zk-claim-service/scripts/lib/getLogsPaginated.js`、`zk-claim-service/scripts/h_L2TPSCalulation.js`、`zk-claim-service/scripts/i_L1TPSCalulation.js` | 大勇 |

## Plans

| 日期 | Plan | 对应 Spec | 状态 |
|------|------|-----------|------|
| 2026-06-11 | [Kurtosis runtime 日志过滤实现计划](plans/2026-06-11-kurtosis-runtime-log-filter-plan.md) | [Kurtosis 运行期日志白名单与 DEBUG/TRACE 过滤](specs/2026-06-11-kurtosis-runtime-log-filter-spec.md) | 已完成 |
| 2026-09-04 | [`ydyl-gen-accounts` Core Space 支持实施计划](plans/2026-09-04-gen-accounts-core-space-support-plan.md) | [`ydyl-gen-accounts` 支持 Conflux Core Space](specs/2026-09-03-gen-accounts-core-space-support-spec.md) | 已完成 |
| 2026-09-04 | [`ydyl-gen-accounts` Core BatchSender 单合约部署实施计划](plans/2026-09-04-gen-accounts-core-space-batch-sender-deploy-plan.md) | [`ydyl-gen-accounts` 支持 Conflux Core Space](specs/2026-09-03-gen-accounts-core-space-support-spec.md) | 已完成 |
| 2026-09-08 | [sample-wallets 抽查确定性账户余额实施计划](plans/2026-09-08-deploy-client-sample-wallets-plan.md) | [deploy-client sample-wallets 抽查确定性账户余额](specs/2026-09-08-deploy-client-sample-wallets-spec.md) | 已完成 |
| 2026-09-09 | [gen-private-key l2type=3 CIP-37 实施计划](plans/2026-09-09-deploy-client-gen-private-key-l2type3-plan.md) | [deploy-client gen-private-key 支持 Core Space CIP-37](specs/2026-09-09-deploy-client-gen-private-key-l2type3-spec.md) | 已完成 |
| 2026-09-09 | [gen:contract DEBUG 打印 balance 与 CIP-37 实施计划](plans/2026-09-09-gen-accounts-debug-balance-base32-plan.md) | [gen:contract DEBUG 打印余额与 CIP-37](specs/2026-09-09-gen-accounts-debug-balance-base32-spec.md) | 已完成 |
| 2026-09-10 | [sample-wallets 可选 --rpc-url 实施计划](plans/2026-09-10-deploy-client-sample-wallets-rpc-url-plan.md) | [deploy-client sample-wallets 可选 --rpc-url](specs/2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md) | 已完成 |
| 2026-09-10 | [sample-wallets 支持 l2type=3 实施计划](plans/2026-09-10-deploy-client-sample-wallets-l2type3-plan.md) | [deploy-client sample-wallets 支持 l2type=3 CIP-37](specs/2026-09-10-deploy-client-sample-wallets-l2type3-spec.md) | 已完成 |
| 2026-09-10 | [tps 汇总写入 TOTALTPS.json 实施计划](plans/2026-09-10-bench-cross-tx-tps-summary-plan.md) | [bench-cross-tx tps 汇总写入 TOTALTPS.json](specs/2026-09-10-bench-cross-tx-tps-summary-spec.md) | 已完成 |
| 2026-09-10 | [gen:contract `--retryUntilSuccess` 实施计划](plans/2026-09-10-gen-accounts-retry-until-success-plan.md) | [gen:contract `--retryUntilSuccess`](specs/2026-09-10-gen-accounts-retry-until-success-spec.md) | 已完成 |

---

## Spec 间依赖

- 4.4 spec 上游依赖 4.2 spec：jsonrpc-proxy 的 block hash 修正、CDK 内核侧改造、L1 origin drift 等论点在 4.2 论证后被 4.4 引用，不重述
- 2026-06-10 日志 spec 扩展 4.4 的 `ydyl-deploy-client` 编排：新增 `collect-logs` / `stats-logs`；后续扩展远端 bench client 日志（`benchClientIP`、仅收最新 `bench-cross-tx-*.log`），详见该 spec §2 / §5.1
- 2026-06-11 `USE_REAL_PROVER` spec 依赖 2026-05-14 kurtosis-cdk 真实 prover 能力；在 `cdk-work` 层用环境变量统一注入
- 2026-06-11 Kurtosis 日志过滤 spec 扩展 2026-06-10 日志 spec §3.1：CDK/OP runtime 白名单 + DEBUG/TRACE 过滤
- 2026-06-12 `FAULT_GAME_MAX_CLOCK_DURATION` spec 依赖 2026-05-06 rollup spec 的 dispute 秒级压缩背景；模式对齐 2026-06-11 CDK `USE_REAL_PROVER` spec（envsubst + 流水线持久化）；实现需同步改 `optimism-package` 并更新 `OP_PACKAGE_LOCATOR` commit
- 2026-09-07 远端 gen-accounts 命令复用 2026-05-07 / `gen-cross-tx-config` 的 XJST node-1 选机规则（`PickChainEntries`），不改变流水线 step9
- 2026-09-07 `gen-cross-tx-config` unique-targets 只改 `GenerateJobs` 的目标分配，不改 `PickChainEntries`，不影响远端 gen-accounts 选机
- 2026-09-08 typed-targets 覆盖 unique-targets 的配对范围：xjst 只打 xjst，op/cdk 只打 op/cdk；n=1 允许自指；池内 n≥2 仍 derangement；`--wallet-amount` 默认 100，`--tx-amount-per-wallet` 默认 10000
- 2026-09-08 bench receipt-wait 覆盖 unique-targets / typed-targets 中「xjst 源 `WaitForReceipts=false`」：所有源链默认 `wait_for_receipts=true`，未打包上限 `max_unconfirmed`（默认 1000）由 CLI 写入 job 字段；跨 round 累计，满 N 才查 receipt 补发额度
- 2026-09-08 `sample-wallets` 复用 `PickChainEntries`（不改选机规则）与确定性私钥公式；该 feature 范围内不改 `gen-private-key`
- 2026-09-10 `sample-wallets` 可选 `--rpc-url` 覆盖查余额 RPC，不改写用户 URL；空/空白仍走 summary + `ReplaceLocalhostWithIP`；不跳过选链与 console-service
- 2026-09-09 `gen-private-key` 补回命令并支持 `l2type=3` CIP-37；地址编码由 `CoreBase32AddressFromPrivateKey` 提供；不改 `ydyl-gen-accounts` 的 `0x` CLI 约定
- 2026-09-10 `sample-wallets` `l2type=3` 必填 `--rpc-url` 与 `--chainID`，跳过 servers/console-service，地址 CIP-37，余额 `cfx_getBalance`
- 2026-09-09 gen:contract DEBUG 余额/CIP-37 补充 2026-09-03：`0x` CLI/进度约定不变，仅 DEBUG 日志额外打印 verbose CIP-37 与发交易前余额
- 2026-09-09 `monitor-gen-accounts` 按链类型汇总复用 `PickChainEntries`（先丢掉 `generic` 再选机）；不改 2026-09-07 `gen-accounts start/stop/resume`；XJST 一条链只计组内 node-1
- 2026-09-10 `tps` 汇总扩展既有 `TOTALTPS.json`（覆盖快照）：ISO 启动/当前时间、经历时长、链数量与每链 `wallet_amount`；启动时间取 `{hash}-l1.json` 最早 unix `start_timestamp`；不改编排、不改 `L1TOTALTPS.json`
- 2026-09-10 gen:contract `--retryUntilSuccess` 默认不改变 2026-09-03 的失败/窗口/进度语义；CLI 默认关闭；`cdk_pipe.sh` 默认 `RETRY_UNTIL_SUCCESS=true`；回执重试按下标钉死最后一笔；提交遇 nonce 占用/`already known` 不得钉死原 nonce；不改 by-eoa / op_pipe / xjst_pipe / 远端 `gen-accounts start`
- 2026-09-10 TPS getLogs 折半不改 `--block-range` 默认 300；lookback 与 getLogs 切分分离；`eth_getLogs` 与 xjst `cfx_getLogs` 同一套递归折半；eSpace 无建议区间的 too-many-logs 也要拆；不改 `g_L2eventmonitor.js`
