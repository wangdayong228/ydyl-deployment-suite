# ydyl-deployment-suite

`ydyl-deployment-suite` 是一个面向多种 Layer2 网络的部署与运维自动化套件。当前仓库主要覆盖：

- CDK / ZK L2
- OP Stack L2
- XJST L2

顶层通过三条状态化流水线脚本统一编排部署、充值、配置生成、桥注册、服务启动和元数据收集：

- `cdk_pipe.sh`
- `op_pipe.sh`
- `xjst_pipe.sh`

这份 README 同时面向两类读者：

- 用户：想快速把某条 L2 流水线跑起来，知道从哪里开始、如何续跑、如何清理状态
- 开发者：想修改流水线、补充 step、调整服务启动方式，知道公共逻辑沉淀在哪些目录

## 仓库初始化

首次克隆后先初始化子模块：

```bash
git submodule update --init --recursive
```

顶层脚本会默认 `source ~/.ydyl-env`，因此执行流水线的机器需要预先准备好项目依赖和 PATH。常见依赖包括：

- Node.js 18+
- Go
- `cast`
- `jq`
- `pm2`
- `polycli`
- `awk`
- `envsubst`
- `ip`
- `npm`
- `yarn`
- `openssl`（OP 流水线生成随机私钥用）
- `curl`（XJST 流水线调用 `ydyl-console-service` 用）
- `python3`（XJST 部署 L1 合约用，首次运行会创建 `.venv` 安装 `web3`/`eth-account`）
- `docker`
- `docker-compose`
- `kurtosis`（CDK / OP 部署）
- `aws`（`ydyl-deploy-client` 批量创建 EC2 用）

环境初始化相关脚本：

- `install-env.sh`
  - 用途：安装 Foundry、Go、Node、PM2、Python 等依赖，并准备 `~/.ydyl-env`
  - 运行位置：每个链节点服务器 / 部署机器上执行
  - 备注：当前脚本按 Linux 服务器环境编写，并会安装 Node 22
- `setup-cfxnode.sh`
  - 用途：fullnode 重置后的本地运维修复脚本
  - 运行位置：本地执行即可，不是每个链节点都要跑

## 核心入口

| 脚本 | 作用 | 状态文件 | 主要输出 |
| --- | --- | --- | --- |
| `cdk_pipe.sh` | 部署并启动 CDK / ZK L2 全链路 | `output/cdk_pipe.state` | `cdk-work/output/deploy-result-<network>.json`、`output/<enclave>-meta.json`、`output/counter-bridge-register-result-<network>.json` |
| `op_pipe.sh` | 部署并启动 OP Stack L2 全链路 | `output/op_pipe.state` | `op-work/output/op-deployer-configs-<enclave>/wallets.json`、`output/<enclave>-meta.json`、`output/counter-bridge-register-result-<network>.json` |
| `xjst_pipe.sh` | 部署并启动 XJST L2 与相关桥接配置 | `output/xjst_pipe.state` | `xjst-work/output/`、`output/<enclave>-meta.json`、`output/counter-bridge-register-result-<network>.json` |

## 快速开始

### CDK / ZK

```bash
export L1_CHAIN_ID=<l1-chain-id>
export L2_CHAIN_ID=<l2-chain-id>
export L1_RPC_URL=<l1-rpc-url>
export L1_VAULT_PRIVATE_KEY=<l1-vault-private-key>
export L1_BRIDGE_HUB_CONTRACT=<l1-bridge-hub-address>
export L1_REGISTER_BRIDGE_PRIVATE_KEY=<l1-register-bridge-private-key>
export ENABLE_GEN_ACC=false

bash cdk_pipe.sh
```

### OP Stack

```bash
export L1_CHAIN_ID=<l1-chain-id>
export L2_CHAIN_ID=<l2-chain-id>
export L1_RPC_URL=<l1-rpc-url>
export L1_VAULT_PRIVATE_KEY=<l1-vault-private-key>
export L1_BRIDGE_HUB_CONTRACT=<l1-bridge-hub-address>
export L1_REGISTER_BRIDGE_PRIVATE_KEY=<l1-register-bridge-private-key>
export ENABLE_GEN_ACC=false

bash op_pipe.sh
```

