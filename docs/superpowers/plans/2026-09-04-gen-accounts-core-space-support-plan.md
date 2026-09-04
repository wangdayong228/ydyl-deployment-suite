# `ydyl-gen-accounts` Conflux Core Space 支持实施计划

> **面向执行代理：** 必须使用 `subagent-driven-development`（推荐）或 `executing-plans`，按任务逐项执行本计划。所有步骤使用复选框跟踪状态。

**目标：** 让 `2_genAccsByContract.ts` 和 `2_genAccsByEoa.ts` 通过新增的 `l2type=3` 使用官方 `js-conflux-sdk` 在标准 Conflux Core Space 生成账户和发送交易。

**架构：** 保留 `ethers` 的 EVM 分支和内嵌联盟版 SDK 的 XJST 分支，新增一个只依赖官方 SDK 的 `coreSpaceClient.ts` 适配层。适配层将 Core 网络发现、十六进制地址、标准交易字段、合约调用和自转账收口为现有脚本可消费的接口，两个入口脚本只负责选择运行时和维持原有进度语义。

**技术栈：** TypeScript、Node.js、Hardhat/Mocha/Chai、`ethers`、`js-conflux-sdk@^2.6.0`、内嵌 `@xjshutu/js-conflux-sdk`

## 全局约束

- spec 真理之源：`docs/superpowers/specs/2026-09-03-gen-accounts-core-space-support-spec.md`。
- `l2type=3` 表示 Core Space；`l2type=0/1/2` 的语义和输出必须保持不变。
- 官方依赖固定为 `js-conflux-sdk@^2.6.0`，不得替换或修改 `libs/js-conflux-sdk`。
- Core 的 `networkId` 和 `chainId` 必须来自目标 RPC；确定性私钥编码使用 `chainId`。
- CLI、日志、进度文件和 ABI 地址参数统一使用 `0x` 20 字节地址，不接受 CIP-37 CLI 输入。
- `l2type=3` 不使用 `groupId`；Core EOA 模式必须读取并监听 `--by-contract-progress`。
- 本次不得修改 `scripts/3_concurrency.ts`、`scripts/5_contract_status.ts`、`scripts/6_fund.ts` 或顶层流水线。
- `ydyl-gen-accounts` 是 Git 子模块：实现提交在子模块内完成，最后在父仓库提交子模块指针和计划状态。
- 所有生产代码遵循红、绿、重构顺序；每个测试必须先因缺少目标行为而失败。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `ydyl-gen-accounts/scripts/coreSpaceClient.ts` | 官方 Core SDK 的网络发现、账户地址、合约 reader/writer、自转账和回执适配 |
| `ydyl-gen-accounts/scripts/utils.ts` | 在现有确定性私钥规则上增加 Core 地址派生和 Core 回执成功判断 |
| `ydyl-gen-accounts/scripts/batchSenderClient.ts` | 将 `l2type=3` 分派给 Core 适配层，保留统一 reader/writer 接口 |
| `ydyl-gen-accounts/scripts/2_genAccsByContract.ts` | 新增 Core by-contract 运行时并传递 `networkId` |
| `ydyl-gen-accounts/scripts/2_genAccsByEoa.ts` | 新增 Core EOA 运行时并复用 by-contract 进度协调 |
| `ydyl-gen-accounts/test/coreSpaceClient.test.ts` | Core 网络、地址、标准交易字段和合约适配测试 |
| `ydyl-gen-accounts/test/genAccsCoreModes.test.ts` | 两个入口的 `l2type=3` 参数、配置和确定性批量地址测试 |
| `ydyl-gen-accounts/package.json` / `package-lock.json` | 官方 SDK 依赖和稳定的测试命令 |
| `ydyl-gen-accounts/README.md` | `l2type=3` 用法、参数和边界 |

---

### 任务 1：建立官方 Core SDK 适配层和确定性账户能力

**文件：**

- 新建：`ydyl-gen-accounts/scripts/coreSpaceClient.ts`
- 修改：`ydyl-gen-accounts/scripts/utils.ts`
- 修改：`ydyl-gen-accounts/package.json`
- 修改：`ydyl-gen-accounts/package-lock.json`
- 新建：`ydyl-gen-accounts/test/coreSpaceClient.test.ts`

**接口：**

- 产出：`CoreSpaceContext { cfx, networkId, chainId }`
- 产出：`connectCoreSpace(rpc, factory?): Promise<CoreSpaceContext>`
- 产出：`validateCoreStatus(value): CoreNetwork`
- 产出：`coreHexAddressFromPrivateKey(privateKey, networkId): string`
- 修改：`createAccountFromIndex(groupId, chainId, index, l2type, networkId?)`

- [x] **步骤 1：先写 Core 网络和账户的失败测试**

新建 `test/coreSpaceClient.test.ts`，先只加入以下测试；此时目标模块尚不存在：

