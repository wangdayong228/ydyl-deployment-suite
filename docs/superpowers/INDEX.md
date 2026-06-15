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
| 2026-06-11 | [CDK `USE_REAL_PROVER` 环境变量](specs/2026-06-11-cdk-use-real-prover-env-spec.md) | — | `cdk-work/scripts/params.template.yml`、`cdk_pipe.sh` | 大勇 |
| 2026-06-11 | [Kurtosis 运行期日志白名单与 DEBUG/TRACE 过滤](specs/2026-06-11-kurtosis-runtime-log-filter-spec.md) | 4.4 扩展 | `ydyl-scripts-lib/log_monitor_runtime.sh`、`ydyl-deploy-client` | 大勇 |
| 2026-06-12 | [OP `FAULT_GAME_MAX_CLOCK_DURATION` 环境变量](specs/2026-06-12-op-fault-game-max-clock-duration-spec.md) | — | `op-work/scripts/params.template.yml`、`optimism-package`、`op_pipe.sh` | 大勇 |

## Plans

| 日期 | Plan | 对应 Spec | 状态 |
|------|------|-----------|------|
| 2026-06-11 | [Kurtosis runtime 日志过滤实现计划](plans/2026-06-11-kurtosis-runtime-log-filter-plan.md) | [Kurtosis 运行期日志白名单与 DEBUG/TRACE 过滤](specs/2026-06-11-kurtosis-runtime-log-filter-spec.md) | 已完成 |

---

## Spec 间依赖

- 4.4 spec 上游依赖 4.2 spec：jsonrpc-proxy 的 block hash 修正、CDK 内核侧改造、L1 origin drift 等论点在 4.2 论证后被 4.4 引用，不重述
- 2026-06-10 日志 spec 扩展 4.4 的 `ydyl-deploy-client` 编排：新增 `collect-logs` / `stats-logs`；后续扩展远端 bench client 日志（`benchClientIP`、仅收最新 `bench-cross-tx-*.log`），详见该 spec §2 / §5.1
- 2026-06-11 `USE_REAL_PROVER` spec 依赖 2026-05-14 kurtosis-cdk 真实 prover 能力；在 `cdk-work` 层用环境变量统一注入
- 2026-06-11 Kurtosis 日志过滤 spec 扩展 2026-06-10 日志 spec §3.1：CDK/OP runtime 白名单 + DEBUG/TRACE 过滤
- 2026-06-12 `FAULT_GAME_MAX_CLOCK_DURATION` spec 依赖 2026-05-06 rollup spec 的 dispute 秒级压缩背景；模式对齐 2026-06-11 CDK `USE_REAL_PROVER` spec（envsubst + 流水线持久化）；实现需同步改 `optimism-package` 并更新 `OP_PACKAGE_LOCATOR` commit