### XJST

```bash
export L1_CHAIN_ID=<l1-chain-id>
export L1_RPC_URL=<l1-http-rpc-url>
export L1_RPC_URL_WS=<l1-ws-rpc-url>
export L1_VAULT_PRIVATE_KEY=<l1-vault-private-key>
export L1_BRIDGE_HUB_CONTRACT=<l1-bridge-hub-address>
export L1_REGISTER_BRIDGE_PRIVATE_KEY=<l1-register-bridge-private-key>
export CHAIN_NODE_IPS='[ip1,ip2,ip3,ip4]'
export NODE_ID=node-1
export GROUP_ID=<group-id>
export ENABLE_GEN_ACC=false

bash xjst_pipe.sh
```

常见执行方式：

```bash
# 默认从上次完成步骤的下一步继续
bash cdk_pipe.sh

# 从指定步骤开始
START_STEP=5 ./cdk_pipe.sh
./op_pipe.sh 7

# 彻底重来
rm output/cdk_pipe.state && ./cdk_pipe.sh

# 清理顶层状态、日志和各工作目录输出
make clean
```

## 流水线说明

### `cdk_pipe.sh`

默认步骤如下：

1. 初始化身份和密钥
2. 从 `L1_VAULT_PRIVATE_KEY` 转账 L1 ETH
3. 启动 `jsonrpc-proxy`
4. 部署 Kurtosis CDK
5. 给 `L2_PRIVATE_KEY` 和 `CLAIM_SERVICE_PRIVATE_KEY` 充值 L2 ETH
6. 生成 `zk-claim-service` 所需 `.env`
7. 部署 Counter 并注册 bridge
8. 启动 `zk-claim-service`
9. 运行 `ydyl-gen-accounts`
10. 收集元数据
11. 启动 `ydyl-console-service`
12. 检查 PM2 进程健康

CDK 特有点：

- step3 会真正启动 `jsonrpc-proxy`
- step4 调用 `cdk-work/scripts/deploy.sh`
- step6 生成并拷贝：
  - `cdk-work/output/zk-claim-service.env`
  - `cdk-work/output/counter-bridge-register.env`

### `op_pipe.sh`

默认步骤与 CDK 基本一致，也是 12 个 step，但第 3、4、6、8 步为 OP 专属实现（step3 的 OP 版本多了 `ENABLE_L1_RPC_RROXY` 的跳过分支）：

1. 初始化身份和密钥
2. 从 `L1_VAULT_PRIVATE_KEY` 转账 L1 ETH
3. 启动 `jsonrpc-proxy`
4. 部署 Kurtosis OP
5. 给 `L2_PRIVATE_KEY` 和 `CLAIM_SERVICE_PRIVATE_KEY` 充值 L2 ETH
6. 生成 `op-claim-service` / `counter-bridge-register` 所需 `.env`
7. 部署 Counter 并注册 bridge
8. 启动 `op-claim-service`
9. 运行 `ydyl-gen-accounts`
10. 收集元数据
11. 启动 `ydyl-console-service`
12. 检查 PM2 进程健康

OP 特有点：

- `run_all_steps()` 内部默认设置了 `ENABLE_L1_RPC_RROXY=true`
- 因此 step3 默认会跳过实际启动 `jsonrpc-proxy`，直接把 `L1_RPC_URL` 当成 `L1_RPC_URL_PROXY`
- 变量名 `ENABLE_L1_RPC_RROXY` 保留了历史拼写，使用时也要保持这个名字
- step4 调用 `op-work/scripts/deploy.sh`
- step6 生成并拷贝：
  - `op-work/output/op-claim-service.env`
  - `op-work/output/op-counter-bridge-register.env`

### `xjst_pipe.sh`

XJST 的编排与 CDK / OP 不同。

当 `NODE_ID=node-1` 时，默认步骤为：

