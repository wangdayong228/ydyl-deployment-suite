# OP 流水线：`FAULT_GAME_MAX_CLOCK_DURATION` 环境变量

## 背景

OP Stack 链上 `FaultDisputeGame` 的 `MAX_CLOCK_DURATION` 为 **immutable**，只能在 op-deployer 部署合约时通过 `faultGameMaxClockDuration`（秒）写入。演示环境将主网默认 3.5 天（302400s）压缩为 24 秒，以缩短 dispute game resolve 等待；该背景见 [`2026-05-06-rollup-sidechain-integration-spec`](2026-05-06-rollup-sidechain-integration-spec.md) 与 [`op-work/doc/l2-withdrawal-and-fault-proof.md`](../../op-work/doc/l2-withdrawal-and-fault-proof.md) §7。

当前配置链路存在断层：

```
FAULT_GAME_MAX_CLOCK_DURATION（尚不存在）
  → params.template.yml（尚无棋钟字段）
  → envsubst
  → kurtosis run
  → optimism-package contract_deployer.star（硬编码 24）
  → op-deployer intent
  → 链上 MAX_CLOCK_DURATION
```

具体问题：

1. [`op-work/scripts/params.template.yml`](../../op-work/scripts/params.template.yml) 的 `op_contract_deployer_params` 仅有镜像与 artifacts，**未**包含棋钟参数。
2. 实际值硬编码在 [`optimism-package/src/contracts/contract_deployer.star`](../../optimism-package/src/contracts/contract_deployer.star) 两处：
   - `globalDeployOverrides.faultGameMaxClockDuration: 24` — PermissionedDisputeGame（GameType 1），**L2→L1 提现**使用
   - `dangerousAdditionalDisputeGames[].faultGameMaxClockDuration: 24` — GameType 0 additional FaultDisputeGame
3. [`op-work/scripts/deploy.sh`](../../op-work/scripts/deploy.sh) 固定拉取 `github.com/wangdayong228/optimism-package@948152332c155a4e5b86be006145490e948ade89`。
4. optimism-package 虽支持 `op_contract_deployer_params.global_deploy_overrides`，但：
   - [`sanity_check.star`](../../optimism-package/src/package_io/sanity_check.star) 白名单仅含 `faultGameAbsolutePrestate` / `proofMaturityDelaySeconds` / `faultGameWithdrawalDelay`，**不含** `faultGameMaxClockDuration`
   - [`input_parser.star`](../../optimism-package/src/package_io/input_parser.star) 对 `op_contract_deployer_params` 为**浅** `update`，用户 YAML 只写 `faultGameMaxClockDuration` 时会**整段替换** `global_deploy_overrides`，丢失默认键 `faultGameAbsolutePrestate`
   - `contract_deployer.star` 用下标访问 `["faultGameAbsolutePrestate"]`，在上述浅合并后可能 KeyError；且在设置 prestate 时会 **replace** 整个 `globalDeployOverrides`，丢掉其余 demo 参数

运维需改 optimism-package 源码或手工 patch 渲染后的 params，无法与 `op_pipe.sh` / `envsubst` 环境变量风格统一（对比已完成的 [`2026-06-11-cdk-use-real-prover-env-spec`](2026-06-11-cdk-use-real-prover-env-spec.md)）。

## 目标

- 用户通过环境变量 **`FAULT_GAME_MAX_CLOCK_DURATION`**（无前导零的正整数，单位秒）控制链上 `MAX_CLOCK_DURATION`
- 经现有 `envsubst` 注入 `params.template.yml`，不引入新工具链
- **默认值 `24`**，与当前演示环境行为一致
- `op_pipe.sh` 的 `PERSIST_VARS` + `check_input_env_consistency` 支持续跑一致性
- `ydyl-deploy-client deploy` 可通过 `config.deploy.yaml` 的 `faultGameMaxClockDuration` 将该值透传到远端 `op_pipe.sh`
- Permissioned game 与 additional game **使用同一 max 值**

## 非目标

