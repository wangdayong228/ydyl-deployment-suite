# `ydyl-gen-accounts` 支持 Conflux Core Space

## 背景

`ydyl-gen-accounts` 当前通过 `l2type` 区分运行时：

| `l2type` | 网络类型 | SDK |
|----------|----------|-----|
| `0` / `1` | EVM L2 | `ethers` |
| `2` | XJST | 仓库内嵌的 `@xjshutu/js-conflux-sdk@0.13.6-consortium.1.0.6` |

内嵌 SDK 是面向 XJST 的联盟链分叉。它删除了标准 Conflux 交易中的 `storageLimit` 编码，并配合现有脚本固定使用 `chainId=0`、`gasPrice=0`、`gas=0`。这些行为不能直接用于标准 Conflux Core Space。

官方 [`js-conflux-sdk`](https://github.com/Conflux-Chain/js-conflux-sdk) 专门支持 Core Space，能够处理标准 Core JSON-RPC、交易签名、gas 与存储抵押字段。因此 Core Space 必须使用独立的官方 SDK 运行时，不能复用或替换 XJST 分叉。

## 目标

- 为 `scripts/2_genAccsByContract.ts` 和 `scripts/2_genAccsByEoa.ts` 增加 Conflux Core Space 支持。
- 新增 `l2type=3` 表示 Core Space，保持 `l2type=0/1/2` 的现有行为不变。
- 引入官方 `js-conflux-sdk`，与内嵌 XJST SDK 并存且职责隔离。
- Core Space 的网络参数从目标 RPC 自动获取，支持主网、测试网和私有 Core 网络。
- CLI 参数、日志、进度文件及合约 ABI 参数统一使用 `0x` 地址。
- 保留两个脚本现有的断点续跑、批量发送、交易窗口、回执检查和失败进度记录语义。

## 非目标

- 本次不修改 `scripts/3_concurrency.ts`、`scripts/5_contract_status.ts`、`scripts/6_fund.ts` 或流水线入口。
- 本次不改变 XJST 的零 gas、`groupId` 私钥派生或定制交易编码。
- 本次不迁移或删除 `libs/js-conflux-sdk`。
- 本次不支持以 CIP-37 地址作为 CLI 输入或进度文件输出。
- 本次不部署 Core Space `BatchSender` 合约；调用方仍需提供已经部署的合约地址。

## 方案选择

### 采用：独立 Core Space 适配器

新增官方 `js-conflux-sdk` 依赖，并用一个共享适配层封装两个脚本所需的最小 Core 能力。EVM、XJST、Core 三类运行时在脚本入口按 `l2type` 分流。

优点：

- 不触碰 XJST 已验证的定制协议行为。
- Core 交易格式、地址处理和 RPC 调用由官方 SDK 负责。
- 两个脚本复用同一套 Core 初始化与交易工具，减少分支重复。

### 不采用：用官方 SDK 替换内嵌 SDK

官方 SDK 会恢复标准 `storageLimit` 和网络规则，与 XJST 当前的定制交易格式不兼容，会破坏 `l2type=2`。

### 不采用：继续扩展内嵌 SDK

在同一份分叉中同时维护 XJST 和标准 Core 两套交易编码，协议边界不清晰，后续升级和排障风险较高。

## 详细设计

### 1. 类型与参数

- 两个目标脚本及必要共享类型中的 `L2Type` 从 `0 | 1 | 2` 扩展为 `0 | 1 | 2 | 3`。
- 参数校验和帮助文本同步接受 `l2type=3`。
- `l2type=3` 不使用也不要求 `groupId`。
- `batchSender`、付款账户和生成账户对外均保持 `0x` 十六进制地址。
- `gasPrice` 对 Core Space 可选：显式提供时使用固定值，未提供时读取 RPC 建议值。

### 2. SDK 隔离

- `libs/js-conflux-sdk` 继续仅供 `l2type=2` 使用，并在导入时使用 XJST 专用别名。
- `package.json` 增加官方 `js-conflux-sdk@^2.6.0` 依赖，`package-lock.json` 固定实际安装版本。
- 新增共享 Core Space 适配模块，负责：
  - 创建官方 `Conflux` client；
  - 启用十六进制地址 RPC 参数；
  - 从 `cfx_getStatus` 初始化 `networkId` 并取得 `chainId`；
  - 从私钥生成符合 Core 地址类型规则的账户，并转换成 `0x` 地址；
  - 统一 Core 回执、nonce、epoch、gas、存储抵押和交易存在性查询。

适配层只暴露两个脚本实际需要的接口，不向上层泄漏官方 SDK 与 XJST 分叉之间的 API 差异。

### 3. 确定性账户生成

现有私钥布局保持不变：

```text
32 字节私钥 = 左侧补零 + chainId（4 字节）+ addressIndex（10 字节）
```

- `l2type=0/1`：继续使用 EVM RPC `chainId` 和 `ethers.Wallet`。
- `l2type=2`：继续使用 `groupId` 和内嵌 XJST `Account`。
- `l2type=3`：使用 Core RPC `cfx_getStatus().chainId`，再由官方 SDK 账户实现派生 Core 用户地址。

Core 分支最终返回 `0x` 地址。不得使用 `ethers.Wallet.address` 代替 Core 账户派生，因为 Core 用户地址包含协议规定的地址类型位。

### 4. `2_genAccsByContract.ts`

`l2type=3` 初始化时：

1. 连接 Core RPC 并读取 `networkId`、`chainId`、当前 epoch 和 gas price。
2. 用付款私钥创建官方 SDK 账户。
3. 用 `0x` 合约地址和现有 `BatchSender` ABI 创建 Core 合约实例。
4. 读取 `startAddressIndex`、`totalCount`、`lastAddressIndex` 和 `remainCount`。
5. 按 Core `chainId` 生成目标账户地址并调用 `batchSendETH`。

每个交易窗口必须使用标准 Core 交易字段：

- 连续 nonce；
- 当前 `epochHeight`；
- 正确的 `chainId`；
- 显式参数或 RPC 返回的 `gasPrice`；
- `cfx_estimateGasAndCollateral` 返回并带安全余量的 `gas` 与 `storageLimit`；
- `value = amountPerAddressWei * batch.length`。

交易回执以 `outcomeStatus === 0` 为成功。超时后的交易存在性检查、按原 nonce 补发及进度刷新保持现有语义。

### 5. `2_genAccsByEoa.ts`

Core Space 有正常 gas 成本，新账户必须在收到 `2_genAccsByContract.ts` 的转账后才能发送自转账。因此 `l2type=3` 沿用 `l2type=0/1` 的协调方式：

- 必须提供 `--by-contract-progress`；
- 从进度文件读取 RPC、`startAddressIndex` 和已充值数量；
- `ByContractProgressWatcher` 控制当前允许发送的账户索引；
- 每个账户使用与 by-contract 相同的 Core `chainId + addressIndex` 规则恢复私钥；
- 使用官方 SDK 发送一笔发给自身 `0x` 地址的标准 Core 交易；
- gas、`storageLimit`、epoch 和 nonce 由官方 SDK/RPC 填充，固定 `gasPrice` 仅在显式传入时覆盖；
- 回执以 `outcomeStatus === 0` 为成功。

现有进度文件格式、恢复起点、失败状态和等待策略不变。

### 6. 错误处理

- RPC 无法返回有效 `networkId` 或 `chainId` 时在发送前失败。
- Core `chainId` 必须能放入现有私钥布局的 4 字节范围，否则拒绝生成账户。
- Core SDK 返回的地址必须能转换并校验为 `0x` 20 字节地址。
- gas/storage 估算失败、交易提交失败和失败回执沿用现有重试与进度失败机制。
- `l2type=3` 缺少 `--by-contract-progress` 时输出明确错误，不回退到 XJST 的直接参数模式。

## 测试策略

测试优先覆盖分支选择、确定性派生和交易参数，不依赖真实主网资金。

- 参数校验：接受 `l2type=3`，不要求 `groupId`，by-eoa 要求进度文件。
- 兼容性：`l2type=0/1/2` 的原有分流和私钥派生结果不变。
- Core 账户：固定 `chainId + index` 产生固定私钥和合法 `0x` Core 用户地址。
- Core 初始化：正确使用 RPC 返回的 `networkId` 和 `chainId`。
- by-contract：传入标准 Core nonce、epoch、chainId、gas、gasPrice、`storageLimit` 和 value。
- by-eoa：等待充值进度后发送自转账，并按 `outcomeStatus` 判定成功或失败。
- 构建检查：TypeScript/Hardhat 编译通过。

如环境提供可用的 Core 测试 RPC、已部署 `BatchSender` 和测试私钥，再补充小批量集成验证；这些外部资源不是单元测试通过的前提。

## 涉及产物

| 产物 | 改动 |
|------|------|
| `ydyl-gen-accounts/package.json` / lockfile | 增加官方 `js-conflux-sdk` 与测试命令所需配置 |
| `ydyl-gen-accounts/scripts/2_genAccsByContract.ts` | 新增 `l2type=3` Core 运行时 |
| `ydyl-gen-accounts/scripts/2_genAccsByEoa.ts` | 新增 `l2type=3` Core 自转账 |
| `ydyl-gen-accounts/scripts/utils.ts` | 扩展 Core 回执判断和确定性账户生成 |
| `ydyl-gen-accounts/scripts/batchSenderClient.ts` | 通过 Core 适配模块接入合约 reader/writer |
| `ydyl-gen-accounts/scripts/coreSpaceClient.ts` | 封装官方 SDK 的 Core 专用能力 |
| `ydyl-gen-accounts/test/*` | Core 适配单元测试 |
| `ydyl-gen-accounts/README.md` | 增加 `l2type=3` 参数说明和用法 |

## 验收标准

- 两个目标脚本均接受 `--l2type 3`，且不会进入 ethers 或 XJST 分支。
- Core 账户使用 RPC `chainId` 确定性生成，输出为 `0x` 地址。
- by-contract 生成并提交包含 `storageLimit` 的标准 Core 交易。
- by-eoa 在对应账户已充值后提交标准 Core 自转账。
- Core 成功回执被识别为成功，失败回执不会推进成功进度。
- `l2type=0/1/2` 的既有测试和构建行为无回归。
- `scripts/3_concurrency.ts` 等非目标入口不在本次改动中。
