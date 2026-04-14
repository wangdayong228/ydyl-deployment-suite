# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库概述

`ydyl-deployment-suite` 是多种 Layer2 网络（ZK/CDK、OP Stack、XJST）的部署与运维自动化套件。顶层脚本编排若干 Git 子模块中的服务与部署工具。克隆后必须先执行：

```bash
git submodule update --init --recursive
```

## 顶层流水线

三个脚本是进入代码库的主入口，都编排 "step1..stepN" 的多步流程：

- `cdk_pipe.sh` — ZK/CDK L2（通过 Kurtosis 部署）
- `op_pipe.sh` — OP Stack L2
- `xjst_pipe.sh` — XJST L2

通用用法：

```bash
# 从头开始（或从上次中断步骤的下一步续跑）
bash cdk_pipe.sh

# 从指定步骤开始
START_STEP=5 ./cdk_pipe.sh          # 或：./cdk_pipe.sh 5

# 彻底重来
rm output/cdk_pipe.state && ./cdk_pipe.sh
```

每个流水线脚本头部都有**必需/可选环境变量**的详细说明（如 `L1_CHAIN_ID`、`L2_CHAIN_ID`、`L1_RPC_URL`、`L1_VAULT_PRIVATE_KEY`、`L1_BRIDGE_HUB_CONTRACT`、`L1_REGISTER_BRIDGE_PRIVATE_KEY`、`ENABLE_GEN_ACC` 等）— 修改流水线前请先阅读脚本顶部的注释块。

### 状态管理（关键）

流水线是**状态化**的，必须理解以下机制再做修改：

- 每次执行会把关键变量写入 `output/{cdk,op,xjst}_pipe.state`，启动时自动 `source` 该文件以支持续跑。
- 哪些变量被持久化由各 `*_pipe.sh` 中的 `PERSIST_VARS` 白名单决定；新增需要跨步骤共享的变量时必须加入该列表。
- 用户输入的关键变量通过 `check_input_env_consistency` 与历史 state 比对，不一致会拒绝续跑 — 这是为了防止中途换网络污染已有产物。
- 部署产物（合约地址、私钥等）落到 `cdk-work/output/`、`op-work/output/`、`xjst-work/output/` 的 JSON 文件中。

清理所有状态与产物：`make clean`（删除 `output/`、`logs/`、各 work 目录的 `output/` 以及 `~/ydyl-deploy-logs`）。

## 架构

### 组件分工

| 组件 | 类型 | 作用 |
|------|------|------|
| `cdk-work` / `op-work` / `xjst-work` | Bash + Nginx 配置 | 特定 L2 的部署脚本与模板；被流水线的 step4/step6/step7 调用 |
| `ydyl-scripts-lib` | 共享 Bash 库 | `utils.sh`、`pipeline_utils.sh`、`pipeline_steps_lib.sh`、`deploy_common.sh` — 三条流水线的公共步骤都在这里 |
| `jsonrpc-proxy` | Koa (Node.js) | L1/L2 RPC 代理，带 SQLite 日志和区块哈希修正，流水线 step3 启动 |
| `zk-claim-service` | Node.js + PM2 | 监听 ZK 跨域消息，拉取 ZK proof 并在 L1 发交易 |
| `op-claim-service` | Node.js + PM2 | 监听 OP 跨域消息，生成证明并中继到 L1 |
| `ydyl-console-service` | Go + Gin | 监控部署状态、链元数据的 HTTP API |
| `ydyl-deploy-client` | Go + Cobra | 批量创建 EC2 实例、远程执行部署命令、收集日志 |
| `ydyl-gen-accounts` | Hardhat/TS | 批量生成测试账户并充值，用于压测与演示 |
| `ydyl-bench-docker` | Docker Compose | 跨交易 TPS 基准测试环境 |

### 流水线步骤说明

`cdk_pipe.sh` 与 `op_pipe.sh` 基本遵循同一骨架（step 编号由各 `*_pipe.sh` 里的 `run_step` 调度定义，`pipeline_steps_lib.sh` 主要提供可复用 step 函数）：

1. 生成身份和密钥（助记词、claim-service EOA、L2 部署 key 等）
2. 从 `L1_VAULT_PRIVATE_KEY` 给各账户充 L1 ETH
3. 处理 L1 RPC 入口（CDK 启动 `jsonrpc-proxy`；OP 默认可跳过 proxy 并直连 L1 RPC）
4. 部署 L2（CDK 走 Kurtosis，OP 走 OP Stack 脚本）
5. 给 L2 账户充值
6. 生成 claim-service / bridge register 所需 `.env`
7. L2 部署 `Counter` 合约 + L1 `bridgeHub.addBridgeService` 注册桥（见下方）
8. 启动 claim-service（CDK: `zk-claim-service`，OP: `op-claim-service`）
9. （可选）`ydyl-gen-accounts` 生成测试账户
10. 收集元数据
11. 启动 `ydyl-console-service`
12. 检查 PM2 进程健康