1. 初始化身份和密钥
2. 从 `L1_VAULT_PRIVATE_KEY` 转账 L1 ETH
3. 启动 `ydyl-console-service`
4. 部署 L1 合约
5. 部署 XJST 节点
6. 给 `L2_PRIVATE_KEY` 充值 L2 ETH
7. 等待其它节点启动完成
8. 生成 Counter / bridge 注册环境配置
9. 部署 Counter 并注册 bridge
10. 运行 `ydyl-gen-accounts`
11. 收集元数据
12. 检查 PM2 进程健康

当 `NODE_ID!=node-1` 时，脚本会走精简路径，仅执行一步 `step5_deploy_xjst_node`（此时 `START_STEP` 只能为 1）。

XJST 特有点：

- 脚本在 `main()` 中直接固定（即便用户显式传入也会被覆盖）：
  - `L2_CHAIN_ID=0`
  - `L2_TYPE=2`
- `L2_VAULT_PRIVATE_KEY` 被硬编码为固定私钥（`xjst_pipe.sh` 的 `gen_xjst_deploy_accounts`），用户传入同样会被覆盖
- `KURTOSIS_L1_VAULT_PRIVATE_KEY` 直接复用 `L1_VAULT_PRIVATE_KEY`，不会另外生成（与 OP 不同）
- 需要额外提供：
  - `L1_RPC_URL_WS`
  - `CHAIN_NODE_IPS`
  - `NODE_ID`
  - `GROUP_ID`
- 首次运行会在仓库根目录创建 `.venv` 并安装 Python 依赖：
  - `web3==6.20.1`
  - `eth-account==0.10.0`
- node-1 会通过 `ydyl-console-service` API 拉取 L1 合约部署结果，再驱动各节点部署

## 状态管理与续跑

三条流水线都是状态化脚本，理解这一点比记命令更重要。

状态文件位置：

- `output/cdk_pipe.state`
- `output/op_pipe.state`
- `output/xjst_pipe.state`

关键行为：

- 每完成一个 step，会把 `LAST_DONE_STEP` 和白名单变量写入状态文件
- 默认执行时，会从 `LAST_DONE_STEP + 1` 继续
- 白名单由各脚本中的 `PERSIST_VARS` 控制
- 若新增变量需要跨 step 共享，必须把它加入 `PERSIST_VARS`
- 启动时会执行 `check_input_env_consistency`
  - 如果你本次显式传入的关键变量与历史状态不一致，脚本会拒绝续跑
- `DRYRUN=true` 时不会保存状态

相关产物一般落在以下目录：

- 顶层 `output/`
- `cdk-work/output/`
- `op-work/output/`
- `xjst-work/output/`

统一清理：

```bash
make clean
```

该命令会删除：

- `output/`
- `logs/`
- `~/ydyl-deploy-logs`
- `cdk-work/output/`
- `op-work/output/`
- `xjst-work/output/`

## 关键环境变量

### CDK / OP 共通必填

- `L1_CHAIN_ID`
- `L2_CHAIN_ID`
- `L1_RPC_URL`
- `L1_VAULT_PRIVATE_KEY`
- `L1_BRIDGE_HUB_CONTRACT`
- `L1_REGISTER_BRIDGE_PRIVATE_KEY`
- `ENABLE_GEN_ACC`

说明：

- `ENABLE_GEN_ACC` 虽然是开关，但当前脚本要求它必须有值，通常填 `true` 或 `false`
- `L2_PRIVATE_KEY`、`CLAIM_SERVICE_PRIVATE_KEY` 由 step1 (`step1_init_identities`) 自动生成
- `KURTOSIS_L1_PREALLOCATED_MNEMONIC` 的生成位置按流水线不同：
  - CDK：step1 生成
  - OP：在 step1 与 step2 之间的 `gen_op_enclave_deploy_accounts()` 生成
  - XJST：不使用该助记词（直接以 `L1_VAULT_PRIVATE_KEY` 作为 `KURTOSIS_L1_VAULT_PRIVATE_KEY`）

### OP 常用可选变量