```ts
import { expect } from 'chai';

import {
  connectCoreSpace,
  coreHexAddressFromPrivateKey,
  validateCoreStatus,
} from '../scripts/coreSpaceClient';
import { createAccountFromIndex, isTxReceiptSuccess } from '../scripts/utils';

const CORE_PRIVATE_KEY = '0x0000000000000000000000000000000000000000040500000000000000000001';
const CORE_HEX_ADDRESS = '0x189a5c14c344b7e69205e4e1c1a325229e0d206f';

describe('Core Space 基础适配', () => {
  it('校验 RPC 返回的 networkId 和 4 字节 chainId', () => {
    expect(validateCoreStatus({ networkId: 1, chainId: 1029 })).to.deep.equal({ networkId: 1, chainId: 1029 });
    expect(() => validateCoreStatus({ networkId: 0, chainId: 1 })).to.throw('networkId');
    expect(() => validateCoreStatus({ networkId: 1, chainId: 0x1_0000_0000 })).to.throw('chainId');
  });

  it('用官方 Core 账户规则输出 0x 用户地址', () => {
    expect(coreHexAddressFromPrivateKey(CORE_PRIVATE_KEY, 1029)).to.equal(CORE_HEX_ADDRESS);
    expect(createAccountFromIndex(0, 1029, 1n, 3, 1029)).to.deep.equal({
      privateKey: CORE_PRIVATE_KEY,
      address: CORE_HEX_ADDRESS,
    });
  });

  it('把 Core outcomeStatus=0 判定为成功', () => {
    expect(isTxReceiptSuccess(3, { outcomeStatus: 0 })).to.equal(true);
    expect(isTxReceiptSuccess(3, { outcomeStatus: 1 })).to.equal(false);
    expect(isTxReceiptSuccess(0, { status: 1 })).to.equal(true);
    expect(isTxReceiptSuccess(2, { outcomeStatus: 0 })).to.equal(true);
  });

  it('连接时开启 hex 参数并采用 RPC 网络信息', async () => {
    let received: Record<string, unknown> | undefined;
    const fake = {
      networkId: 1,
      getStatus: async () => ({ networkId: 1, chainId: 1029 }),
    };
    const context = await connectCoreSpace('http://core.invalid', async (options) => {
      received = options;
      return fake as never;
    });

    expect(received).to.deep.include({ url: 'http://core.invalid', useHexAddressInParameter: true });
    expect(context.networkId).to.equal(1);
    expect(context.chainId).to.equal(1029);
  });
});
```

- [x] **步骤 2：运行测试并确认红灯原因正确**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts
```

预期：FAIL，错误包含 `Cannot find module '../scripts/coreSpaceClient'`，证明测试确实依赖尚未实现的 Core 适配层。

- [x] **步骤 3：安装官方 SDK 并登记测试命令**

运行：

```bash
cd ydyl-gen-accounts
npm install --save 'js-conflux-sdk@^2.6.0'
```

在 `package.json` 的 `scripts` 增加：

```json
"test": "hardhat test --no-compile",
"typecheck": "tsc --noEmit"
```

确认 `package-lock.json` 根依赖包含：

```json
"js-conflux-sdk": "^2.6.0"
```

- [x] **步骤 4：实现最小 Core 网络与地址基础**

新建 `scripts/coreSpaceClient.ts`，先写入网络、转换和公共类型。转换必须验证 Core 用户地址类型位为 `0x1`：

```ts
import { Conflux, PrivateKeyAccount, address as coreAddress } from 'js-conflux-sdk';

import type {
  BatchSenderReaderLike,
  BatchSenderWriterLike,
  RuntimeTxReceipt,
} from './batchSenderClient';

export type CoreNetwork = {
  networkId: number;
  chainId: number;
};

export type CoreSpaceContext = CoreNetwork & {
  cfx: Conflux;
};

export type CoreSdkOptions = {
  url: string;
  useHexAddressInParameter: true;
};

export type CoreSdkFactory = (
  options: CoreSdkOptions,
) => Promise<Conflux>;

const MAX_CORE_CHAIN_ID = 0xffff_ffff;
const CORE_TX_MARGIN_NUMERATOR = 12n;
const CORE_TX_MARGIN_DENOMINATOR = 10n;

function requireInteger(value: unknown, name: string, min: number, max: number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} 必须是 ${min}..${max} 范围内的安全整数`);
  }
  return parsed;
}

function toBigInt(value: unknown, name: string): bigint {
  try {
    if (typeof value === 'bigint') return value;
    if (typeof value === 'number' || typeof value === 'string') return BigInt(value);
    if (value && typeof (value as { toString?: unknown }).toString === 'function') {
      return BigInt(String(value));
    }
  } catch {
    throw new Error(`${name} 无法转换为 bigint`);
  }
  throw new Error(`${name} 无法转换为 bigint`);
}

function toSafeNumber(value: unknown, name: string): number {
  const parsed = toBigInt(value, name);
  if (parsed < 0n || parsed > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`${name} 超出安全整数范围`);
  }
  return Number(parsed);
}

function addEstimateMargin(value: unknown, name: string): bigint {
  const parsed = toBigInt(value, name);
  return (parsed * CORE_TX_MARGIN_NUMERATOR + CORE_TX_MARGIN_DENOMINATOR - 1n) / CORE_TX_MARGIN_DENOMINATOR;
}

export function validateCoreStatus(value: unknown): CoreNetwork {
  const status = value as { networkId?: unknown; chainId?: unknown };
  return {
    networkId: requireInteger(status?.networkId, 'networkId', 1, Number.MAX_SAFE_INTEGER),
    chainId: requireInteger(status?.chainId, 'chainId', 0, MAX_CORE_CHAIN_ID),
  };
}

export async function connectCoreSpace(
  rpc: string,
  factory: CoreSdkFactory = async (options) => await Conflux.create(options),
): Promise<CoreSpaceContext> {
  const cfx = await factory({ url: rpc, useHexAddressInParameter: true });
  const network = validateCoreStatus(await cfx.getStatus());
  if (Number(cfx.networkId) !== network.networkId) {
    throw new Error(`SDK networkId=${String(cfx.networkId)} 与 RPC networkId=${network.networkId} 不一致`);
  }
  return { cfx, ...network };
}

export function coreHexAddressFromPrivateKey(privateKey: string, networkId: number): string {
  const checkedNetworkId = requireInteger(networkId, 'networkId', 1, Number.MAX_SAFE_INTEGER);
  const account = new PrivateKeyAccount(privateKey, checkedNetworkId);
  const decoded = coreAddress.decodeCfxAddress(account.address) as { hexAddress?: Buffer | Uint8Array };
  if (!decoded.hexAddress) throw new Error('官方 SDK 未返回 Core hexAddress');
  const result = `0x${Buffer.from(decoded.hexAddress).toString('hex')}`;
  if (!/^0x1[a-f0-9]{39}$/.test(result)) throw new Error(`无效的 Core 用户地址: ${result}`);
  return result;
}
```

