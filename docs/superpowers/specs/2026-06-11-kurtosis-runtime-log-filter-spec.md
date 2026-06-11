# Kurtosis 运行期日志白名单与 DEBUG/TRACE 过滤

## 背景

[`2026-06-10-deploy-client-log-collection-spec`](2026-06-10-deploy-client-log-collection-spec.md) 通过 [`ydyl-scripts-lib/log_monitor_runtime.sh`](../../../ydyl-scripts-lib/log_monitor_runtime.sh) 在 CDK/OP 部署期间跟 Kurtosis 运行日志，当前策略为：

- **服务过滤**：黑名单排除 `grafana` / `prometheus` / `blockscout`，其余 User Service 全量跟
- **级别过滤**：无
- **栈识别**：仅靠 `--enclave`（`cdk-gen` / `op-gen`），脚本内不区分 CDK/OP 规则

实际运行中观测/基础设施组件（`postgres`、`panoptichain`、`contracts` 等）与大量 DEBUG/TRACE 日志占满 `{name}-runtime.log`，不利于批量部署后的排障与 `collect-logs` 归档。

## 目标

1. CDK / OP Kurtosis **运行期**日志改为**白名单服务**跟踪，去掉非主线噪声
2. 对白名单服务日志做 **DEBUG + TRACE**（及 erigon 等等价级别）行过滤
3. 通过 `--stack cdk|op` 显式区分栈类型，由 `ydyl-deploy-client` 透传
4. 看门狗基于**过滤前**原始流活动计时，避免链空闲时仅剩 DEBUG 输出导致误重连

## 非目标

- 不修改 `deploy-gen.log`（Kurtosis 部署阶段日志）
- 不修改 XJST `docker` 模式行为
- 不修改 Kurtosis 包内 `global_log_level` / `verbosity`（源头降噪可后续单独迭代）
- 实现时同步修订 [`2026-06-10-deploy-client-log-collection-spec`](2026-06-10-deploy-client-log-collection-spec.md) §3.1，保持日志收集上游 spec 一致

## CDK / OP Kurtosis User Service 参考

### CDK（`deployment_suffix: '-1'`，见 `cdk-work/scripts/params.template.yml`）

典型 enclave inspect 输出（示例）：

| 服务名 | 保留 | 说明 |
|--------|------|------|
| `cdk-node-1` | 是 | 聚合器 / L1 同步 |
| `cdk-erigon-rpc-1` | 是 | L2 RPC |
| `cdk-erigon-sequencer-1` | 是 | L2 排序 |
| `zkevm-pool-manager-1` | 是 | 交易池 |
| `zkevm-prover-1` | 条件 | 仅 `USE_REAL_PROVER=false` 时部署（见 [`2026-06-11-cdk-use-real-prover-env-spec`](2026-06-11-cdk-use-real-prover-env-spec.md)）；白名单包含，但**不强制等待** |
| `status-checker-1` | 是 | 健康检查 |
| `zkevm-bridge-service-1` | 是 | 桥服务 |
| `contracts-1` | 否 | 部署后常驻，运行期排障价值低 |
| `postgres-1` | 否 | 数据库 |
| `panoptichain-1` | 否 | 观测 |
| `grafana-1` / `prometheus-1` | 否 | 观测 |

### OP（`network_params.name: op-kurtosis`，见 `op-work/scripts/params.template.yml`）

| 服务名 | 保留 | 组件 |
|--------|------|------|
| `op-cl-1-op-node-op-geth-op-kurtosis` | 是 | op-node |
| `op-el-1-op-geth-op-node-op-kurtosis` | 是 | op-geth |
| `op-batcher-op-kurtosis` | 是 | op-batcher |
| `op-proposer-op-kurtosis` | 是 | op-proposer |
| `op-challenger-op-kurtosis` | 是 | op-challenger |
| `grafana` / `prometheus` | 否 | 观测（`observability.enabled: true`） |
| `op-blockscoutop-kurtosis` | 否 | 当前 `additional_services` 未启用；若未来启用亦排除 |

## 详细设计

### 1. CLI 入参

`log_monitor_runtime.sh` kurtosis 模式新增必填参数：

```bash
log_monitor_runtime.sh --mode kurtosis \
  --stack cdk|op \
  --enclave cdk-gen|op-gen \
  --output /home/ubuntu/ydyl-deploy-logs/{name}-runtime.log
```

`ydyl-deploy-client` [`buildRuntimeMonitorCommand`](../../../ydyl-deploy-client/internal/deploy/exec_helpers.go) 按 `ServiceTypeCDK` / `ServiceTypeOP` 透传 `--stack cdk` 或 `--stack op`。

### 2. 服务白名单

替换现有 `KURTOSIS_EXCLUDE_SERVICES_REGEX` 黑名单，改为按 `--stack` 选择**包含**正则（用于 `kurtosis enclave inspect` 解析与日志行 `[服务名]` 前缀匹配）。