- **不**将 `FAULT_GAME_CLOCK_EXTENSION`（固定 **12**）、`PREIMAGE_ORACLE_CHALLENGE_PERIOD`（固定 **0**）暴露为用户可配项
- **不**在本 spec 中改动 `proofMaturityDelaySeconds` / `disputeGameFinalityDelaySeconds` / `faultGameWithdrawalDelay`（仍由 `contract_deployer.star` 现有 demo 默认值 12 / 0 / 12 提供）
- **不**在 `params.template.yml` 中增加除 `faultGameMaxClockDuration` 以外的 `global_deploy_overrides` 字段（其它 dispute delay 继续由 `contract_deployer.star` 内置 demo dict 提供）
- **不**将 demo 秒级参数（`proofMaturityDelaySeconds` 等）下沉到 `input_parser` 默认值，避免与 `contract_deployer.star` 双处维护
- **不**支持已部署 enclave 热更新（合约 immutable，需 `FORCE_DEPLOY_OP=true` 重部署）；仅改 env 且 step4 因 enclave 已存在而跳过时，链上参数不会变

## 合约约束

部署时 OPCM / `FaultDisputeGame` 构造函数校验：

```
max(clockExtension × 2, clockExtension + oracleChallengePeriod) ≤ maxClockDuration
```

本 spec 固定 `faultGameClockExtension = 12`、`preimageOracleChallengePeriod = 0`（additional game 侧 `useCustomOracle: true` + `oracleChallengePeriodSeconds: 0`），故：

**`FAULT_GAME_MAX_CLOCK_DURATION` 合法下界为 24。**

解析脚本在值 `< 24`、非正整数或带前导零时**失败并给出明确错误**，避免 op-deployer apply 阶段 revert 或 Bash 八进制数字解析差异。详见 [`op-work/doc/note.md`](../../op-work/doc/note.md) §修改 MAX_CLOCK_DURATION。

## 变量映射

| 环境变量 | 默认 | 写入 `params.template.yml` | op-deployer / 链上 |
|---------|------|---------------------------|-------------------|
| `FAULT_GAME_MAX_CLOCK_DURATION` | `24` | `op_contract_deployer_params.global_deploy_overrides.faultGameMaxClockDuration` | `MAX_CLOCK_DURATION` |

固定常量（不暴露 env，由 `contract_deployer.star` 写入 intent）：

| 字段 | 固定值 | 链上 / 语义 |
|------|--------|------------|
| `faultGameClockExtension` | `12` | `CLOCK_EXTENSION` |
| `preimageOracleChallengePeriod` | `0` | global oracle challenge period |
| additional game `useCustomOracle` | `true` | 满足短 period 合约校验 |
| additional game `oracleChallengePeriodSeconds` | `0` | 同上 |

两套 game 分工（改 max 时须同步）：

| 配置入口 | GameType | 场景 |
|----------|----------|------|
| `globalDeployOverrides.faultGameMaxClockDuration` | 1 PermissionedDisputeGame | L2→L1 提现 |
| `dangerousAdditionalDisputeGames[].faultGameMaxClockDuration` | 0 FaultDisputeGame | 额外 Cannon game |

## 涉及文件

| 文件 | 改动 |
|------|------|
| `docs/superpowers/specs/2026-06-12-op-fault-game-max-clock-duration-spec.md` | 本 spec |
| `docs/superpowers/INDEX.md` | 索引与依赖 |
| `op-work/scripts/params.template.yml` | `global_deploy_overrides.faultGameMaxClockDuration: $FAULT_GAME_MAX_CLOCK_DURATION` |
| `op-work/scripts/dispute_clock_env.sh` | 解析、校验（正整数、无前导零、≥24）、`export` |
| `op-work/scripts/dispute_clock_env.test.sh` | 默认值、显式值、非法值、模板渲染、无残留占位符、`op_pipe.sh` 一致性挂钩 |
| `op-work/scripts/deploy.sh` | `run_deploy` 前 `source dispute_clock_env.sh`；实现后更新 `OP_PACKAGE_LOCATOR` commit |
| `op_pipe.sh` | 头部可选变量；`record_input_vars`；`PERSIST_VARS`；`check_env_compat`；启动时调用解析函数 |
| `ydyl-deploy-client/internal/deploy/config.go` | 增加 `faultGameMaxClockDuration` 配置项和本地校验 |
| `ydyl-deploy-client/internal/deploy/deploy.go` | 内置 OP 远程命令透传 `FAULT_GAME_MAX_CLOCK_DURATION` |
| `ydyl-deploy-client/config.deploy.example.yaml` / `README.md` | 说明 deploy-client 配置方式 |
| `optimism-package/src/package_io/sanity_check.star` | `OP_CONTRACT_DEPLOYER_GLOBAL_DEPLOY_OVERRIDES` 增加 `faultGameMaxClockDuration` |
| `optimism-package/src/package_io/input_parser.star` | 对 `global_deploy_overrides` **深合并**（保留 `faultGameAbsolutePrestate` 等 parser 默认键） |
| `optimism-package/src/contracts/contract_deployer.star` | **`DEMO_GLOBAL_DEPLOY_OVERRIDES` + YAML 覆盖**（主逻辑）；两套 game 同源 |