- [x] **步骤 5：扩展确定性账户和回执判断**

在 `scripts/utils.ts` 引入 `coreHexAddressFromPrivateKey`，将现有两个函数改为：

```ts
import { coreHexAddressFromPrivateKey } from './coreSpaceClient';

export function isTxReceiptSuccess(
  l2type: number,
  receipt: TxReceiptLike,
): boolean {
  if (!receipt) return false;
  if (l2type === 2 || l2type === 3) {
    const outcome = normalizeReceiptStatus(receipt.outcomeStatus ?? receipt.status);
    return outcome === 0n;
  }
  const status = normalizeReceiptStatus(receipt.status);
  return status === 1n;
}

export function createAccountFromIndex(
  groupId: number,
  chainId: number,
  index: bigint,
  l2type: number = 0,
  networkId?: number,
): GeneratedAccount {
  const chainIdOrGroupId = l2type === 2 ? groupId : chainId;
  const privateKey = buildPrivateKey(chainIdOrGroupId, index);
  if (l2type === 2) {
    const account = new Account(privateKey);
    return { address: String(account.address || ''), privateKey };
  }
  if (l2type === 3) {
    if (networkId == null) throw new Error('l2type=3 时必须提供 networkId');
    return { address: coreHexAddressFromPrivateKey(privateKey, networkId), privateKey };
  }
  return { address: new ethers.Wallet(privateKey).address, privateKey };
}
```

- [x] **步骤 6：运行基础测试并确认绿灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts
npm run typecheck
```

预期：四个基础测试 PASS，类型检查 PASS。

- [x] **步骤 7：提交基础能力**

```bash
cd ydyl-gen-accounts
git add package.json package-lock.json scripts/coreSpaceClient.ts scripts/utils.ts test/coreSpaceClient.test.ts
git commit -m "feat(gen-accounts): add Core Space client foundation"
```

---

### 任务 2：实现 Core `BatchSender` reader/writer 并接入统一客户端

**文件：**

- 修改：`ydyl-gen-accounts/scripts/coreSpaceClient.ts`
- 修改：`ydyl-gen-accounts/scripts/batchSenderClient.ts`
- 修改：`ydyl-gen-accounts/test/coreSpaceClient.test.ts`

**接口：**

- 消费：任务 1 的 `CoreSpaceContext`
- 产出：`L2Type = 0 | 1 | 2 | 3`
- 产出：`getBatchSenderReader(context, address, 3)`
- 产出：`getBatchSenderWriter(context, address, 3)`

- [x] **步骤 1：先写 Core 合约参数的失败测试**

在 `test/coreSpaceClient.test.ts` 增加假 SDK 工厂和测试。测试必须验证估算余量以及发送参数里存在 `storageLimit`：

```ts
import {
  createCoreBatchSenderReader,
  createCoreBatchSenderWriter,
  type CoreSpaceContext,
} from '../scripts/coreSpaceClient';
import { getBatchSenderReader, getBatchSenderWriter } from '../scripts/batchSenderClient';

it('通过统一 reader 读取 Core 合约状态', async () => {
  const contract = {
    startAddressIndex: () => Promise.resolve(10n),
    sentCount: () => Promise.resolve(2n),
    totalCount: () => Promise.resolve(20n),
    lastAddressIndex: () => Promise.resolve(12n),
    remainCount: () => Promise.resolve(18n),
  };
  const context = {
    networkId: 1,
    chainId: 1029,
    cfx: { Contract: () => contract },
  } as unknown as CoreSpaceContext;
  const reader = getBatchSenderReader(context, '0x8000000000000000000000000000000000000001', 3);

  expect(await reader.startAddressIndex()).to.equal(10n);
  expect(await reader.sentCount()).to.equal(2n);
  expect(await reader.remainCount()).to.equal(18n);
});

