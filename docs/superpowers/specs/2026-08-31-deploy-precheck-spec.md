# Deploy 前预检（check）

## 背景

Confura 机器重启后公网 IP 会变，`jsonrpc-proxy-op` 也需要在新机器上重新拉起。若此时直接 `deploy`，`NewDeployer` 会先归档旧 `output/` / `logs/`，再创建 EC2，L1 不通也会烧掉一轮产物与实例。

需要在创建 EC2 之前，对 `config.deploy.yaml` 做连通性预检；不通则失败退出。

## 目标

- 独立命令：`ydyl-deploy-client check -f config.deploy.yaml`
- `deploy` 在 `withClientCommandTee` 内、`RunWithRestoreRetryWithOptions` 之前调用同一套 `precheck.Run`
- 任一检查失败则非零退出，不创建 EC2、不归档
- 预检不调用、不自动重启 proxy；proxy 单独重跑用 `ONLY_UPDATE_CONFURA_IP=true bash setup-cfxnode.sh`（现为脚本第 1 步）
- 不做 `--skip-check`

## 非目标

- 不 SSH 到 Confura，不直连 `127.0.0.1:28545`
- 不读远端 pm2 / `.env_op`
- 不对比 `eth_getBlockByNumber` 的 hash 是否已被修正
- 不检查 `setup-cfxnode.sh` 的 step2 npm cross、step3/4 合约部署、step5 打款
- 不改 `config.deploy.yaml` 里的 IP
- 不增加通用 `ONLY_STEP`；proxy 单独重跑使用 `ONLY_UPDATE_CONFURA_IP=true`

## 检查项

超时默认 10s，失败即停。

### 1. OP artifacts（仅当存在 `type: op` 且 `count > 0`）

读仓库根下 `op-work/scripts/params.template.yml`（**不**读 gitignore 的 `params-gen.yml`）的 `l1_artifacts_locator`；若 `l2_artifacts_locator` 与它不同则各查一次。

HTTP HEAD，非 2xx 再 GET。不落盘、不读完整 tar。失败信息带 URL 和 HTTP status。

### 2. 全局 `l1RpcUrl` / `l1RpcUrlWs`

POST JSON-RPC `eth_chainId`。若配置了 `l1ChainId`，结果必须一致（十进制或 hex）。`l1RpcUrlWs` 为空则跳过。

### 3. `services.op.l1RpcUrl`（jsonrpc-proxy-op 公网入口）

不打 `.env_op` 的 `JSONRPC_URL=http://127.0.0.1:28545`（只在 Confura 本机有效）。预检打 YAML 里的公网入口（通常 `:3031`）。

`eth_chainId` / `eth_blockNumber` 在 proxy 中无专用中间件，会落到 `call_rpc` 转发到本机 28545。公网入口能返回二者，即 proxy 在听且上游 L1 通。

判定：

- `eth_chainId` 成功，且与 `l1ChainId`、与全局 `l1RpcUrl` 的 chainId 一致
- `eth_blockNumber` 成功
- 规范化后的 URL 必须与全局 `l1RpcUrl` 不同（避免 OP 直连 `/espace`、吃到未修正的 block hash）

仅当 op `count > 0` 且该字段非空时检查。空则沿用全局 `l1RpcUrl`，不再重复打，但警告：OP 将直连 Confura，没有 jsonrpc-proxy。

失败时写明这是 jsonrpc-proxy-op 公网入口，并提示运行 `setup-cfxnode.sh` 的第 1 步（`ONLY_UPDATE_CONFURA_IP=true` 即可只重启 `jsonrpc-proxy-op`）。可能原因（预检机无法区分）一并写出：YAML 仍是旧 IP、proxy 未启动、或 Confura 本机 28545 未起来。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/precheck/precheck.go` | 预检实现 |
| `ydyl-deploy-client/internal/precheck/precheck_test.go` | httptest + 本地 websocket，不打真实网络 |
| `ydyl-deploy-client/cmd/check.go` | cobra `check` 子命令 |
| `ydyl-deploy-client/cmd/check_test.go` | 注册校验 |
| `ydyl-deploy-client/cmd/deploy.go` | tee 内、Run 前调用 precheck |
| `ydyl-deploy-client/cmd/bench_cross_tx_test.go` | 补齐 LoadConfigFromFile 必填字段，使 `go test ./cmd` 能跑 |
| `ydyl-deploy-client/go.mod` | `gorilla/websocket`、`gopkg.in/yaml.v3` 改为直接依赖 |
| `setup-cfxnode.sh` | 预检仍不调用该脚本；脚本第 1 步为重启 `jsonrpc-proxy-op`，`ONLY_UPDATE_CONFURA_IP=true` 仅执行这一步 |

## 用法

```bash
cd ydyl-deploy-client
go run . check -f config.deploy.yaml
go run . deploy -f config.deploy.yaml
```
