# 流水线 step2：L1 账户余额差额补足

## 背景

[`ydyl-scripts-lib/pipeline_steps_lib.sh`](../../ydyl-scripts-lib/pipeline_steps_lib.sh) 中 `step2_fund_l1_accounts` 被 CDK / OP / XJST 三条流水线共用，当前每次执行都无条件转账：

| 收款地址 | 目标余额 |
|---------|---------|
| `KURTOSIS_L1_FUND_VAULT_ADDRESS` | 5000 ether |
| `CLAIM_SERVICE_ADDRESS` | 1000 ether |
| `L1_REGISTER_BRIDGE_ADDRESS` | 1000 ether |

`START_STEP=2` 或重跑 step2 时会重复打满额，浪费 `L1_VAULT_PRIVATE_KEY` 资金。

## 目标

- step2 执行前查询链上余额，**只补足不足部分**至目标余额
- 余额已达标时跳过转账并打印日志
- `DRYRUN=true` 时仍查余额并打印将转金额，不执行 `cast send`
- 目标金额与收款地址集合不变
- 抽取 `fund_eth_up_to` 到 `utils.sh`，便于日后 step5 复用

## 非目标

- 本次不改 `step5_fund_l2_accounts`
- 余额高于目标时不抽回超额资金
- 不新增 vault 余额预检（与现状一致）

## 实现要点

### `wei_deficit`

用 Node `BigInt` 计算 `max(0, target_wei - current_wei)`，避免 bash 64-bit 与 JS `Number` 精度问题。

### `fund_eth_up_to`

```bash
fund_eth_up_to <rpc_url> <from_pk> <to_addr> <amount> <unit>
```

流程：`cast balance` → `cast to-wei` → `wei_deficit` → 差额为 0 则跳过，否则 `run_with_retry cast send --value "${deficit}wei"`。

### step2 改动

三段固定 `cast send --value 5000ether/1000ether` 改为三次 `fund_eth_up_to`；DRYRUN 分支由 helper 内部处理，step2 不再分 DRYRUN/非 DRYRUN 两套逻辑。

## 产物

- `ydyl-scripts-lib/utils.sh`：`wei_deficit`、`fund_eth_up_to`
- `ydyl-scripts-lib/pipeline_steps_lib.sh`：`step2_fund_l1_accounts`
- `ydyl-scripts-lib/utils.test.sh`：单元测试

## 验证

- `bash ydyl-scripts-lib/utils.test.sh` 通过
- 首次部署（余额 0）仍转满额，行为与改前一致
- 重跑 step2 时已达标账户跳过、未达标账户只转差额