- `ENCLAVE_NAME`，默认 `op-gen`
- `KURTOSIS_L1_VAULT_PRIVATE_KEY`：若未设置，`gen_op_enclave_deploy_accounts()` 会用 `openssl rand -hex 32` 生成随机私钥
- `KURTOSIS_L1_PREALLOCATED_MNEMONIC`：若未设置，`gen_op_enclave_deploy_accounts()` 会用 `cast wallet new-mnemonic` 自动生成
- `ENABLE_L1_RPC_RROXY`：`run_all_steps()` 默认设为 `true`，因此 OP 流水线默认不会真正启动 `jsonrpc-proxy`
- `DRYRUN`

### CDK 常用可选变量

- `ENCLAVE_NAME`，默认 `cdk-gen`
- `DEPLOY_RESULT_FILE`
- `L2_VAULT_PRIVATE_KEY`
- `DRYRUN`

### XJST 必填补充

- `L1_RPC_URL_WS`
- `CHAIN_NODE_IPS`
- `NODE_ID`
- `GROUP_ID`
- `ENABLE_GEN_ACC`

### 开发时建议优先看的位置

每个顶层脚本头部都有一段“使用说明（简要）”注释块。改动流水线前，先看：

- `cdk_pipe.sh`
- `op_pipe.sh`
- `xjst_pipe.sh`

## 仓库结构

| 目录 | 语言 / 形态 | 作用 |
| --- | --- | --- |
| `cdk-work/` | Bash / Nginx / Kurtosis 辅助脚本 | CDK 部署、配置生成、输出落盘 |
| `op-work/` | Bash / Nginx / Kurtosis 辅助脚本 | OP Stack 部署、配置生成、工具脚本 |
| `xjst-work/` | Bash / Python / Node | XJST 节点部署与多节点协同 |
| `ydyl-scripts-lib/` | Bash 公共库 | 通用 step、状态持久化、错误处理、部署骨架 |
| `jsonrpc-proxy/` | Node.js + Koa + SQLite | L1/L2 RPC 代理与区块哈希修正 |
| `zk-claim-service/` | Node.js + Hardhat + PM2 | ZK 消息监听、proof 获取、交易中继服务，同时承载 `Counter` / bridge 注册、跨链压测、跨链 TPS 监控脚本 |
| `op-claim-service/` | Node.js + PM2 | OP L2 -> L1 消息监听、proof 生成与中继服务 |
| `ydyl-console-service/` | Go + Gin | 部署结果、状态与链信息 HTTP API |
| `ydyl-deploy-client/` | Go + Cobra | AWS EC2 批量部署、生成跨链压测 jobs、远程执行与日志收集 |
| `ydyl-gen-accounts/` | Hardhat / TypeScript | 批量生成账户、充值、并发压测 |
| `ydyl-bench-docker/` | Docker Compose | 基于 jobs 配置启动 8 个压测发送容器和 1 个 TPS 监控容器 |
| `cfxnode-work/` | 运维脚本 / 配置 | fullnode 相关环境准备与辅助文件 |
| `tools/` | 杂项脚本 | 临时性运维 / 调试工具 |
| `doc-report/` | 文档 | 报告、调研与设计文档 |
| `install-env.sh`、`install-zsh.sh`、`setup-cfxnode.sh` | Bash | 部署机环境初始化与 fullnode 重置修复 |

## 常用开发命令

### `jsonrpc-proxy`

```bash
cd jsonrpc-proxy
npm i
npm run start:cdk   # 通过 PM2 启动，进程名 jsonrpc-proxy-cdk，读取 .env_cdk
npm run start:op    # 通过 PM2 启动，进程名 jsonrpc-proxy-op，读取 .env_op
npm test            # mocha 测试
```

说明：

- `start:cdk` / `start:op` 实际执行 `pm2 start "... node ./index.js"`，不是直接前台运行 Node。
- 停止请使用 `pm2 stop jsonrpc-proxy-cdk` 或 `pm2 delete <name>`。

### `zk-claim-service`

```bash
cd zk-claim-service
yarn
yarn start
yarn status
yarn stop
yarn logs
```

说明：

