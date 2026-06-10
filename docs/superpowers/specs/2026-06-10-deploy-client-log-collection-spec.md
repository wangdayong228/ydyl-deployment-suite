# ydyl-deploy-client 日志收集与统计

## 1. 目标

为批量部署场景提供统一的日志落盘、远端运行期监控、压缩收集与 CSV 统计能力，覆盖 **deploy / bench** 客户端日志，以及 CDK / OP / XJST 服务端部署与运行日志。

## 2. 日志源

远端仓库根目录：`/home/ubuntu/workspace/ydyl-deployment-suite`（与 `ydyl-deploy-client` 远程命令 `cd` 一致）。

| 类别 | 路径 | 说明 |
|------|------|------|
| 客户端 deploy | `logs/client/deploy-{ts}.log` | deploy 命令 stdout+stderr 自动 tee |
| 客户端 bench | `logs/client/bench-cross-tx-{ts}.log` | bench-cross-tx 命令 stdout+stderr 自动 tee |
| 服务端 pipe 部署 | 远端 `/home/ubuntu/ydyl-deploy-logs/{name}.log`；本地 `logs/{name}-{ip}.log` | 已有 Sync 增量同步 |
| 服务端 Kurtosis 部署（CDK） | 远端 `/home/ubuntu/workspace/ydyl-deployment-suite/cdk-work/scripts/deploy-gen.log` | `kurtosis run` 重定向；默认 `NETWORK=gen` |
| 服务端 Kurtosis 部署（OP） | 远端 `/home/ubuntu/workspace/ydyl-deployment-suite/op-work/scripts/deploy-gen.log` | 同上 |
| 服务端 CDK/OP 运行 | 远端 `/home/ubuntu/ydyl-deploy-logs/{name}-runtime.log` | enclave 就绪后 follow **主要服务**日志（排除 grafana / prometheus / blockscout，见 §3.1） |
| 服务端 XJST 运行 | 远端 `/home/ubuntu/ydyl-deploy-logs/{name}-runtime.log` | 仅 node-1 机器，`docker logs -f testchain_node1` |

默认 enclave：`cdk-gen` / `op-gen`（与 `cdk_pipe.sh` / `op_pipe.sh` 一致）。

## 3. 远端运行监控

主 pipeline（`*_pipe.sh`）启动后，**立即**通过 SSH 下发 `ydyl-scripts-lib/log_monitor_runtime.sh` 后台任务（与主部署并行，失败不阻断主部署）：

- **CDK/OP**：每台机器 kurtosis 模式；脚本**内置轮询等待 enclave 创建**（`kurtosis enclave ls` 检测到目标 enclave 后，按 §3.1 规则 follow 主要服务日志并写入 runtime 文件）
- **XJST**：仅 `node-1` 角色机器（全局 index `i%4==0`）docker 模式；脚本**内置等待容器** `testchain_node1` 存在后再 `docker logs -f`
- 输出文件：§2 中的 `{name}-runtime.log`

### 3.1 Kurtosis 运行日志服务过滤

**不使用** `kurtosis service logs -a`（会纳入 grafana / prometheus / blockscout 等观测与索引组件，日志量大且与链本体排障无关）。

`log_monitor_runtime.sh` 在 enclave 就绪后：

1. 解析 `kurtosis enclave inspect {enclave}` 的 **User Services** 名称列表
2. **排除**名称（大小写不敏感，前缀或子串匹配）命中以下任一模式的服务：
   - `grafana`（如 `grafana`、`grafana-1`）
   - `prometheus`（如 `prometheus`、`prometheus-1`）
   - `blockscout`（如 `blockscout`、`op-blockscoutop-kurtosis`）
3. 对其余服务执行 `kurtosis service logs -f {enclave} {svc1} {svc2} ...`，合并写入 `{name}-runtime.log`（每行前带 `[{svc}]` 前缀以便区分来源）

典型保留服务示例（以实际 enclave inspect 为准，非硬编码白名单）：

| 栈 | 主要服务（示例） |
|----|-----------------|
| CDK | `cdk-node-*`、`cdk-erigon-*`、`zkevm-*`、`contracts-*` |
| OP | `op-cl-*`、`op-el-*`、`op-batcher-*`、`op-proposer-*`、`op-challenger-*` |

`log_monitor_runtime.sh` 入参约定：

```bash
log_monitor_runtime.sh --mode kurtosis|docker \
  --output /home/ubuntu/ydyl-deploy-logs/{name}-runtime.log \
  --enclave cdk-gen|op-gen \        # kurtosis 模式必填
  --container testchain_node1         # docker 模式必填
```

## 4. 客户端 tee

在以下命令入口对 **stdout + stderr** 做 tee，写入 `logs/client/`（目录不存在则创建）：

| 命令 | 落盘路径 |
|------|---------|
| `deploy` | `logs/client/deploy-{ts}.log` |
| `bench-cross-tx` | `logs/client/bench-cross-tx-{ts}.log` |