## 详细设计

### 1. `params.template.yml`

在 `op_contract_deployer_params` 下增加：

```yaml
  op_contract_deployer_params:
    image: "davidyoung2025/op-deployer:v0.0.12"
    l1_artifacts_locator: ...
    l2_artifacts_locator: ...
    global_deploy_overrides:
      faultGameMaxClockDuration: $FAULT_GAME_MAX_CLOCK_DURATION
```

本阶段模板 **`global_deploy_overrides` 仅增加 `faultGameMaxClockDuration` 一个字段**，不要写入 `proofMaturityDelaySeconds` / `faultGameClockExtension` 等（由 deployer 内置 demo dict 提供）。

`envsubst` 由 [`ydyl-scripts-lib/deploy_common.sh`](../../ydyl-scripts-lib/deploy_common.sh) 的 `ydyl_kurtosis_deploy` 调用，无需改动。

### 2. `dispute_clock_env.sh` — 公共解析函数

```bash
FAULT_GAME_MAX_CLOCK_DURATION="${FAULT_GAME_MAX_CLOCK_DURATION:-24}"
if ! [[ "$FAULT_GAME_MAX_CLOCK_DURATION" =~ ^([1-9][0-9]*)$ ]] || [[ "$FAULT_GAME_MAX_CLOCK_DURATION" -lt 24 ]]; then
  echo "错误: FAULT_GAME_MAX_CLOCK_DURATION 须为无前导零的正整数且 >= 24（当前固定 clockExtension=12），当前值: $FAULT_GAME_MAX_CLOCK_DURATION" >&2
  return 1
fi
export FAULT_GAME_MAX_CLOCK_DURATION
```

### 3. `deploy.sh`

在 `run_deploy` 前 `source` 解析脚本，确保直接执行 `op-work/scripts/deploy.sh` 与经 `op_pipe.sh` 调用行为一致。

### 4. `op_pipe.sh`

对齐 CDK [`resolve_cdk_prover_env` / `init_optional_env_vars`](../../cdk_pipe.sh) 模式：

- 头部可选变量：`FAULT_GAME_MAX_CLOCK_DURATION: dispute game 棋钟上限秒数（默认 24）`
- 新增 `init_optional_env_vars`（或等价入口），在父 shell 启动时 `source dispute_clock_env.sh`，使默认值写入 `output/op_pipe.state`
- `record_input_vars` 记录 `INPUT_FAULT_GAME_MAX_CLOCK_DURATION`
- `check_env_compat` 对 `FAULT_GAME_MAX_CLOCK_DURATION` 做续跑一致性校验
- `PERSIST_VARS` 增加 `FAULT_GAME_MAX_CLOCK_DURATION`

`step4_deploy_kurtosis_op` 无需改代码：子进程继承已 export 的环境变量。

`dispute_clock_env.test.sh` 除 env 解析与模板渲染外，应断言 `op_pipe.sh` 含 `INPUT_FAULT_GAME_MAX_CLOCK_DURATION`、`check_input_env_consistency FAULT_GAME_MAX_CLOCK_DURATION`、`resolve_op_dispute_clock_env`（或实际函数名）等挂钩（参考 [`cdk-work/scripts/prover_env.test.sh`](../../cdk-work/scripts/prover_env.test.sh)）。

### 5. `ydyl-deploy-client` 远程透传

`ydyl-deploy-client/internal/deploy/config.go` 在 `CommonConfig` 增加：

```yaml
faultGameMaxClockDuration: "600"
```