- `yarn start` 会通过 PM2 启动 `ecosystem.config.js` 中定义的 8 个服务
  - `l2-l1-eventListener`
  - `l2-l1-proofFetcher`
  - `l2-l1-transactionSender`
  - `l2-l1-transactionSenderBalanceCheck`
  - `l1-l2-eventListener`
  - `l1-l2-proofFetcher`
  - `l1-l2-transactionSender`
  - `l1-l2-transactionSenderBalanceCheck`
- `zk-claim-service` 本身就是长期运行的跨域消息中继服务（与 `op-claim-service` 对应），同时承载 Counter 部署 / bridge 注册 / 压测脚本
- 另外还包含压测与 TPS 统计脚本，重点是：
  - `scripts/7s_multijob.js`
    - 作用：读取 jobs 配置并并发发送跨链交易
    - 默认输入：`scripts/7s_jobs.json`
    - 默认输出目录：当前目录
  - `scripts/h_TPSjob.js`
    - 作用：读取同一份 jobs 配置和 `7s_multijob.js` 生成的 hash JSON，统计各 job 和总 TPS
    - 默认输入：`scripts/7s_jobs.json`
    - 默认输出目录：当前目录

压测脚本常用方式：

```bash
cd zk-claim-service
node scripts/7s_multijob.js ./scripts/7s_jobs.json .
node scripts/h_TPSjob.js ./scripts/7s_jobs.json .
```

### `op-claim-service`

```bash
cd op-claim-service
npm i
npm run start
npm run stop
npm run logs
```

### `ydyl-console-service`

```bash
cd ydyl-console-service
cp config.sample.yaml config.yaml
go build .
./ydyl-console-service

# 生成 swagger
make swag
```

### `ydyl-deploy-client`

```bash
cd ydyl-deploy-client
go build -o ydyl-deploy-client .
go run . deploy -f config.deploy.yaml
go run . gen-cross-tx-config --servers ./output/servers.json --config ./config.deploy.yaml
```

主要子命令（完整列表见 `ydyl-deploy-client --help`）：

- `deploy`
  - 作用：批量创建 EC2、等待 SSH、远程执行部署命令
  - 常见产物：`output/servers.json`、`output/script_status.json`、`output/servers_create.json`
- `deploy-restore`：基于已有 `servers.json` 重新触发远端部署脚本
- `gen-cross-tx-config`
  - 作用：读取 `servers.json`，再从各链节点的 `ydyl-console-service` 拉取 RPC 和合约信息，生成 `zk-claim-service/scripts/7s_multijob.js` 所需 jobs
  - 默认输出：`<servers 所在目录>/jobs/all.json` 和 `jobs/1.json ~ jobs/N.json`
  - 默认拆分份数：8
- `waitssh`：等待指定主机 SSH 就绪
- `sync`：向远端主机同步文件 / 脚本
- `shutdown`：批量停机 / 终止实例
- `monitor-gen-accounts`：远端观察 `ydyl-gen-accounts` 进度
- `bench-cross-tx`：批量触发跨链压测
- `tps`：拉取并汇总各节点 TPS
- `setup-cfxnode`：远端执行 `setup-cfxnode.sh` 的对应逻辑

典型顺序：

1. 先执行 `deploy`，把链节点和服务拉起来
2. 再执行 `gen-cross-tx-config`，生成压测 jobs
3. 然后进入 `ydyl-bench-docker` 跑 `docker-compose`

如果 `servers` 使用的是 `ydyl-deploy-client/output/servers.json`，且 `gen-cross-tx-config` 不额外传 `--out`，那么 jobs 会生成到：

```bash
ydyl-deploy-client/output/jobs/
```

这正好是 `ydyl-bench-docker/docker-compose.yml` 默认挂载的目录。

### `ydyl-gen-accounts`

```bash
cd ydyl-gen-accounts
npm i
npm run build
npm run start -- --fundAmount 1000 --processes 1 --capacity 20000000
```

### `ydyl-bench-docker`

```bash
cd ydyl-bench-docker
docker-compose up --build
```

说明：

- 这个 Compose 文件会把 `../ydyl-deploy-client/output/jobs` 挂载到容器内 `/app/jobs`
- 如果 `gen-cross-tx-config` 使用了自定义 `--out`，需要同步修改这里的 bind mount 路径
- 默认会启动：
  - `multijob-1` 到 `multijob-8`
  - `tps`
