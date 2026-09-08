# sample-wallets 抽查确定性账户余额实施计划

> **面向执行代理：** 必须使用 `executing-plans` 或 `subagent-driven-development`，按任务逐项执行。所有步骤使用复选框跟踪状态。

**目标：** 在 `ydyl-deploy-client` 新增 `sample-wallets`：按 `--l2type` 从 `servers.json` 随机挑一条链，用确定性规则抽取 10 个 index，派生地址并查询 L2 余额。

**架构：** Cobra 命令调用 `internal/samplewallets`。该包复用 `PickChainEntries` 与导出的 `ReplaceLocalhostWithIP`，通过可注入的 summary fetcher 与 JSON-RPC balance client 查链；私钥转地址放在 `cryptoutil`。

**技术栈：** Go 1.25、Cobra、go-ethereum `crypto`/`rpc`、ydyl-console-service SDK

## 全局约束

- spec 真理之源：`docs/superpowers/specs/2026-09-08-deploy-client-sample-wallets-spec.md`
- 不修改 `gen-private-key`，不补 `cmd/gen_private_key.go`
- 不支持 `l2type=3`；不加 `--rpc-url` / `--chainID` / `--groupID` / `--index` / `--count` / `--config`
- 抽样个数固定 10；`--max-index` 默认 1000000，区间 `[0, max-index)`
- `--l2type` 必填且 `0` 合法（cdk）；必须用 Cobra required flag，不能靠默认值 0
- 不改 `PickChainEntries` 规则；只导出 `ReplaceLocalhostWithIP`，行为与现有 `replaceLocalhostWithIP` 相同
- 生产代码遵循红、绿、重构；每个测试必须先因缺少目标行为而失败
- 用户未要求 commit：不要提交

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil.go` | `AddressFromPrivateKey` |
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil_test.go` | 地址向量 |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go` | 导出 `ReplaceLocalhostWithIP` |
| `ydyl-deploy-client/internal/samplewallets/samplewallets.go` | 选链、抽样、派生、查余额、格式化输出 |
| `ydyl-deploy-client/internal/samplewallets/samplewallets_test.go` | 选链、抽样、余额 RPC、失败路径 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | Cobra |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | flag 默认值与必填 |
| `ydyl-deploy-client/README.md` | 用法 |

---

### Task 1: cryptoutil 私钥转地址

**文件：**

- 修改：`ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil.go`
- 修改：`ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil_test.go`

**接口：**

- 产出：`AddressFromPrivateKey(pkHex string, l2type int) (string, error)`
- `l2type` 仅 `0/1/2`；`0/1` 以太坊地址；`2` 将以太坊地址 `0x` 后第一个 hex 字符置为 `1`

- [x] **步骤 1：写失败测试**

在 `cryptoutil_test.go` 增加：

```go
func TestAddressFromPrivateKey_EVMVector(t *testing.T) {
	pk, err := BuildDeterministicPrivateKey(0, 10000, big.NewInt(200000), 1)
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	got, err := AddressFromPrivateKey(pk, 1)
	if err != nil {
		t.Fatalf("addr: %v", err)
	}
	want := "0xfc737023702a09c01260252d853033ccaa587b5d"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}

func TestAddressFromPrivateKey_XJSTVector(t *testing.T) {
	pk, err := BuildDeterministicPrivateKey(1, 0, big.NewInt(12345), 2)
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	got, err := AddressFromPrivateKey(pk, 2)
	if err != nil {
		t.Fatalf("addr: %v", err)
	}
	want := "0x1d22176670f087456f2760405469b25917eed45b"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}