it('为 Core batchSendETH 准备并发送完整标准交易字段', async () => {
  const sent: Record<string, unknown>[] = [];
  const method = {
    estimateGasAndCollateral: async () => ({ gasLimit: 100_000n, storageCollateralized: 1_000n }),
    sendTransaction: (options: Record<string, unknown>) => {
      sent.push(options);
      return Promise.resolve(`0x${'ab'.repeat(32)}`);
    },
  };
  const contract = { batchSendETH: () => method };
  const context = {
    networkId: 1,
    chainId: 1029,
    cfx: {
      Contract: () => contract,
      wallet: { addPrivateKey: () => ({ address: 'cfxtest:aasm4c231py7j34fghntcfkdt2nm9xv1tu6jd3r1s7' }) },
      advanced: { getNextUsableNonce: async () => 7n },
      getEpochNumber: async () => 99,
      getGasPrice: async () => 10n,
      getTransactionReceipt: async () => ({ epochNumber: 100, outcomeStatus: 0 }),
      getTransactionByHash: async () => ({ hash: `0x${'ab'.repeat(32)}` }),
    },
  } as unknown as CoreSpaceContext;
  const writer = getBatchSenderWriter(
    { core: context, privateKey: CORE_PRIVATE_KEY },
    '0x8000000000000000000000000000000000000001',
    3,
  );
  const batch = [CORE_HEX_ADDRESS];
  const base = await writer.prepareWindowTxParams(batch, 2n);

  expect(base).to.deep.equal({
    nonce: 7,
    gas: 120_000n,
    gasPrice: 10n,
    storageLimit: 1200,
    chainId: 1029,
    epochHeight: 99,
  });

  await writer.batchSendETH(batch, 2n, base);
  expect(sent[0]).to.deep.include({
    nonce: 7,
    gas: '120000',
    gasPrice: '10',
    storageLimit: 1200,
    chainId: 1029,
    epochHeight: 99,
    value: '2',
  });
});
```

- [x] **步骤 2：运行新增测试并确认红灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts
```

预期：FAIL，错误指出 `createCoreBatchSenderReader` / `createCoreBatchSenderWriter` 未导出或 `l2type=3` 尚未被统一客户端接受。

- [x] **步骤 3：在 Core 适配层实现合约 reader/writer**

在 `scripts/coreSpaceClient.ts` 引入 `BatchSender__factory`，并加入：

```ts
import { BatchSender__factory } from '../typechain-types';

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function waitCoreReceipt(
  context: CoreSpaceContext,
  txHash: string,
): Promise<RuntimeTxReceipt> {
  while (true) {
    const receipt = await context.cfx.getTransactionReceipt(txHash);
    if (receipt) {
      return {
        blockNumber: receipt.epochNumber == null ? null : String(receipt.epochNumber),
        status: receipt.outcomeStatus == null ? null : String(receipt.outcomeStatus),
        outcomeStatus: receipt.outcomeStatus == null ? null : String(receipt.outcomeStatus),
      };
    }
    await wait(1000);
  }
}

export function createCoreBatchSenderReader(
  context: CoreSpaceContext,
  contractAddress: string,
): BatchSenderReaderLike {
  const contract = context.cfx.Contract({
    abi: BatchSender__factory.abi,
    address: contractAddress,
  }) as any;
  return {
    startAddressIndex: async () => toBigInt(await contract.startAddressIndex(), 'startAddressIndex'),
    sentCount: async () => toBigInt(await contract.sentCount(), 'sentCount'),
    totalCount: async () => toBigInt(await contract.totalCount(), 'totalCount'),
    lastAddressIndex: async () => toBigInt(await contract.lastAddressIndex(), 'lastAddressIndex'),
    remainCount: async () => toBigInt(await contract.remainCount(), 'remainCount'),
  };
}

function requireOverride<T>(value: T | null | undefined, name: string): T {
  if (value == null) throw new Error(`Core 交易缺少 ${name}`);
  return value;
}

export function createCoreBatchSenderWriter(
  context: CoreSpaceContext,
  contractAddress: string,
  privateKey: string,
): BatchSenderWriterLike {
  const payer = context.cfx.wallet.addPrivateKey(privateKey);
  const contract = context.cfx.Contract({
    abi: BatchSender__factory.abi,
    address: contractAddress,
  }) as any;

  return {
    prepareWindowTxParams: async (batch, amountPerAddressWei) => {
      const value = amountPerAddressWei * BigInt(batch.length);
      const method = contract.batchSendETH(batch, amountPerAddressWei.toString());
      const [nonce, epochHeight, gasPrice, estimate] = await Promise.all([
        context.cfx.advanced.getNextUsableNonce(payer.address),
        context.cfx.getEpochNumber('latest_state'),
        context.cfx.getGasPrice(),
        method.estimateGasAndCollateral({ from: payer.address, value: value.toString() }, 'latest_state'),
      ]);
      return {
        nonce: toSafeNumber(nonce, 'nonce'),
        gas: addEstimateMargin(estimate.gasLimit ?? estimate.gasUsed, 'gas'),
        gasPrice: toBigInt(gasPrice, 'gasPrice'),
        storageLimit: toSafeNumber(addEstimateMargin(estimate.storageCollateralized, 'storageLimit'), 'storageLimit'),
        chainId: context.chainId,
        epochHeight: toSafeNumber(epochHeight, 'epochHeight'),
      };
    },
    batchSendETH: async (batch, amountPerAddressWei, overrides) => {
      const value = amountPerAddressWei * BigInt(batch.length);
      const method = contract.batchSendETH(batch, amountPerAddressWei.toString());
      const pending = method.sendTransaction({
        from: payer.address,
        nonce: requireOverride(overrides?.nonce, 'nonce'),
        gas: requireOverride(overrides?.gas, 'gas').toString(),
        gasPrice: requireOverride(overrides?.gasPrice, 'gasPrice').toString(),
        storageLimit: requireOverride(overrides?.storageLimit, 'storageLimit'),
        chainId: requireOverride(overrides?.chainId, 'chainId'),
        epochHeight: requireOverride(overrides?.epochHeight, 'epochHeight'),
        value: value.toString(),
      });
      const hash = String(await pending);
      return { hash, wait: () => waitCoreReceipt(context, hash) };
    },
    txExists: async (txHash) => Boolean(await context.cfx.getTransactionByHash(txHash)),
  };
}
```

- [x] **步骤 4：把 `l2type=3` 接入 `batchSenderClient.ts`**

扩展类型和连接对象：

