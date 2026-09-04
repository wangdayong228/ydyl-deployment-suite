# `ydyl-gen-accounts` Core BatchSender 单合约部署实施计划

> **面向执行代理：** 必须使用 `subagent-driven-development`（推荐）或 `executing-plans`，按任务逐项执行本计划。所有步骤使用复选框跟踪状态。

**目标：** 让 `scripts/1_deployBatchSender.ts --l2type 3` 使用官方 `js-conflux-sdk` 在 Conflux Core Space 部署单个 `BatchSender`，经回执和链上状态双重校验后输出 `0x` 合约地址。

**架构：** Core 部署交易全部收口到 `coreSpaceClient.ts`，共享 `batchSenderClient.ts` 只读取 artifact、连接 Core RPC 并完成 `l2type` 分派，CLI 入口只负责参数校验和选择 Core/Hardhat 执行器。Core 交易显式携带 RPC `status.chainId`、nonce、epoch、gasPrice、gas、`storageLimit` 和 `value=0`，成功回执后再读回构造参数。

**技术栈：** TypeScript、Node.js、Hardhat/Mocha/Chai、`ethers`、`js-conflux-sdk@^2.6.0`、Yargs

## 全局约束

- spec 真理之源：`docs/superpowers/specs/2026-09-03-gen-accounts-core-space-support-spec.md`。
- 只增加 Core 单合约部署；不得修改 `scripts/3_concurrency.ts`、`scripts/5_contract_status.ts`、`scripts/6_fund.ts` 或顶层流水线。
- Core 部署使用官方 `js-conflux-sdk@^2.6.0`；不得修改或用于 Core 的 `libs/js-conflux-sdk`。
- Core `networkId` 和 `chainId` 必须来自目标 RPC；部署交易的 `chainId` 必须显式使用 RPC `status.chainId`。
- CLI 和部署结果统一使用 `0x` 地址；成功结果必须是小写 `0x` Core 合约地址。
- 部署交易 `value` 固定为 `0`；gas 和 `storageLimit` 使用 RPC 估算值加 20% 向上取整余量。
- 回执失败、`contractCreated` 缺失或部署后 `startAddressIndex` / `totalCount` 不匹配时不得返回地址。
- 不传 `--l2type 3` 时，保留 `scripts/1_deployBatchSender.ts` 现有 Hardhat/ethers 行为和默认构造参数 `100000, 200000`。
- `ydyl-gen-accounts` 是 Git 子模块：生产代码和测试提交在子模块完成，父仓库只提交 plan、INDEX、spec 一致性和子模块指针。
- 所有生产代码遵循红、绿、重构顺序；每个新增行为必须先由测试证明会失败。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `ydyl-gen-accounts/scripts/coreSpaceClient.ts` | 校验 Core artifact/地址，准备并发送标准部署交易，等待回执并读回状态 |
| `ydyl-gen-accounts/scripts/batchSenderClient.ts` | `l2type=3` 时读取 artifact、连接 Core RPC 并调用 Core 部署原语 |
| `ydyl-gen-accounts/scripts/1_deployBatchSender.ts` | Core CLI 参数校验与 Core/Hardhat 路由；避免 Core 路径提前加载 Hardhat |
| `ydyl-gen-accounts/test/coreSpaceClient.test.ts` | Core 部署字段、估算余量、地址、回执和链上读回测试 |
| `ydyl-gen-accounts/test/deployBatchSenderCore.test.ts` | 单合约部署 CLI 校验和执行器分派测试 |
| `ydyl-gen-accounts/README.md` | Core BatchSender 编译、部署和账户生成的端到端示例 |
| `docs/superpowers/INDEX.md` | 新部署计划状态 |
| `docs/superpowers/plans/2026-09-04-gen-accounts-core-space-batch-sender-deploy-plan.md` | 任务状态和验证记录 |

---

### 任务 1：实现可验证的 Core 部署原语

**文件：**

- 修改：`ydyl-gen-accounts/test/coreSpaceClient.test.ts`
- 修改：`ydyl-gen-accounts/scripts/coreSpaceClient.ts`

**接口：**