为空时不拼接该环境变量，远端 `op_pipe.sh` 使用默认 `24`；非空时先做与 `op_pipe.sh` 一致的本地校验（无前导零、正整数、`>= 24`），再在内置 OP 远程命令中追加：

```bash
FAULT_GAME_MAX_CLOCK_DURATION=<value> ./op_pipe.sh
```

### 6. `optimism-package` — `sanity_check.star`

`OP_CONTRACT_DEPLOYER_GLOBAL_DEPLOY_OVERRIDES` 至少增加：

```python
"faultGameMaxClockDuration",
```

否则 kurtosis 包在解析 args 时会因字段不在白名单而失败。

### 7. `optimism-package` — `input_parser.star`（辅助：深合并）

`op_contract_deployer_params` 仍为浅 `update`，但对嵌套 dict **`global_deploy_overrides` 单独深合并**，避免模板只写 `faultGameMaxClockDuration` 时丢失 parser 默认键：

```python
odp = default_op_contract_deployer_params()
user_odp = input_args.get("op_contract_deployer_params", {}) or {}
user_gdo = user_odp.get("global_deploy_overrides")
odp.update({k: v for k, v in user_odp.items() if k != "global_deploy_overrides"})
if user_gdo:
    odp["global_deploy_overrides"].update(user_gdo)
results["op_contract_deployer_params"] = odp
```

**职责边界**：`input_parser` 只保证 args 结构完整（如保留 `faultGameAbsolutePrestate: ""`）；**不**把 demo 秒级 dispute 参数写入 `default_op_contract_deployer_global_deploy_overrides()`，那些默认值仅在 `contract_deployer.star` 维护。

### 7. `optimism-package` — `contract_deployer.star`（主逻辑）

**现状（问题）：**

```python
"globalDeployOverrides": {
    "proofMaturityDelaySeconds": 12,
    "faultGameWithdrawalDelay": 12,
    "dangerouslyAllowCustomDisputeParameters": True,
    "faultGameClockExtension": 12,
    "faultGameMaxClockDuration": 24,  # 硬编码
    "preimageOracleChallengePeriod": 0,
    "disputeGameFinalityDelaySeconds": 0,
}
# ...
if faultGameAbsolutePrestate:
    intent["globalDeployOverrides"] = {  # replace，丢掉上面 demo 参数
        "dangerouslyAllowCustomDisputeParameters": True,
        "faultGameAbsolutePrestate": absolute_prestate,
    }
```

**目标行为（方案 C：deployer 为主 + parser 深合并为辅）：**

1. 在 `contract_deployer.star` 定义常量 `DEMO_GLOBAL_DEPLOY_OVERRIDES`（保留现有秒级参数，`faultGameMaxClockDuration` 默认 24）——**demo 默认值的唯一来源**
2. 读取 `yaml_gdo = optimism_args.op_contract_deployer_params.global_deploy_overrides`，一律用 `.get(key, default)`，禁止对可选键用下标访问
3. 构建 intent：

```python
DEMO_GLOBAL_DEPLOY_OVERRIDES = {
    "proofMaturityDelaySeconds": 12,
    "faultGameWithdrawalDelay": 12,
    "dangerouslyAllowCustomDisputeParameters": True,
    "faultGameClockExtension": 12,
    "faultGameMaxClockDuration": 24,
    "preimageOracleChallengePeriod": 0,
    "disputeGameFinalityDelaySeconds": 0,
}

yaml_gdo = optimism_args.op_contract_deployer_params.global_deploy_overrides
global_overrides = dict(DEMO_GLOBAL_DEPLOY_OVERRIDES)

if yaml_gdo.get("faultGameMaxClockDuration") != None:
    global_overrides["faultGameMaxClockDuration"] = yaml_gdo["faultGameMaxClockDuration"]

absolute_prestate = yaml_gdo.get("faultGameAbsolutePrestate", "") or ""
if absolute_prestate:
    global_overrides["faultGameAbsolutePrestate"] = absolute_prestate

intent["globalDeployOverrides"] = global_overrides
```

4. `dangerousAdditionalDisputeGames` 单次构建（去掉重复 `intent_chain.update`）；`faultGameMaxClockDuration` 取 `global_overrides["faultGameMaxClockDuration"]`；`faultGameClockExtension: 12`、`useCustomOracle: True`、`oracleChallengePeriodSeconds: 0` 保留

