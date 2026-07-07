# 测试用例：服务端日志路径与测试私钥

## 任务二：测试私钥

测试用例由 `ydyl-deploy-client/config.deploy.yaml` 显式提供 **2 个** L1 侧密钥；流水线 step1 自动生成的 `CLAIM_SERVICE_PRIVATE_KEY`、`L2_PRIVATE_KEY`、`KURTOSIS_L1_PREALLOCATED_MNEMONIC`，以及 deploy 时由 `l1VaultMnemonic` 按链衍生的远端 `L1_VAULT_PRIVATE_KEY` 等不在此列。

### 1. `l1VaultMnemonic`

- **配置项**：`l1VaultMnemonic`
- **值**：见 `ydyl-deploy-client/config.deploy.yaml` 中 `l1VaultMnemonic`（勿提交到公开仓库）
- **源账户派生**：`m/44'/60'/0'/0/0`
- **源账户地址**：`0xcE4CC6E76635FfAAD91a587f204011D3d3B96EB9`
- **权限（deploy client 侧）**：L1 普通 EOA；`deploy` 命令的 `fundAllL1Vaults` 从该地址向各链衍生的 vault 地址充值 L1 ETH（当前 OP 首台对应 `L2_CHAIN_ID=10000`），无合约 owner/admin 权限
- **说明**：远端 pipe step2 使用的 `L1_VAULT_PRIVATE_KEY` 由同一助记词在 deploy 时按 `m/44'/{deriveRand}/{serviceType}` + `index` 衍生，地址随每次 deploy 的 `deriveRand` 变化，不在 config 中单独配置

### 2. `l1RegisterBridgePrivateKey`

- **配置项**：`l1RegisterBridgePrivateKey`
- **值**：见 `ydyl-deploy-client/config.deploy.yaml` 中 `l1RegisterBridgePrivateKey`（勿提交到公开仓库）
- **地址**：`0xef431755Bb97ed53874E3e27cAD2cD3399558e25`
- **权限**：L1 普通 EOA；pipe step2 接收 L1 ETH 充值；pipe step7 以该账户调用 `bridgeHub.addBridgeService`（`L1_BRIDGE_HUB_CONTRACT: 0x7aC81f608D15819148317EeAD3169734664205Bb`）注册 L2 bridge


## 任务三：服务端系统日志路径

`name` 是 deploy 时为每台 EC2 生成的逻辑名（与 Name tag 一致）：OP / CDK 为 `{tagPrefix}-{type}-{序号}`（如 `tps-ydyl-op-1`）；XJST 为 `{tagPrefix}-xjst-{组号}-{组内序号}`（如 `tps-ydyl-xjst-1-1`）。

**pipe 日志**是顶层流水线脚本（如 `cdk_pipe.sh` / `op_pipe.sh`）的完整输出；**kurtosis 日志**是 `xx_pipe.sh` 里 `kurtosis run` 单独重定向的输出（默认 `NETWORK=gen`，文件名为 `deploy-gen.log`），两者阶段不同，故 CDK/OP 各有两份部署日志。

以下 OP 示例对应当前配置；CDK / XJST 为同命名规则下的示例。XJST 仅组内序号为 1 的节点（如 `tps-ydyl-xjst-1-1`）会生成 runtime 日志。

### 1. CDK

- pipe 部署日志：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-cdk-1.log`
- kurtosis 部署日志：`/home/ubuntu/workspace/ydyl-deployment-suite/cdk-work/scripts/deploy-gen.log`
- 运行期日志（kurtosis 服务日志经脚本过滤后落盘）：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-cdk-1-runtime.log`

### 2. OP

- pipe 部署日志：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-op-1.log`
- kurtosis 部署日志：`/home/ubuntu/workspace/ydyl-deployment-suite/op-work/scripts/deploy-gen.log`
- 运行期日志（kurtosis 服务日志经脚本过滤后落盘）：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-op-1-runtime.log`

### 3. XJST

- pipe 部署日志：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-xjst-1-1.log`
- 运行期日志（`docker logs -f testchain_node1` 经脚本落盘）：`/home/ubuntu/ydyl-deploy-logs/tps-ydyl-xjst-1-1-runtime.log`