- 产出：`CoreContractArtifact { abi: readonly unknown[] | unknown[]; bytecode: string }`
- 产出：`normalizeCoreContractAddress(value: unknown): string`
- 产出：`deployCoreBatchSender(context, privateKey, artifact, startAddressIndex, totalCount): Promise<string>`
- 复用：`CoreSpaceContext`、`createCoreBatchSenderReader`、20% gas/storage 余量算法

- [x] **步骤 1：先写成功交易字段和地址规范化测试**

在 `test/coreSpaceClient.test.ts` 中导入新接口，并增加一个可观测构造参数、估算参数、发送参数和读回值的 fake Core context：

```ts
import {
  deployCoreBatchSender,
  normalizeCoreContractAddress,
} from '../scripts/coreSpaceClient';

const CORE_CONTRACT = `0x8${'0'.repeat(38)}1`;

function createDeployHarness(overrides: {
  outcomeStatus?: number;
  contractCreated?: string | null;
  actualStart?: bigint;
  actualTotal?: bigint;
  estimateError?: string;
} = {}) {
  const calls: Record<string, unknown> = {};
  const method = {
    estimateGasAndCollateral: async (options: Record<string, unknown>, epoch: string) => {
      calls.estimate = { options, epoch };
      if (overrides.estimateError) throw new Error(overrides.estimateError);
      return { gasLimit: 100_001n, storageCollateralized: 1_001n };
    },
    sendTransaction: (options: Record<string, unknown>) => {
      calls.sent = options;
      return {
        executed: async () => ({
          outcomeStatus: overrides.outcomeStatus ?? 0,
          contractCreated: overrides.contractCreated === undefined ? CORE_CONTRACT : overrides.contractCreated,
        }),
      };
    },
  };
  const reader = {
    startAddressIndex: async () => overrides.actualStart ?? 10n,
    totalCount: async () => overrides.actualTotal ?? 20n,
  };
  const cfx = {
    wallet: { addPrivateKey: () => ({ address: 'cfxtest:aasm4c231py7j34fghntcfkdt2nm9xv1tu6jd3r1s7' }) },
    advanced: { getNextUsableNonce: async () => 7n },
    getEpochNumber: async () => 99,
    getGasPrice: async () => 10n,
    Contract: (options: { bytecode?: string }) => options.bytecode
      ? {
          constructor: (start: number, total: number) => {
            calls.constructorArgs = [start, total];
            return method;
          },
        }
      : reader,
  };
  return {
    calls,
    context: { networkId: 1, chainId: 1029, cfx } as unknown as CoreSpaceContext,
  };
}

it('部署 Core BatchSender 时显式发送完整标准交易字段', async () => {
  const { calls, context } = createDeployHarness();
  const address = await deployCoreBatchSender(
    context,
    CORE_PRIVATE_KEY,
    { abi: [], bytecode: '0x6000' },
    10,
    20,
  );

  expect(address).to.equal(CORE_CONTRACT);
  expect(calls.constructorArgs).to.deep.equal([10, 20]);
  expect(calls.estimate).to.deep.equal({
    options: { from: 'cfxtest:aasm4c231py7j34fghntcfkdt2nm9xv1tu6jd3r1s7', value: '0' },
    epoch: 'latest_state',
  });
  expect(calls.sent).to.deep.include({
    nonce: 7,
    gas: '120002',
    gasPrice: '10',
    storageLimit: 1202,
    chainId: 1029,
    epochHeight: 99,
    value: '0',
  });
});

it('把 CIP-37 和 0x Core 合约地址统一成小写 0x', () => {
  const bytes = Buffer.from(CORE_CONTRACT.slice(2), 'hex');
  const cip37 = coreAddress.encodeCfxAddress(bytes, 1);
  expect(normalizeCoreContractAddress(cip37)).to.equal(CORE_CONTRACT);
  expect(normalizeCoreContractAddress(CORE_CONTRACT.toUpperCase().replace('0X', '0x'))).to.equal(CORE_CONTRACT);
});
```

- [x] **步骤 2：先写不可恢复失败和读回校验测试**

继续在同一 `describe` 中增加失败矩阵；每个分支都必须在返回地址前失败：