**CDK**（前缀匹配，兼容 `-1` / `-001` 等后缀）：

```bash
KURTOSIS_CDK_SERVICES_REGEX='^(cdk-node-|cdk-erigon-rpc-|cdk-erigon-sequencer-|zkevm-pool-manager-|zkevm-prover-|status-checker-|zkevm-bridge-service-)'
```

**OP**（`count: 1` 时 participant 序号为 `1`）：

```bash
KURTOSIS_OP_SERVICES_REGEX='^(op-cl-[0-9]+-op-node-op-geth-op-kurtosis|op-el-[0-9]+-op-geth-op-node-op-kurtosis|op-batcher-op-kurtosis|op-proposer-op-kurtosis|op-challenger-op-kurtosis)$'
```

**就绪检测**：`list_kurtosis_services()` 返回白名单内至少一个服务即视为可开始跟踪；`zkevm-prover-*` 缺席不阻塞。

**日志流**：`stream_kurtosis_logs()` 仅写入行首 `[服务名]` 命中白名单的日志行（`grep --line-buffered -Ei`）。

### 3. DEBUG / TRACE 行过滤

在通过服务白名单后，再排除以下模式（大小写不敏感，`grep -Eiv`）：

| 栈 / 组件 | 排除模式 | 示例 |
|-----------|---------|------|
| OP 全系 | `lvl=debug`、`lvl=trace` | `lvl=debug msg="[Sequencer] received BuildStartedEvent"` |
| CDK zap（cdk-node 等） | `\tDEBUG\t`、`\tTRACE\t` | `2026-06-11T03:54:01.260Z\tDEBUG\treorgdetector/...` |
| CDK erigon（cdk-erigon-*） | `[dbg]`、`[trace]`、`lvl=debug`、`lvl=trace` | erigon 多格式保守覆盖 |

组合为一个排除正则或串联两次 `grep -Eiv`，须保持 `--line-buffered`。

**注意**：仅排除**行级**日志级别标记，不按消息体子串宽泛匹配，降低误杀 INFO/WARN/ERROR 的风险。

### 4. 看门狗与断流恢复

保留现有机制（`LOG_STALL_TIMEOUT` 默认 120s、重连 kurtosis 用 `-n 0`），并修正一点：

- **活动检测**：基于 kurtosis **原始输出流**（过滤前）更新 `LAST_ACTIVITY_EPOCH`，避免"仅有 DEBUG 被滤掉 → 输出文件不增长 → 误重连"
- **落盘内容**：仍为过滤后的日志
- **行缓冲**：过滤管道继续使用 `grep --line-buffered` / `sed -u`

实现建议：过滤前用 `tee` 写活动标记（如 FIFO / 辅助文件 touch）或在子 shell 中对原始流计数；具体实现细节留给 plan，行为以本 spec 为准。

### 5. 数据流

```
kurtosis service logs -f [-a|-n 0] {enclave}
  → [活动检测：原始流]
  → grep 白名单服务行
  → grep -v DEBUG/TRACE
  → {name}-runtime.log
```

## 涉及文件（实现阶段）

| 文件 | 改动 |
|------|------|
| `ydyl-scripts-lib/log_monitor_runtime.sh` | `--stack`、白名单、级别过滤、看门狗原始流活动 |
| `ydyl-deploy-client/internal/deploy/exec_helpers.go` | 透传 `--stack cdk\|op` |
| `docs/superpowers/specs/2026-06-10-deploy-client-log-collection-spec.md` | 修订 §3.1 与本文一致 |

## 验收标准

1. CDK runtime 日志包含：`cdk-node`、`cdk-erigon-rpc`、`cdk-erigon-sequencer`、`zkevm-pool-manager`、`status-checker`、`zkevm-bridge-service` 的 INFO/WARN/ERROR
2. CDK runtime 日志**不包含**：`contracts`、`postgres`、`panoptichain`、`grafana`、`prometheus` 等行
3. CDK runtime 日志**不包含** zap `\tDEBUG\t`/`\tTRACE\t` 及 erigon 等价级别行
4. OP 五条主线服务（op-node / op-geth / op-batcher / op-proposer / op-challenger）的 info/warn/error 均保留
5. OP runtime 日志**不包含** `lvl=debug` / `lvl=trace` 行
6. `USE_REAL_PROVER=false` 时 `zkevm-prover-*` 日志纳入；`USE_REAL_PROVER=true`（默认）时脚本不因缺少 prover 失败
7. 链空闲仅产 DEBUG/TRACE 时，120s 内不误触发重连
8. XJST docker 模式行为与改前一致
9. `deploy-gen.log` 不受本 spec 影响

## 关联 spec

- 上游：[`2026-06-10-deploy-client-log-collection-spec`](2026-06-10-deploy-client-log-collection-spec.md)
- 相关：[`2026-06-11-cdk-use-real-prover-env-spec`](2026-06-11-cdk-use-real-prover-env-spec.md)（`zkevm-prover` 条件部署）