```ts
import {
  createCoreBatchSenderReader,
  createCoreBatchSenderWriter,
  type CoreSpaceContext,
} from './coreSpaceClient';

export type L2Type = 0 | 1 | 2 | 3;

export type BatchSenderReaderConnection =
  | ethers.Provider
  | ethers.JsonRpcProvider
  | ConfluxLike
  | CoreSpaceContext;

export type BatchSenderWriterConnection =
  | ethers.Signer
  | { cfx: ConfluxLike; privateKey: string }
  | { core: CoreSpaceContext; privateKey: string };
```

在两个工厂的 `l2type===2` 判断之前分别增加：

```ts
if (l2type === 3) {
  return createCoreBatchSenderReader(connection as CoreSpaceContext, address);
}
```

```ts
if (l2type === 3) {
  const { core, privateKey } = connection as { core: CoreSpaceContext; privateKey: string };
  return createCoreBatchSenderWriter(core, address, privateKey);
}
```

部署 helper 的分支保持不变，`deployBatchSender(..., l2type=3)` 仍属于非目标；如被调用必须抛出明确的“不支持 Core 部署”错误，不能误入 ethers 分支：

```ts
if (l2type === 3) {
  throw new Error('本次不支持通过 deployBatchSender 部署 Core Space 合约');
}
```

- [x] **步骤 5：运行 Core 合约测试并确认绿灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts
npm run typecheck
```

预期：六个测试全部 PASS，类型检查 PASS。

- [x] **步骤 6：提交 Core 合约适配**

```bash
cd ydyl-gen-accounts
git add scripts/coreSpaceClient.ts scripts/batchSenderClient.ts test/coreSpaceClient.test.ts
git commit -m "feat(gen-accounts): adapt BatchSender for Core Space"
```

---

### 任务 3：接入 `2_genAccsByContract.ts` 的 Core 运行时

**文件：**

- 修改：`ydyl-gen-accounts/scripts/2_genAccsByContract.ts`
- 新建：`ydyl-gen-accounts/test/genAccsCoreModes.test.ts`

**接口：**

- 消费：`connectCoreSpace`、统一 batch reader/writer、五参数 `createAccountFromIndex`
- 产出：`validateArgs`、`buildBatchAddresses` 可直接单测
- 产出：`buildCoreRuntime(argv): Promise<RuntimeContext>`

- [x] **步骤 1：先写 by-contract 的失败测试**

新建 `test/genAccsCoreModes.test.ts`：

```ts
import { expect } from 'chai';

import {
  buildBatchAddresses,
  validateArgs as validateContractArgs,
} from '../scripts/2_genAccsByContract';

const PRIVATE_KEY = `0x${'01'.repeat(32)}`;
const BATCH_SENDER = `0x8${'0'.repeat(39)}`;

describe('gen accounts Core 模式', () => {
  it('by-contract 接受 l2type=3 且不要求 groupId', () => {
    expect(validateContractArgs({
      l2type: 3,
      groupId: 0,
      rpc: 'http://core.invalid',
      batchSender: BATCH_SENDER,
      privateKey: PRIVATE_KEY,
      n: 1,
      addressesPerTx: 1,
      amountPerAddressWei: '1',
      txQueueLimit: 1,
      dryrun: true,
      debugSentCheck: false,
    })).to.equal(true);
  });

  it('by-contract 按 Core chainId 生成 0x 地址', () => {
    expect(buildBatchAddresses(0, 1029, 1029, 1, 1, 3)).to.deep.equal([
      '0x189a5c14c344b7e69205e4e1c1a325229e0d206f',
    ]);
  });
});
```

- [x] **步骤 2：运行测试并确认红灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/genAccsCoreModes.test.ts
```

预期：FAIL，原因是 `validateArgs` / `buildBatchAddresses` 尚未导出或 `l2type=3` 尚未接受；不得出现脚本自动执行 CLI 的副作用。

- [x] **步骤 3：扩展参数、运行时上下文和地址生成**

在 `2_genAccsByContract.ts`：

```ts
import {
  connectCoreSpace,
  coreHexAddressFromPrivateKey,
  type CoreSpaceContext,
} from './coreSpaceClient';

type L2Type = 0 | 1 | 2 | 3;

type RuntimeContext = {
  l2type: L2Type;
  groupId: number;
  chainId: number;
  networkId: number;
  payerAddress: string;
  startAddressIndex: number;
  totalCount: number;
  contractReader: BatchSenderReaderLike;
  contractWriter: BatchSenderWriterLike;
  tracker: ProgressTracker;
};
```

把 `validateArgs` 和 `buildBatchAddresses` 导出；前者接受 `0/1/2/3`，后者传递 `networkId`：