```ts
async function captureError(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return '';
  } catch (error) {
    return String(error);
  }
}

it('拒绝空 bytecode 和非 Core 合约地址', async () => {
  const { context } = createDeployHarness();
  expect(await captureError(deployCoreBatchSender(
    context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x' }, 10, 20,
  ))).to.include('bytecode');
  expect(() => normalizeCoreContractAddress(CORE_HEX_ADDRESS)).to.throw('Core 合约地址');
});

it('拒绝失败回执和缺失 contractCreated 的回执', async () => {
  const failed = createDeployHarness({ outcomeStatus: 1 });
  expect(await captureError(deployCoreBatchSender(
    failed.context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x6000' }, 10, 20,
  ))).to.include('outcomeStatus');

  const missing = createDeployHarness({ contractCreated: null });
  expect(await captureError(deployCoreBatchSender(
    missing.context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x6000' }, 10, 20,
  ))).to.include('contractCreated');
});

it('gas 和 storage 估算失败时不发送部署交易', async () => {
  const unavailable = createDeployHarness({ estimateError: 'estimate unavailable' });
  expect(await captureError(deployCoreBatchSender(
    unavailable.context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x6000' }, 10, 20,
  ))).to.include('estimate unavailable');
  expect(unavailable.calls.sent).to.equal(undefined);
});

it('部署后构造参数读回不一致时拒绝返回地址', async () => {
  const wrongStart = createDeployHarness({ actualStart: 11n });
  expect(await captureError(deployCoreBatchSender(
    wrongStart.context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x6000' }, 10, 20,
  ))).to.include('startAddressIndex');

  const wrongTotal = createDeployHarness({ actualTotal: 21n });
  expect(await captureError(deployCoreBatchSender(
    wrongTotal.context, CORE_PRIVATE_KEY, { abi: [], bytecode: '0x6000' }, 10, 20,
  ))).to.include('totalCount');
});
```

- [x] **步骤 3：运行测试并确认红灯原因正确**

运行：

```bash
cd ydyl-gen-accounts
env PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  npx hardhat test --no-compile test/coreSpaceClient.test.ts
```

预期：FAIL，错误明确指出 `deployCoreBatchSender` 或 `normalizeCoreContractAddress` 尚未导出；不得因测试语法或 Hardhat 配置失败。

- [x] **步骤 4：实现地址、artifact 和部署交易校验**

在 `scripts/coreSpaceClient.ts` 中复用现有 `toBigInt`、`toSafeNumber`、`addEstimateMargin`，加入以下接口。实现必须在创建交易前验证 artifact 和构造参数：