`xjst_pipe.sh` 的步骤编排与上面不同，包含“部署 L1 合约”“部署 xjst 节点”“等待多节点就绪”等 XJST 专属流程，应以 `xjst_pipe.sh` 的 `run_step` 为准。

**step7 的桥注册**：执行 `zk-claim-service/scripts/i_deployCounterAndRegisterBridge.js`，读取 `zk-claim-service/.env.counter-bridge-register`。桥地址使用 `BRIDGES` 数组（逗号分隔），也可通过 CLI `--bridges 0x... --bridges 0x...` 重复传参。

## 子服务开发命令

### Node.js 服务（`jsonrpc-proxy`、`zk-claim-service`、`op-claim-service`）

```bash
yarn              # 或 npm i

# jsonrpc-proxy
npm run start:cdk # 或 npm run start:op
npm test          # 仅 jsonrpc-proxy 有 Mocha 测试

# zk-claim-service / op-claim-service
yarn start        # 通过 PM2 启动
yarn stop
yarn logs         # 查看 PM2 日志
```

PM2 与启动脚本以各自 `package.json` 为准；`zk-claim-service` / `op-claim-service` 使用 `ecosystem.config.js`，`jsonrpc-proxy` 使用 `pm2 start "...node ./index.js"` 的脚本命令。

### Go 服务（`ydyl-console-service`、`ydyl-deploy-client`）

```bash
go build -o <binary> .
go run . [args]
go test ./...                      # 跑所有测试
go test ./path/to/pkg -run TestX   # 跑单个测试

# ydyl-deploy-client 主命令
cd ydyl-deploy-client && go run . deploy -f config.deploy.yaml

# ydyl-console-service 生成 Swagger
cd ydyl-console-service && make swag
```

### ydyl-gen-accounts（Hardhat/TS）

```bash
cd ydyl-gen-accounts
npx hardhat run scripts/<script>.ts
```

### ydyl-bench-docker

```bash
cd ydyl-bench-docker && docker-compose up --build
```

## 环境依赖

- **Node.js** ≥ 18，**Go** ≥ 1.25
- **必需 CLI**：`cast`、`jq`、`pm2`、`polycli`、`awk`、`envsubst`、`ip`、`npm`、`yarn`、`openssl`、`docker`、`docker-compose`
- **AWS CLI** — `ydyl-deploy-client` 用
- **Kurtosis** — CDK 流水线 step4 通过 `cdk-work/scripts/deploy.sh` 调用
- 流水线脚本会 `source ~/.ydyl-env` 设置 `cast`/`go`/`nvm` 等 PATH；首次机器准备用 `install-env.sh` 和 `setup-cfxnode.sh`

## 配置文件位置

- `.env` 风格：每个 Node 服务自带（如 `zk-claim-service/.env`、`jsonrpc-proxy/.env_cdk`）。流水线会从 `cdk-work/output/` 等处生成后再 `cp` 过去。
- YAML：`ydyl-deploy-client/config.deploy.yaml`、`ydyl-console-service/config.yaml`
- 流水线环境变量：见各 `*_pipe.sh` 脚本顶部注释块

## 开发约定

- 流水线逻辑优先拆到 `ydyl-scripts-lib` 的函数中复用；只在 `*_pipe.sh` 中保留 **CDK/OP/XJST 专属** 的 step（如 `cdk_pipe.sh` 里的 `step3_start_jsonrpc_proxy`、`step4_deploy_kurtosis_cdk`）。
- 修改 `ydyl-scripts-lib` 时**务必**评估对三条流水线的影响 — 它是三个入口的公共基座。
- Bash 脚本必须 `source utils.sh` 并调用 `ydyl_enable_traps` 启用错误陷阱（嵌套调用外部脚本时用 `YDYL_NO_TRAP=1` 临时抑制，见 `step4_deploy_kurtosis_cdk` 中的用法）。
- Node 服务一律用 PM2 管理；其中 `zk-claim-service` / `op-claim-service` 使用 `ecosystem.config.js`，`jsonrpc-proxy` 通过 `package.json` 脚本直接调用 `pm2 start`。
- Go 服务：CLI 用 Cobra（`ydyl-deploy-client`），HTTP 用 Gin（`ydyl-console-service`）。
- 新增需要跨 step 传递的变量时，记得加入对应流水线的 `PERSIST_VARS` 白名单，否则续跑时会丢失。
- 提交信息中英文均可，代码库两种都用。

## 来自 `.cursorrules`

- 定位为**资深 Golang 后端工程师**，熟悉 AWS。
- 遵循模块化与代码复用；命名准确而简洁，符合 Go 规范。