### 8. 实现与发布顺序

避免「模板已改、package 未升」导致 sanity check 失败：

1. 改 `optimism-package`（`input_parser` 深合并 + `contract_deployer` demo merge + `sanity_check` 白名单）并 push
2. 更新 [`op-work/scripts/deploy.sh`](../../op-work/scripts/deploy.sh) 中 `OP_PACKAGE_LOCATOR` 至新 commit
3. 改 `op-work`（`params.template.yml`、`dispute_clock_env.sh`、`deploy.sh` source）
4. 改顶层 `op_pipe.sh`
5. 同步更新主仓库与各 submodule 指针（`optimism-package`、`op-work`）

**不可**在未升级 `OP_PACKAGE_LOCATOR` 前单独合并仅含 `faultGameMaxClockDuration` 的模板——旧 package 白名单会拒绝该字段。

## 使用方式

```bash
# 默认 24 秒（与改前 demo 一致）
./op_pipe.sh

# op-challenger 自动多步对局：分钟级棋钟
FAULT_GAME_MAX_CLOCK_DURATION=600 FORCE_DEPLOY_OP=true ./op_pipe.sh

# 仅检查渲染（不部署；须补齐 deploy.sh 要求的 L2_CHAIN_ID / L1_CHAIN_ID / L1_RPC_URL / KURTOSIS_L1_* 等，可参考 deploy-eth.sh）
DRYRUN=true FAULT_GAME_MAX_CLOCK_DURATION=600 op-work/scripts/deploy.sh op-gen
```

修改 `FAULT_GAME_MAX_CLOCK_DURATION` 后必须 **`FORCE_DEPLOY_OP=true`** 重部署 enclave，否则链上 immutable 参数不变。

## 验收标准

1. 未设置 `FAULT_GAME_MAX_CLOCK_DURATION` 时，渲染后 `params-<network>.yml` 中 `faultGameMaxClockDuration: 24`
2. `FAULT_GAME_MAX_CLOCK_DURATION=600` 时渲染为 `600`；`envsubst` 后无残留 `$FAULT_GAME_MAX_CLOCK_DURATION`
3. `FAULT_GAME_MAX_CLOCK_DURATION=10`、带前导零或非法值时，解析脚本失败，不进入 kurtosis
4. `op_pipe.sh` 续跑时该变量与 `output/op_pipe.state` 一致，不一致则拒绝
5. `FORCE_DEPLOY_OP=true` 重部署后，部署产物 `op-work/output/op-deployer-configs-<enclave>/intent-merged.json`（或等价 merge 后 intent）中，`globalDeployOverrides.faultGameMaxClockDuration` 与 `chains[].dangerousAdditionalDisputeGames[].faultGameMaxClockDuration` 均为配置值
6. optimism-package sanity check 通过（新 YAML 字段在白名单内）
7. 模板仅含 `faultGameMaxClockDuration` 时，`contract_deployer` 不因缺少 `faultGameAbsolutePrestate` 键而失败（parser 深合并 + deployer `.get`）
8. `ydyl-deploy-client` 设置 `faultGameMaxClockDuration: "600"` 时，内置 OP 远程命令包含 `FAULT_GAME_MAX_CLOCK_DURATION=600 ./op_pipe.sh`
9. `ydyl-deploy-client` 的 `forceDeployL2Chain` 在 OP 内置远程命令中映射为 `FORCE_DEPLOY_OP`，确保修改 immutable 棋钟参数后可触发重部署

## 关联 spec

- 上游：[`2026-05-06-rollup-sidechain-integration-spec`](2026-05-06-rollup-sidechain-integration-spec.md)（dispute 参数秒级压缩背景）
- 模式参考：[`2026-06-11-cdk-use-real-prover-env-spec`](2026-06-11-cdk-use-real-prover-env-spec.md)（envsubst + 流水线持久化）
- 领域文档：[`op-work/doc/l2-withdrawal-and-fault-proof.md`](../../op-work/doc/l2-withdrawal-and-fault-proof.md)、[`op-work/doc/note.md`](../../op-work/doc/note.md)
- 扩展：[`2026-05-07-multi-sidechain-bulk-deployment-spec`](2026-05-07-multi-sidechain-bulk-deployment-spec.md)（`ydyl-deploy-client` 远程 env 透传）