```ts
export type CoreContractArtifact = {
  abi: readonly unknown[] | unknown[];
  bytecode: string;
};

export function normalizeCoreContractAddress(value: unknown): string {
  const raw = String(value ?? '').trim();
  let hex: string;
  if (/^0x[0-9a-fA-F]{40}$/.test(raw)) {
    hex = raw.toLowerCase();
  } else {
    try {
      const decoded = coreAddress.decodeCfxAddress(raw) as { hexAddress?: Buffer | Uint8Array };
      if (!decoded.hexAddress) throw new Error('missing hexAddress');
      hex = `0x${Buffer.from(decoded.hexAddress).toString('hex')}`;
    } catch {
      throw new Error(`无效的 Core 合约地址: ${raw}`);
    }
  }
  if (!/^0x8[0-9a-f]{39}$/.test(hex)) {
    throw new Error(`无效的 Core 合约地址: ${raw}`);
  }
  return hex;
}

export async function deployCoreBatchSender(
  context: CoreSpaceContext,
  privateKey: string,
  artifact: CoreContractArtifact,
  startAddressIndex: number,
  totalCount: number,
): Promise<string> {
  const start = requireInteger(startAddressIndex, 'startAddressIndex', 0, Number.MAX_SAFE_INTEGER);
  const total = requireInteger(totalCount, 'totalCount', 1, Number.MAX_SAFE_INTEGER);
  if (!Array.isArray(artifact?.abi)) throw new Error('Core artifact abi 必须是数组');
  if (!/^0x(?:[0-9a-fA-F]{2})+$/.test(String(artifact?.bytecode || ''))) {
    throw new Error('Core artifact bytecode 必须是非空十六进制字节串');
  }

  const deployer = context.cfx.wallet.addPrivateKey(privateKey);
  const contract = context.cfx.Contract({ abi: artifact.abi as any, bytecode: artifact.bytecode }) as any;
  if (typeof contract.constructor !== 'function') throw new Error('Core BatchSender constructor 不存在');
  const method = contract.constructor(start, total);
  const [nonce, epochHeight, gasPrice, estimate] = await Promise.all([
    context.cfx.advanced.getNextUsableNonce(deployer.address),
    context.cfx.getEpochNumber('latest_state'),
    context.cfx.getGasPrice(),
    method.estimateGasAndCollateral({ from: deployer.address, value: '0' }, 'latest_state'),
  ]);
  const pending = method.sendTransaction({
    from: deployer.address,
    nonce: toSafeNumber(nonce, 'nonce'),
    gas: addEstimateMargin(estimate.gasLimit ?? estimate.gasUsed, 'gas').toString(),
    gasPrice: toBigInt(gasPrice, 'gasPrice').toString(),
    storageLimit: toSafeNumber(addEstimateMargin(estimate.storageCollateralized, 'storageLimit'), 'storageLimit'),
    chainId: context.chainId,
    epochHeight: toSafeNumber(epochHeight, 'epochHeight'),
    value: '0',
  });
  const receipt = await pending.executed();
  if (Number(receipt?.outcomeStatus) !== 0) {
    throw new Error(`Core 部署回执失败: outcomeStatus=${String(receipt?.outcomeStatus)}`);
  }
  if (!receipt?.contractCreated) throw new Error('Core 部署回执缺少 contractCreated');
  const address = normalizeCoreContractAddress(receipt.contractCreated);
  const reader = createCoreBatchSenderReader(context, address);
  const [actualStart, actualTotal] = await Promise.all([
    reader.startAddressIndex(),
    reader.totalCount(),
  ]);
  if (actualStart !== BigInt(start)) throw new Error(`Core 部署后 startAddressIndex 不一致: ${actualStart}`);
  if (actualTotal !== BigInt(total)) throw new Error(`Core 部署后 totalCount 不一致: ${actualTotal}`);
  return address;
}
```

- [x] **步骤 5：运行 Core 适配测试并确认绿灯**

运行步骤 3 的同一命令。

预期：`Core Space 基础适配` 下原有 7 项和新增部署测试全部 PASS；发送参数中的 `chainId` 为 `1029`，不是 fake context 的 `networkId=1`。

- [x] **步骤 6：提交 Core 部署原语**

```bash
cd ydyl-gen-accounts
git add scripts/coreSpaceClient.ts test/coreSpaceClient.test.ts
git commit -m "feat(gen-accounts): add Core BatchSender deployment"
```

---

### 任务 2：接入共享部署 helper 和单合约 CLI

**文件：**

- 修改：`ydyl-gen-accounts/scripts/batchSenderClient.ts`
- 修改：`ydyl-gen-accounts/scripts/1_deployBatchSender.ts`
- 新建：`ydyl-gen-accounts/test/deployBatchSenderCore.test.ts`

**接口：**

- 修改：`deployBatchSender(..., l2type=3): Promise<string>` 读取 artifact 并调用 `deployCoreBatchSender`
- 产出：`DeployArgs { l2type, rpc, privateKey, artifact, startAddressIndex, totalCount }`
- 产出：`validateDeployArgs(args): true`
- 产出：`runDeploy(args, dependencies?): Promise<string>`
- 保留：不传 `--l2type 3` 时动态加载 Hardhat 并调用原有 ethers 部署路径

- [x] **步骤 1：先写 CLI 参数和分派失败测试**

新建 `test/deployBatchSenderCore.test.ts`：