```ts
export function validateArgs(args: unknown): true {
  const a = args as Args;
  if (!Number.isInteger(a.l2type) || ![0, 1, 2, 3].includes(a.l2type)) {
    throw new Error('l2type 必须为 0/1/2/3');
  }
  if (!a.rpc) throw new Error('必须提供 RPC');
  if (!/^0x[a-fA-F0-9]{40}$/.test(a.batchSender)) throw new Error('无效的 batchSender 地址');
  if (!/^0x[a-fA-F0-9]{64}$/.test(a.privateKey)) throw new Error('无效的 privateKey');
  if (!Number.isInteger(a.n) || a.n < 0) throw new Error('n 必须为非负整数（0 表示自动）');
  if (!Number.isInteger(a.addressesPerTx) || a.addressesPerTx <= 0) {
    throw new Error('addressesPerTx 必须为正整数');
  }
  if (!/^\d+$/.test(String(a.amountPerAddressWei || ''))) {
    throw new Error('amountPerAddressWei 必须为十进制整数（单位 wei）');
  }
  if (BigInt(a.amountPerAddressWei) <= 0n) throw new Error('amountPerAddressWei 必须 > 0');
  if (!Number.isInteger(a.txQueueLimit) || a.txQueueLimit <= 0) {
    throw new Error('txQueueLimit（队列中的交易数上限）必须为正整数');
  }
  if (a.gasPrice != null && String(a.gasPrice) !== '' && !/^\d+$/.test(String(a.gasPrice))) {
    throw new Error('gasPrice 必须为十进制非负整数（单位 wei）');
  }
  if (a.l2type === 2 && (!Number.isInteger(a.groupId) || a.groupId <= 0)) {
    throw new Error('l2type=2 时 groupId 必须为正整数');
  }
  return true;
}

export function buildBatchAddresses(
  groupId: number,
  chainId: number,
  networkId: number,
  batchStart: number,
  size: number,
  l2type: L2Type,
): string[] {
  return Array.from({ length: size }, (_, offset) => createAccountFromIndex(
    groupId,
    chainId,
    BigInt(batchStart + offset),
    l2type,
    networkId,
  ).address);
}
```

实现时保留 `validateArgs` 中 RPC、合约、私钥、数量、gas price 和 `groupId` 的全部现有校验，不得用注释替代。

- [x] **步骤 4：新增 `buildCoreRuntime` 并分流**

新增：

```ts
async function buildCoreRuntime(argv: Args): Promise<RuntimeContext> {
  const core = await connectCoreSpace(argv.rpc);
  const reader = getBatchSenderReader(core, argv.batchSender, 3);
  const writer = getBatchSenderWriter({ core, privateKey: argv.privateKey }, argv.batchSender, 3);
  const startAddressIndex = Number(await reader.startAddressIndex());
  const totalCount = Number(await reader.totalCount());
  const processName = resolveProcessNameFromEnv() || buildGenAccProcessName(startAddressIndex);
  const tracker = new ProgressTracker({
    processName,
    rpc: argv.rpc,
    batchSender: argv.batchSender,
    startAddressIndex,
    addressesPerTx: argv.addressesPerTx,
    totalCount,
    contractReader: reader,
  });
  return {
    l2type: 3,
    groupId: 0,
    chainId: core.chainId,
    networkId: core.networkId,
    payerAddress: coreHexAddressFromPrivateKey(argv.privateKey, core.networkId),
    startAddressIndex,
    totalCount,
    contractReader: reader,
    contractWriter: writer,
    tracker,
  };
}

async function initRuntime(argv: Args): Promise<RuntimeContext> {
  if (argv.l2type === 2) return await buildXjstRuntime(argv);
  if (argv.l2type === 3) return await buildCoreRuntime(argv);
  return await buildEvmRuntime(argv);
}
```

为 EVM 和 XJST 返回值补 `networkId: chainId` 与 `networkId: 0`。`sendRangeSequentially` 增加 `networkId` 参数，并在调用 `buildBatchAddresses` 时传入；最终示例账户调用也传入 `runtime.networkId`。

gas price 逻辑保持：只有 `l2type=2` 固定为零，Core 使用 `fixedGasPriceWei ?? windowBaseParams.gasPrice`。

- [x] **步骤 5：避免导入测试时自动运行 CLI**

将文件末尾改为：

```ts
if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
```

`derivePayerAddress` 的 Core 分支使用任意合法 `networkId=1` 生成后立即转成网络无关的 hex 地址：

```ts
if (argv.l2type === 3) {
  return coreHexAddressFromPrivateKey(argv.privateKey, 1);
}
```

- [x] **步骤 6：运行 by-contract 测试并确认绿灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/genAccsCoreModes.test.ts
npm run typecheck
```

预期：两个测试 PASS，类型检查 PASS，导入脚本时没有 CLI 日志或进程退出。

- [x] **步骤 7：提交 by-contract 适配**

```bash
cd ydyl-gen-accounts
git add scripts/2_genAccsByContract.ts test/genAccsCoreModes.test.ts
git commit -m "feat(gen-accounts): support Core Space by contract"
```

---

### 任务 4：接入 `2_genAccsByEoa.ts` 的 Core 运行时和进度协调

**文件：**

- 修改：`ydyl-gen-accounts/scripts/coreSpaceClient.ts`
- 修改：`ydyl-gen-accounts/scripts/2_genAccsByEoa.ts`
- 修改：`ydyl-gen-accounts/test/coreSpaceClient.test.ts`
- 修改：`ydyl-gen-accounts/test/genAccsCoreModes.test.ts`

**接口：**

- 消费：`CoreSpaceContext`、`createAccountFromIndex(..., networkId)`
- 产出：`sendCoreSelfTransfer(context, privateKey, gasPrice?)`
- 产出：`RunConfig.fromArgs` 对 `l2type=3` 使用 by-contract progress
- 产出：`EoaRuntime` 的 Core 发送与回执等待分支

- [x] **步骤 1：先写标准 Core 自转账失败测试**

在 `test/coreSpaceClient.test.ts` 增加：

```ts
import { Transaction, address as coreAddress } from 'js-conflux-sdk';
import { sendCoreSelfTransfer } from '../scripts/coreSpaceClient';

