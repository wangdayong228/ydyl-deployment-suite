# deploy-client `monitor-gen-accounts` 按链类型汇总

## 背景

`ydyl-deploy-client monitor-gen-accounts` 轮询各链 `ydyl-console-service` 的 `/v1/result/gen-acc/summary`，把分链 `items` 与全量加总 `summary` 写入 `output/summary-gen-accounts.json`。验收 4.1.32（侧链最大支持用户容量）需要一眼看到每种链有多少条、各自创建了多少账户。原先 `summary` 只有全链数字加总；选机还把 XJST 一组 4 个节点都算进去。

## 目标

- JSON 顶层增加 `byServiceType`：固定键 `op` / `cdk` / `xjst`，每项含 `count`（链条数）与 `accountGenerated`（该类型创建总账户数）
- 控制台每轮在现有 `totalAccountGenerated` / `successServers` / `errorServers` 后追加 `op=<count>/<accountGenerated>` 等同格式
- 选机与统计同一口径：`op`/`cdk` 全留，XJST 只计组内 `index==1`
- 顶层 `summary.accountGenerated` 等于三类 `byServiceType.*.accountGenerated` 之和

## 非目标

- 不改 `ydyl-console-service` 与远端 `progress.all.by-contract.json` 格式
- 不改 SDK `GenAccSummaryResponse` 字段
- 不把条数塞进现有 `summary` 对象
- 不改 `PickChainEntries` 本身
- 不改 `gen-accounts start|stop|resume`

## 选机

1. 丢掉 `serviceType` 不是 `op`/`cdk`/`xjst` 的项（含 `generic`）以及空 IP。不能把整份 `servers.json` 直接交给 `PickChainEntries`，否则 `generic` 会 fail-fast。
2. 对过滤后的列表调用 `crosstxconfig.PickChainEntries`：XJST 仅 `index==1`；非法 name / 空 name / 重复 name 失败退出。
3. 禁止对全部 name 做 `HasSuffix("-1")`。
4. 结果按 name 排序。过滤后为空则失败退出。

## `byServiceType` 口径

| 字段 | 含义 |
|------|------|
| `count` | 该类型选中的链条数，**含**本轮 API 失败的链 |
| `accountGenerated` | 该类型本轮成功拉到 summary 的 `accountGenerated` 之和（`Summary == nil` 的项不加） |

三类键即使为 0 也必须输出。用结构体而不是 `map`，保证 JSON 键稳定。

示例：

```json
{
  "updatedAt": "2026-09-09T07:00:00Z",
  "items": [],
  "summary": {
    "totalTxSentCount": 0,
    "accountGenerated": 123000,
    "accountRemains": 0,
    "processing": 0,
    "success": 0,
    "fail": 0
  },
  "byServiceType": {
    "op": { "count": 20, "accountGenerated": 50000 },
    "cdk": { "count": 20, "accountGenerated": 40000 },
    "xjst": { "count": 11, "accountGenerated": 33000 }
  }
}
```

## 控制台

每轮一行：

```text
[ts] totalAccountGenerated=123000 successServers=51 errorServers=1 op=20/50000 cdk=20/40000 xjst=11/33000
```

`类型=条数/创建总账户数`。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/genaccmonitor/monitor.go` | 选机对齐 `PickChainEntries`；`SummaryFile` 增加 `byServiceType`；抽出 `aggregate`；控制台打印按类型统计 |
| `ydyl-deploy-client/internal/genaccmonitor/monitor_test.go` | 选机与按类型聚合单测 |
| `ydyl-deploy-client/cmd/monitor_gen_accounts.go` | 命令说明补上 `byServiceType` 与 XJST node-1 |
| `docs/superpowers/INDEX.md` | 登记本 spec |
| `docs/superpowers/specs/2026-09-07-deploy-client-gen-accounts-remote-commands-spec.md` | 注明 monitor 已另实现，原非目标不阻止后续监控命令 |

## 测试

- 选机：op/cdk 全留；`xjst-2-1` 留、`xjst-2-2` 丢；`generic` 忽略；`tps-ydyl-op-2` 不得因 `-2` 被丢掉
- 聚合：`count` 含失败项；`accountGenerated` 只加成功项；顶层总和等于三类之和