```ts
import { expect } from 'chai';

import {
  runDeploy,
  validateDeployArgs,
  type DeployArgs,
} from '../scripts/1_deployBatchSender';

const PRIVATE_KEY = `0x${'01'.repeat(32)}`;
const CORE_CONTRACT = `0x8${'0'.repeat(38)}1`;
const CORE_ARGS: DeployArgs = {
  l2type: 3,
  rpc: 'http://core.invalid',
  privateKey: PRIVATE_KEY,
  artifact: '/tmp/BatchSender.json',
  startAddressIndex: 10,
  totalCount: 20,
};

describe('Core BatchSender 部署 CLI', () => {
  it('Core 模式要求 rpc、私钥和有效构造参数', () => {
    expect(validateDeployArgs(CORE_ARGS)).to.equal(true);
    expect(() => validateDeployArgs({ ...CORE_ARGS, rpc: '' })).to.throw('rpc');
    expect(() => validateDeployArgs({ ...CORE_ARGS, privateKey: '0x01' })).to.throw('privateKey');
    expect(() => validateDeployArgs({ ...CORE_ARGS, startAddressIndex: -1 })).to.throw('startAddressIndex');
    expect(() => validateDeployArgs({ ...CORE_ARGS, totalCount: 0 })).to.throw('totalCount');
  });

  it('Core 模式把精确参数分派给共享 deployBatchSender', async () => {
    let received: unknown[] = [];
    let legacyCalled = false;
    const result = await runDeploy(CORE_ARGS, {
      deployBatchSender: async (...args: unknown[]) => {
        received = args;
        return CORE_CONTRACT;
      },
      deployWithHardhat: async () => {
        legacyCalled = true;
        return '0xlegacy';
      },
    });
    expect(result).to.equal(CORE_CONTRACT);
    expect(received).to.deep.equal([
      CORE_ARGS.rpc,
      CORE_ARGS.privateKey,
      CORE_ARGS.artifact,
      10,
      20,
      1,
      3,
    ]);
    expect(legacyCalled).to.equal(false);
  });

  it('默认模式保留 Hardhat 部署路径', async () => {
    let coreCalled = false;
    let legacyArgs: number[] = [];
    const result = await runDeploy({ ...CORE_ARGS, l2type: 0, rpc: '', privateKey: '' }, {
      deployBatchSender: async () => {
        coreCalled = true;
        return CORE_CONTRACT;
      },
      deployWithHardhat: async (start, total) => {
        legacyArgs = [start, total];
        return '0xlegacy';
      },
    });
    expect(result).to.equal('0xlegacy');
    expect(legacyArgs).to.deep.equal([10, 20]);
    expect(coreCalled).to.equal(false);
  });
});
```

- [x] **步骤 2：运行 CLI 测试并确认红灯原因正确**

```bash
cd ydyl-gen-accounts
env PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  npx hardhat test --no-compile test/deployBatchSenderCore.test.ts
```

预期：FAIL，错误指出 `runDeploy`、`validateDeployArgs` 或 `DeployArgs` 尚未导出；不得因为导入脚本而自动开始部署。

- [x] **步骤 3：把共享 helper 的 `l2type=3` 分支接到 Core 适配层**

在 `scripts/batchSenderClient.ts` 导入 `connectCoreSpace`、`deployCoreBatchSender` 和 `CoreContractArtifact`，把现有拒绝分支替换为：

```ts
if (l2type === 3) {
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8')) as CoreContractArtifact;
  const context = await connectCoreSpace(rpc);
  return deployCoreBatchSender(context, deployerKey, artifact, startAddressIndex, totalCount);
}
```

不得修改后续 `l2type=2` 的 XJST 零 gas 分支或 `l2type=0/1` 的 ethers 分支。

- [x] **步骤 4：实现可测试的 CLI 校验和执行器分派**

重写 `scripts/1_deployBatchSender.ts` 的入口结构，顶层不得静态导入 `hardhat` 或 `hookHardhat`。加入 Yargs 参数解析和以下可测试接口：