it('自转账签名包含官方 SDK 补齐的 storageLimit', async () => {
  let raw = '';
  const context = {
    networkId: 1029,
    chainId: 1029,
    cfx: {
      cfx: {
        populateTransaction: async (options: Record<string, unknown>) => ({
          ...options,
          nonce: 1,
          gas: 21_000,
          gasPrice: 10,
          storageLimit: 0,
          epochHeight: 100,
          chainId: 1029,
          type: 0,
        }),
      },
      sendRawTransaction: async (value: string) => {
        raw = value;
        return `0x${'cd'.repeat(32)}`;
      },
    },
  } as unknown as CoreSpaceContext;

  const hash = await sendCoreSelfTransfer(context, CORE_PRIVATE_KEY, 10n);
  const decoded = Transaction.decodeRaw(raw);
  const decodedTo = coreAddress.decodeCfxAddress(decoded.to) as { hexAddress: Buffer | Uint8Array };
  expect(hash).to.equal(`0x${'cd'.repeat(32)}`);
  expect(`0x${Buffer.from(decodedTo.hexAddress).toString('hex')}`).to.equal(CORE_HEX_ADDRESS);
  expect(BigInt(decoded.storageLimit)).to.equal(0n);
  expect(Number(decoded.chainId)).to.equal(1029);
});
```

- [x] **步骤 2：先写 EOA 配置失败测试**

在 `test/genAccsCoreModes.test.ts` 增加：

```ts
import fs from 'fs';
import os from 'os';
import path from 'path';

import {
  RunConfig,
  validateArgs as validateEoaArgs,
} from '../scripts/2_genAccsByEoa';

it('by-eoa 的 l2type=3 必须并会复用 by-contract progress', () => {
  expect(() => validateEoaArgs({
    l2type: 3,
    groupId: 0,
    rpc: '',
    byContractProgress: '',
    startAddressIndex: 0,
    totalCount: 2,
    txQueueLimit: 1,
    dryrun: true,
  })).to.throw('by-contract-progress');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gen-accounts-core-'));
  const progressPath = path.join(dir, 'by-contract.json');
  fs.writeFileSync(progressPath, JSON.stringify({
    rpc: 'http://core.invalid',
    startAddressIndex: 10,
    contracts: [{ sentCount: 2 }],
  }));

  const cfg = RunConfig.fromArgs({
    l2type: 3,
    groupId: 0,
    rpc: '',
    byContractProgress: progressPath,
    startAddressIndex: 0,
    totalCount: 2,
    txQueueLimit: 1,
    dryrun: true,
  });
  expect(cfg.rpc).to.equal('http://core.invalid');
  expect(cfg.startAddressIndex).to.equal(10);
  expect(cfg.isByContractMode()).to.equal(true);
});
```

- [x] **步骤 3：运行新增测试并确认红灯**

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts test/genAccsCoreModes.test.ts
```

预期：FAIL，原因分别是 `sendCoreSelfTransfer` 尚未导出，以及 EOA 脚本尚未接受 `l2type=3`。

- [x] **步骤 4：实现无钱包累积的 Core 自转账**

在 `coreSpaceClient.ts` 增加；每个账户直接签名并发送 raw transaction，不加入长期存活的 SDK wallet：

```ts
export async function sendCoreSelfTransfer(
  context: CoreSpaceContext,
  privateKey: string,
  gasPrice?: bigint,
): Promise<string> {
  const account = new PrivateKeyAccount(privateKey, context.networkId);
  const to = coreHexAddressFromPrivateKey(privateKey, context.networkId);
  const populated = await context.cfx.cfx.populateTransaction({
    from: account.address,
    to,
    value: 0,
    ...(gasPrice == null ? {} : { gasPrice: gasPrice.toString() }),
  });
  if (populated.storageLimit == null) throw new Error('Core 自转账缺少 storageLimit');
  if (populated.chainId == null) throw new Error('Core 自转账缺少 chainId');
  const signed = await account.signTransaction(populated);
  return String(await context.cfx.sendRawTransaction(signed.serialize()));
}
```

- [x] **步骤 5：扩展 EOA 参数和配置语义**

在 `2_genAccsByEoa.ts`：

```ts
import {
  connectCoreSpace,
  sendCoreSelfTransfer,
  waitCoreReceipt,
  type CoreSpaceContext,
} from './coreSpaceClient';

type L2Type = 0 | 1 | 2 | 3;
```

导出 `Args`、`RunConfig` 和 `validateArgs`。以下位置把 Core 与 EVM 一样归入 progress 模式：

```ts
isByContractMode(): boolean {
  return this.l2type === 0 || this.l2type === 1 || this.l2type === 3;
}
```

```ts
if (argv.l2type === 0 || argv.l2type === 1 || argv.l2type === 3) {
  const bc = ByContractProgressWatcher.readOnce(byContractProgressPath);
  const startAddressIndex = ByContractProgressWatcher.requireStartAddressIndex(bc, byContractProgressPath);
  const sentCount = ByContractProgressWatcher.requireSentCount(bc, byContractProgressPath);
  return new RunConfig({
    l2type: argv.l2type,
    groupId: argv.groupId,
    rpc: bc.rpc,
    byContractProgressPath,
    startAddressIndex,
    byContractSentCount: sentCount,
    targetAccountCount: argv.totalCount,
    gasPrice: argv.gasPrice,
    txQueueLimit: argv.txQueueLimit,
    dryrun: argv.dryrun,
  });
}
```

参数校验接受 `0/1/2/3`，并要求 `0/1/3` 提供 `by-contract-progress`；帮助文本和注释同步写明 `3` 的语义。

- [x] **步骤 6：扩展 `EoaRuntime`**