`{ts}` 为命令启动时的 UTC 时间戳，格式 `20060102-150405`，与 deploy 归档时间戳风格一致。

## 5. CLI 命令

两命令均复用 deploy 的 `-f/--config` 读取 `logDir`、`outputDir`、SSH 配置；额外支持 `--output-dir` 覆盖 `outputDir`（默认读 config）。

### 5.1 `collect-logs`

从 `output/script_status.json` 读取节点，对每台服务器按 `serviceType` 收集以下文件：

**部署类（deploy）**

| serviceType | 远端文件 |
|-------------|---------|
| cdk / op / xjst | `script_status.logPath`（pipe 日志，`/home/ubuntu/ydyl-deploy-logs/{name}.log`） |
| cdk | `/home/ubuntu/workspace/ydyl-deployment-suite/cdk-work/scripts/deploy-gen.log` |
| op | `/home/ubuntu/workspace/ydyl-deployment-suite/op-work/scripts/deploy-gen.log` |

**运行类（runtime）**

| serviceType | 远端文件 | 备注 |
|-------------|---------|------|
| cdk / op | `/home/ubuntu/ydyl-deploy-logs/{name}-runtime.log` | 文件不存在则跳过并记入 manifest |
| xjst | 同上 | 仅 node-1（`i%4==0`）收集；其余节点跳过 |

每台服务器流程：

1. SSH 对存在的文件执行 `wc -l`，记录行数（压缩前）
2. SSH `gzip -c <原文件> > /tmp/ydyl-collect-{category}-{basename}.gz`（不删原文件）
3. rsync 拉回 `logs/collected/{ip}_{name}/`
4. 汇总写入 `logs/collected/manifest.json`（见 §5.3）

### 5.2 `stats-logs`

扫描以下本地路径，输出行数与大小 CSV 到 `output/log_stats.csv`：

| 来源 | 路径模式 |
|------|---------|
| 客户端 | `logs/client/*.log` |
| pipe 同步 | `logs/{name}-{ip}.log`（排除 `logs/client/`、`logs/collected/`） |
| 已收集压缩包 | `logs/collected/**/*.gz` |

行数规则：

- 明文 `.log`：本地 `wc -l`
- `.gz`：优先读 `manifest.json` 中记录的 `lines`（压缩前）；manifest 缺失时对解压流 `wc -l`

大小规则：

- 明文 `.log`：未压缩字节数
- `.gz`：压缩后字节数；manifest 中另记 `sizeUncompressed`（可选列）

### 5.3 `manifest.json` 结构

路径：`logs/collected/manifest.json`

```json
{
  "collectedAt": "2026-06-10T12:00:00Z",
  "entries": [
    {
      "ip": "44.251.157.206",
      "name": "tps-ydyl-cdk-1",
      "serviceType": "cdk",
      "category": "deploy",
      "remotePath": "/home/ubuntu/ydyl-deploy-logs/tps-ydyl-cdk-1.log",
      "localGz": "logs/collected/44.251.157.206_tps-ydyl-cdk-1/deploy-pipe.log.gz",
      "lines": 12345,
      "sizeCompressed": 456789,
      "skipped": false,
      "skipReason": ""
    }
  ]
}
```

`category` 取值：`deploy` | `runtime`。`skipped=true` 时 `lines` 为 0。

### 5.4 `log_stats.csv` 列

| 列名 | 说明 |
|------|------|
| `path` | 本地相对路径（相对 `ydyl-deploy-client/` 工作目录） |
| `category` | `client` / `pipe` / `kurtosis-deploy` / `runtime` |
| `source` | `local` / `collected` |
| `ip` | 服务器 IP（客户端日志为空） |
| `name` | EC2 逻辑名（客户端日志为空） |
| `lines` | 行数 |
| `size_bytes` | 见 §5.2 大小规则 |
| `compressed` | `true` / `false` |

## 6. 依赖与风险

- 宿主机需 `rsync`；远端默认 Ubuntu 自带 `gzip`
- Kurtosis 主要服务 follow 日志仍可能较大（已排除 grafana / prometheus / blockscout），需足够磁盘（建议 ≥500GiB 系统盘，与 `config.deploy.yaml` `diskSizeGiB` 一致）
- XJST 容器名默认 `testchain_node1`（`CHAIN_NAME=testchain`）；若部署时改了 `CHAIN_NAME`，需同步改监控脚本入参
- `deploy-gen.log` 文件名依赖默认 `NETWORK=gen`；非 gen 时文件名为 `deploy-{network}.log`（当前批量部署保持 gen，见 §2 说明）

## 7. 关联 spec

- 上游：[`2026-05-07-multi-sidechain-bulk-deployment-spec.md`](2026-05-07-multi-sidechain-bulk-deployment-spec.md) 4.4.4 编排链路