```ts
export type DeployArgs = {
  l2type: 0 | 1 | 3;
  rpc: string;
  privateKey: string;
  artifact: string;
  startAddressIndex: number;
  totalCount: number;
};

type DeployRunner = typeof deployBatchSender;
export type DeployDependencies = {
  deployBatchSender: DeployRunner;
  deployWithHardhat: (startAddressIndex: number, totalCount: number) => Promise<string>;
};

export function validateDeployArgs(args: DeployArgs): true {
  if (![0, 1, 3].includes(args.l2type)) throw new Error('l2type 必须为 0/1/3');
  if (!Number.isSafeInteger(args.startAddressIndex) || args.startAddressIndex < 0) {
    throw new Error('startAddressIndex 必须为非负安全整数');
  }
  if (!Number.isSafeInteger(args.totalCount) || args.totalCount <= 0) {
    throw new Error('totalCount 必须为正安全整数');
  }
  if (args.l2type === 3) {
    if (!args.rpc.trim()) throw new Error('l2type=3 时必须提供 rpc');
    if (!/^0x[0-9a-fA-F]{64}$/.test(args.privateKey)) {
      throw new Error('l2type=3 时 privateKey 必须是 0x 加 64 位十六进制');
    }
    if (!args.artifact.trim()) throw new Error('l2type=3 时必须提供 artifact');
  }
  return true;
}

async function deployWithHardhat(startAddressIndex: number, totalCount: number): Promise<string> {
  const [{ ethers }, { enableByEnv }] = await Promise.all([
    import('hardhat'),
    import('./hookHardhat'),
  ]);
  enableByEnv();
  const factory = await ethers.getContractFactory('BatchSender');
  const contract = await factory.deploy(startAddressIndex, totalCount);
  await contract.waitForDeployment();
  return await contract.getAddress();
}

export async function runDeploy(
  args: DeployArgs,
  dependencies: DeployDependencies = {
    deployBatchSender,
    deployWithHardhat,
  },
): Promise<string> {
  validateDeployArgs(args);
  if (args.l2type === 3) {
    return dependencies.deployBatchSender(
      args.rpc,
      args.privateKey,
      args.artifact,
      args.startAddressIndex,
      args.totalCount,
      1,
      3,
    );
  }
  return dependencies.deployWithHardhat(args.startAddressIndex, args.totalCount);
}
```

`parseArgs()` 的默认值固定为：

```ts
l2type: Number(process.env.L2TYPE || 0)
rpc: process.env.RPC || process.env.RPC_URL || ''
privateKey: process.env.PRIVATE_KEY || ''
artifact: path.resolve(__dirname, '../artifacts/contracts/batchSender.sol/BatchSender.json')
startAddressIndex: Number(process.env.START_ADDRESS_INDEX || 100000)
totalCount: Number(process.env.TOTAL_COUNT || 200000)
```

入口必须使用 main guard，并只在成功时输出最终地址：

```ts
if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
```

- [x] **步骤 5：运行 CLI 测试、Core 测试和类型检查**

```bash
cd ydyl-gen-accounts
env PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  npx hardhat test --no-compile test/deployBatchSenderCore.test.ts test/coreSpaceClient.test.ts
npm run typecheck
```

预期：全部 PASS；导入 `1_deployBatchSender.ts` 不加载 Hardhat 配置、不访问 RPC、不发送交易。

- [x] **步骤 6：提交 helper 和 CLI**

```bash
cd ydyl-gen-accounts
git add scripts/batchSenderClient.ts scripts/1_deployBatchSender.ts test/deployBatchSenderCore.test.ts
git commit -m "feat(gen-accounts): expose Core BatchSender deploy CLI"
```

---

### 任务 3：文档、回归验证和父仓库一致性收尾

**文件：**

- 修改：`ydyl-gen-accounts/README.md`
- 修改：`docs/superpowers/INDEX.md`
- 修改：`docs/superpowers/plans/2026-09-04-gen-accounts-core-space-batch-sender-deploy-plan.md`
- 修改：父仓库 `ydyl-gen-accounts` 子模块指针

**接口：**

- 消费：任务 1-2 的 Core 单合约部署 CLI
- 产出：从编译、部署到 by-contract/by-eoa 的可执行测试网流程和完整验证记录

- [x] **步骤 1：更新 README 的 Core 部署说明**

把原有“本脚本不负责在 Core Space 部署 `BatchSender`”改为单合约部署命令，并明确 `3_concurrency.ts` 仍不支持 Core：

````markdown
### Conflux Core Space：部署 BatchSender