给 `EoaRuntime` 增加 `core?: CoreSpaceContext`、`networkId: number`，并新增构建分支：

```ts
if (cfg.l2type === 3) {
  const core = await connectCoreSpace(cfg.rpc);
  return new EoaRuntime({
    cfg,
    core,
    chainId: core.chainId,
    networkId: core.networkId,
  });
}
```

EVM 使用 `networkId=chainId`，XJST 使用 `networkId=0`。发送和等待分支加入：

```ts
case 3:
  return await sendCoreSelfTransfer(this.core!, privateKey, fixedGasPrice);
```

```ts
} else if (this.cfg.l2type === 3) {
  const receipt = await waitCoreReceipt(this.core!, txHash);
  blocknumber = receipt.blockNumber;
  status = receipt.outcomeStatus;
```

账户恢复调用改为：

```ts
const { privateKey } = createAccountFromIndex(
  cfg.groupId,
  runtime.chainId,
  BigInt(idx),
  cfg.l2type,
  runtime.networkId,
);
```

原来的 `if (runtime.chainId === 0 && idx === 0)` 改为 `if (cfg.l2type === 2 && idx === 0)`，避免 Core 私网被错误套用 XJST 特例。

- [x] **步骤 7：增加 main guard 并跑绿灯**

将 `2_genAccsByEoa.ts` 末尾改为：

```ts
if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
```

运行：

```bash
cd ydyl-gen-accounts
npx hardhat test --no-compile test/coreSpaceClient.test.ts test/genAccsCoreModes.test.ts
npm run typecheck
```

预期：全部测试 PASS，类型检查 PASS。

- [x] **步骤 8：提交 EOA 适配**

```bash
cd ydyl-gen-accounts
git add scripts/coreSpaceClient.ts scripts/2_genAccsByEoa.ts test/coreSpaceClient.test.ts test/genAccsCoreModes.test.ts
git commit -m "feat(gen-accounts): support Core Space by EOA"
```

---

### 任务 5：文档、回归验证和父仓库一致性收尾

**文件：**

- 修改：`ydyl-gen-accounts/README.md`
- 修改：`docs/superpowers/plans/2026-09-04-gen-accounts-core-space-support-plan.md`
- 修改：`docs/superpowers/INDEX.md`
- 修改：父仓库的 `ydyl-gen-accounts` 子模块指针

**接口：**

- 消费：任务 1-4 的最终 CLI 行为
- 产出：可执行的 Core 示例、完整验证记录、spec/plan/代码一致状态

- [x] **步骤 1：更新 README**

在两个目标脚本章节明确加入：

```markdown
- `--l2type=3`：Conflux Core Space，使用官方 `js-conflux-sdk`；地址统一传递和输出为 `0x`。
- Core 的 `networkId`、`chainId`、epoch、gas 和 `storageLimit` 从 RPC 获取；`--gasPrice` 仅作为可选覆盖。
- `2_genAccsByEoa.ts --l2type=3` 必须提供 `--by-contract-progress`，并等待对应 by-contract 充值进度。
```

加入可直接替换参数的示例：

```bash
ts-node scripts/2_genAccsByContract.ts \
  --l2type 3 \
  --rpc <CORE_RPC> \
  --batchSender <0x_BATCH_SENDER_ADDRESS> \
  --privateKey <PAYER_PRIVATE_KEY> \
  --n 1000

ts-node scripts/2_genAccsByEoa.ts \
  --l2type 3 \
  --by-contract-progress output/gen-acc-0.by-contract.json \
  --totalCount 1000
```

同时声明 `3_concurrency.ts` 尚未支持 `l2type=3`，Core 模式本次直接运行两个目标脚本。

- [x] **步骤 2：运行完整自动化验证**

依次运行：

```bash
cd ydyl-gen-accounts
npm test
npm run typecheck
npm run build
git diff --check
```

预期：测试全部 PASS，TypeScript 无错误，Hardhat 编译成功，diff 无空白错误。

- [x] **步骤 3：检查范围和兼容性**

运行：

```bash
cd ydyl-gen-accounts
git diff HEAD~4 --name-only
git status --short
```

预期：只出现本计划文件结构表列出的子模块文件；`scripts/3_concurrency.ts`、`scripts/5_contract_status.ts`、`scripts/6_fund.ts` 未修改。人工核对 `l2type=2` 仍引用 `../libs/js-conflux-sdk` 且零 gas 分支未改变。

- [x] **步骤 4：提交子模块 README**

```bash
cd ydyl-gen-accounts
git add README.md
git commit -m "docs(gen-accounts): document Core Space mode"
```

- [x] **步骤 5：执行完成前验证技能链**

依次使用：

```text
pre-verification-check
verification-before-completion
consistency-check
post-verification-check
```

检查内容：

- spec 的目标、非目标、错误处理、测试策略和验收标准都有对应代码或测试；
- 本计划所有完成项有命令证据；
- `docs/superpowers/INDEX.md` 的计划状态更新为“已完成”；
- spec、plan、README、实现和测试对 `l2type=3`、`0x` 地址、双 SDK 隔离的描述一致。

- [x] **步骤 6：提交父仓库收尾**

在父仓库更新本计划所有已完成复选框和 INDEX 状态，然后运行：

```bash
git add ydyl-gen-accounts docs/superpowers/INDEX.md docs/superpowers/plans/2026-09-04-gen-accounts-core-space-support-plan.md
git commit -m "feat: support Core Space account generation"
git status --short --branch
```

预期：父仓库提交记录包含新的子模块指针、已完成计划和索引状态；工作树干净。