- 其中：
  - 8 个 `multijob-*` 容器分别执行 `zk-claim-service/scripts/7s_multijob.js`，每个读取一个拆分后的 jobs 文件
  - 1 个 `tps` 容器执行 `zk-claim-service/scripts/h_TPSjob.js`，读取 `all.json` 做统一 TPS 监控

典型压测流程：

```bash
cd ydyl-deploy-client
go run . deploy -f config.deploy.yaml
go run . gen-cross-tx-config --servers ./output/servers.json --config ./config.deploy.yaml

cd ../ydyl-bench-docker
docker-compose up --build
```

## 对开发者的约定

- 三条流水线的公共逻辑优先沉淀到 `ydyl-scripts-lib/`
- 只把真正的链类型专属 step 留在 `cdk_pipe.sh`、`op_pipe.sh`、`xjst_pipe.sh`
- 修改 `ydyl-scripts-lib` 时，要同时评估对三条流水线的影响
- Bash 脚本应 `source utils.sh` 并调用 `ydyl_enable_traps`
- 新增跨 step 变量时，记得加入对应脚本的 `PERSIST_VARS`
- Node 服务统一由 PM2 管理
- `ydyl-console-service` 使用 `config.sample.yaml -> config.yaml` 的方式启动
- 不要只改 README 而不改脚本头注释；两处文档应保持一致

## 说明：Counter 部署与 bridgeHub 注册（step7）

`cdk_pipe.sh`、`op_pipe.sh` 和 `xjst_pipe.sh` 最终都会复用同一个 step7 核心逻辑：

- 进入 `zk-claim-service/`
- `yarn`
- `npx hardhat compile`
- 执行 `scripts/i_deployCounterAndRegisterBridge.js`

默认结果文件：

```bash
output/counter-bridge-register-result-$NETWORK.json
```

这个 step 会完成两件事：

1. 在 L2 部署 `Counter`
2. 在 L1 的 `bridgeHub` 上调用 `addBridgeService` 注册桥地址

脚本读取的核心环境文件是：

```bash
zk-claim-service/.env.counter-bridge-register
```

不同流水线生成这个文件的方式不同：

- CDK：由 `cdk-work/scripts/gen-zk-claim-service-env.sh` 生成后拷贝过来
- OP：由 `op-work/scripts/gen-op-claim-service-env.sh` 生成后拷贝过来
- XJST：由 `xjst_pipe.sh` 的 step8 直接写入

桥地址使用 `BRIDGES` 数组：

- `.env.counter-bridge-register` 中使用逗号分隔
- CLI 中可以重复传参 `--bridges 0x... --bridges 0x...`

示例：

```bash
BRIDGES=0xaaa...,0xbbb...
```

## 重置 fullnode 后环境配置

fullnode 被重置后，至少要重新确认以下几件事：

1. `confura` 相关入口是否已经切到新的 fullnode / RPC
2. `scan` 相关入口是否已经切到新的 fullnode / RPC
3. 运行 [`setup-cfxnode.sh`](./setup-cfxnode.sh) 重新补齐 deterministic 合约、bridge 合约与 `jsonrpc-proxy-op`

`setup-cfxnode.sh` 当前实际会做这些事：

1. 用 `cast` 部署 deterministic contract 所需的前置交易
2. 进入 `zk-claim-service/`，执行 `ignition/modules/4_deployzkBR.js` 部署 bridge 合约
3. SSH 到远端机器，清理并重启 `jsonrpc-proxy-op`
4. 给若干固定账户重新注资

运行前请确认：

- 已设置 `L1_RPC_URL`
- 已设置 `L1_VAULT_PRIVATE_KEY`
- 本机可以 SSH 到脚本里写死的目标主机
- 你接受脚本中的固定地址、固定私钥和远端主机配置

运行方式：

```bash
bash setup-cfxnode.sh
```

这个脚本偏运维应急用途，不是通用化流水线。执行前建议先完整审阅脚本内容。