Core 模式先编译 artifact，再使用官方 `js-conflux-sdk` 部署单个合约：

```bash
npm run build

npx ts-node scripts/1_deployBatchSender.ts \
  --l2type 3 \
  --rpc "$CORE_RPC" \
  --privateKey "$PRIVATE_KEY" \
  --startAddressIndex 0 \
  --totalCount 10
```

部署交易会从 RPC 获取 chainId、nonce、epoch、gasPrice、gas 和 storageLimit；成功回执后读回构造参数，最终输出 `0x` 合约地址。部署账户必须有足够 CFX 支付 gas 和存储抵押。

`3_concurrency.ts` 尚未支持 `l2type=3`，Core 多合约部署、付款账户充值和 PM2 编排不在当前范围内。
````

原有 by-contract 示例继续使用该命令输出的 `0x` 地址，不再要求用户在仓库外自行部署。

- [x] **步骤 2：运行完整自动化验证**

```bash
cd ydyl-gen-accounts
env PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 npm test
npm run typecheck
env PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 npm run build
git diff --check
```

预期：所有测试 PASS，TypeScript 无错误，Hardhat 编译成功，diff 无空白错误。不得使用真实资金私钥执行自动化测试。

- [x] **步骤 3：执行可选测试网小额 smoke test**

只有环境明确提供已充值的 `CORE_RPC` 和 `PRIVATE_KEY` 时执行：

```bash
cd ydyl-gen-accounts
npm run build
npx ts-node scripts/1_deployBatchSender.ts \
  --l2type 3 \
  --rpc "$CORE_RPC" \
  --privateKey "$PRIVATE_KEY" \
  --startAddressIndex 0 \
  --totalCount 10
```

预期：输出一个 `0x8` 开头的 20 字节合约地址；日志显示成功回执和读回的 `startAddressIndex=0`、`totalCount=10`。缺少已充值测试账户时明确记录“未执行外部 smoke test”，不得改用主网私钥或自行发送交易。

执行记录：当前环境未同时提供 `CORE_RPC` 与已充值 `PRIVATE_KEY`，因此未执行外部 smoke test，未发送真实交易。

- [x] **步骤 4：检查范围和兼容性**

```bash
cd ydyl-gen-accounts
git diff e914cb6..HEAD --name-only
git status --short
```

预期：本阶段新增改动只涉及本计划文件结构列出的子模块文件；`scripts/3_concurrency.ts`、`scripts/5_contract_status.ts`、`scripts/6_fund.ts` 未修改。人工核对 `l2type=2` 部署仍引用 `../libs/js-conflux-sdk` 且保持零 gas 参数，默认 `1_deployBatchSender.ts` 仍部署 `100000, 200000`。

- [x] **步骤 5：提交子模块 README**

```bash
cd ydyl-gen-accounts
git add README.md
git commit -m "docs(gen-accounts): document Core BatchSender deployment"
```

- [x] **步骤 6：执行完成前验证技能链**

依次使用：

```text
pre-verification-check
verification-before-completion
consistency-check
post-verification-check
```

检查内容：

- spec 的 Core 单合约部署目标、非目标、交易字段、错误处理和验收标准都有对应代码或测试；
- 部署使用 RPC `status.chainId`，而不是 SDK 自动补充的 `networkId`；
- 测试包含成功字段、20% 余量、失败回执、缺失地址、地址类型和部署后读回不一致；
- README、CLI help、代码和测试对默认值、必填参数及 `0x` 输出描述一致；
- 本计划所有完成项有命令证据，INDEX 状态更新为“已完成”。

- [x] **步骤 7：提交父仓库收尾**

在父仓库勾选本计划全部步骤并把 INDEX 中本计划状态更新为“已完成”，然后运行：

```bash
git add ydyl-gen-accounts docs/superpowers/INDEX.md docs/superpowers/plans/2026-09-04-gen-accounts-core-space-batch-sender-deploy-plan.md
git commit -m "feat: support Core BatchSender deployment"
git status --short --branch
```

预期：父仓库提交记录包含新子模块指针、已完成计划和 INDEX 状态；父仓库与子模块工作区均干净。