```

- [x] **步骤 2：确认 RED**

```bash
cd ydyl-deploy-client && go test ./internal/utils/cryptoutil -run TestAddressFromPrivateKey -count=1
```

期望：`AddressFromPrivateKey` undefined。

- [x] **步骤 3：最小实现**

用 `crypto.HexToECDSA` + `crypto.PubkeyToAddress`；`l2type==2` 时改写第一个 nibble。非法 l2type / 非法私钥返回 error。

- [x] **步骤 4：确认 GREEN**

同一条 `go test` 命令通过。

---

### Task 2: samplewallets 核心（TDD）

**文件：**

- 新建：`ydyl-deploy-client/internal/samplewallets/samplewallets.go`
- 新建：`ydyl-deploy-client/internal/samplewallets/samplewallets_test.go`
- 修改：`ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go`（导出 `ReplaceLocalhostWithIP`，内部调用点改名）

**接口：**

```go
const SampleCount = 10
const DefaultMaxIndex uint64 = 1_000_000
const DefaultServersPath = "./output/servers.json"

type Params struct {
	ServersPath string
	L2Type      int
	MaxIndex    uint64
}

type Wallet struct {
	Index      *big.Int
	PrivateKey string
	Address    string
	BalanceWei *big.Int
}

type Result struct {
	Name    string
	L2Type  int
	ChainID uint64
	GroupID uint64
	RPC     string
	Wallets []Wallet
}

type SummaryFetcher interface {
	FetchSummary(ctx context.Context, ip string) (*ydylconsolesdk.SummaryResultResponse, error)
}

type BalanceClient interface {
	BalanceAt(ctx context.Context, rpcURL, address string, l2type int) (*big.Int, error)
}

func Run(ctx context.Context, p Params, fetcher SummaryFetcher, balances BalanceClient) (*Result, error)
func FormatResult(r *Result) string
```

`Run` 内部：`LoadServers` → `PickChainEntries` → 按 l2type 过滤 → `crypto/rand` 选 1 条 → `FetchSummary` → `ReplaceLocalhostWithIP` → 抽 10 个 index → 派生 → 顺序 `BalanceAt`。

EVM 用 `summary.L2_CHAIN_ID`；XJST 从 name 解析 groupID。

- [x] **步骤 1：写失败测试（选链、抽样、余额方法、失败路径、格式化）**

覆盖：

- 单条匹配链时 `Run` 选中该链（op/`l2type=1`）
- `[0, maxIndex)` 抽出 10 个 unique index
- EVM mock 收到 `eth_getBalance` + `"latest"`；XJST mock 收到 `cfx_getBalance` + `"latest_state"`
- 无匹配链失败；`max-index < 10` 失败
- `FormatResult` 含 name/l2type/rpc 以及四列

测试用假 fetcher / fake balance client；servers.json 写 temp 文件。导出 `ReplaceLocalhostWithIP` 后，`crosstxconfig` 包内测试改调用导出名（或保留未导出别名转发）。

- [x] **步骤 2：确认 RED**

```bash
cd ydyl-deploy-client && go test ./internal/samplewallets -count=1
```

- [x] **步骤 3：最小实现 + 导出 ReplaceLocalhostWithIP**

- [x] **步骤 4：确认 GREEN**

```bash
cd ydyl-deploy-client && go test ./internal/samplewallets ./internal/crosstxconfig -count=1
```

---

### Task 3: Cobra 命令 + README

**文件：**

- 新建：`ydyl-deploy-client/cmd/sample_wallets.go`
- 新建：`ydyl-deploy-client/cmd/sample_wallets_test.go`
- 修改：`ydyl-deploy-client/README.md`

真实 `SummaryFetcher`：`http://<ip>:8080` 的 `GetDeploySummary`。真实 `BalanceClient`：`go-ethereum/rpc`，按 l2type 调 `eth_getBalance` 或 `cfx_getBalance`。

- [x] **步骤 1：写 flag 测试**

`--servers` 默认 `./output/servers.json`；`--max-index` 默认 `1000000`；`l2type` 为 required。

- [x] **步骤 2：确认 RED**

```bash
cd ydyl-deploy-client && go test ./cmd -run SampleWallets -count=1
```

- [x] **步骤 3：注册命令并更新 README**

- [x] **步骤 4：确认 GREEN**

```bash
cd ydyl-deploy-client && go test ./cmd ./internal/samplewallets ./internal/utils/cryptoutil ./internal/crosstxconfig -count=1
```
