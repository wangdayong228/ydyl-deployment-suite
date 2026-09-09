# deploy-client 远端 `ydyl-gen-accounts` start/stop/resume

## 背景

批量部署后需要在多台 EC2 上统一操作 `ydyl-gen-accounts`（启动、暂停、恢复 PM2 任务）。目前只能 SSH 到单机执行 `npm run start|stop|resume`。XJST 每组 4 个节点中只有组内 `node-1` 跑 gen-accounts，其余节点没有对应进程。

## 目标

- 命令：`ydyl-deploy-client gen-accounts start|stop|resume`
- 默认 `--servers ./output/servers.json`，默认 `-f ./config.deploy.yaml`
- 对选中机器并发 SSH，前台执行远端 `npm run <action>`（不 nohup）
- `start` 与 `resume` 保持独立：远端分别执行 `npm run start` 与 `npm run resume`，不带流水线 `--fundAmount` 等额外参数
- 一台失败不中断其它机器，结束后汇总 multierror

## 非目标

- 不合并 `start` / `resume`
- 不实现 README 中尚未存在的 `monitor-gen-accounts`（该命令已于后续单独实现；本条非目标不阻止后续监控命令，见 [2026-09-09 by-type spec](2026-09-09-deploy-client-monitor-gen-accounts-by-type-spec.md)）
- 不改流水线 step9，不改 `ydyl-gen-accounts/package.json`
- 不在远端重新部署合约或改写 `.env`

## 选机规则

读取 `servers.json`（`ip` / `serviceType` / `name`），复用 `crosstxconfig.PickChainEntries`：

- `op` / `cdk`：全部参与
- `xjst`：仅 name 解析出的组内 `index==1`（如 `tps-ydyl-xjst-2-1`）
- **禁止**对全部 name 做 `HasSuffix("-1")`，否则会丢掉 `tps-ydyl-op-2` / `tps-ydyl-cdk-2`
- name 非法、空 name、空 ip、重复 name、不支持的 serviceType：失败退出
- 过滤后列表按 name 排序，保证 SSH 顺序稳定
- 过滤后为空：失败退出

## 远端命令

工作目录：`/home/ubuntu/workspace/ydyl-deployment-suite/ydyl-gen-accounts`（与 deploy 的 `RemoteRepoDirDefault` 一致）。

```bash
bash -lc 'set -euo pipefail; source "$HOME/.ydyl-env"; cd /home/ubuntu/workspace/ydyl-deployment-suite/ydyl-gen-accounts; npm run start'
```

`stop` / `resume` 只替换最后的 npm script 名。必须 `source ~/.ydyl-env`，否则 nvm 下的 `npm`/`pm2` 可能不在 PATH。

依赖远端已有 `ydyl-gen-accounts/.env`（流水线 step9 写入）。若 PM2 中进程仍在列表，再次 `start` 可能报 `Script already launched`，此时应使用 `resume`。

## SSH

- 二进制：本机 `ssh`
- 选项：`StrictHostKeyChecking=no`、`IdentitiesOnly=yes`、`BatchMode=yes`、`-i <SSHKeyPath>`
- 用户与私钥来自 deploy 配置：`sshUser`、`keyName`、`sshKeyDir`（空则 `~/.ssh/{keyName}.pem`）。由 CLI 读取 YAML 后注入 `genaccounts.Params`，核心包不直接 `LoadConfigFromFile`，避免 viper 全局状态影响测试。
- 并发：`sshMaxConcurrency`，未设则沿用 deploy 默认
- 真实 SSH 前检查私钥文件存在；测试注入 Runner 时跳过文件检查

## CLI

```bash
cd ydyl-deploy-client
go run . gen-accounts start
go run . gen-accounts stop
go run . gen-accounts resume
go run . gen-accounts start --servers ./output/servers.json -f ./config.deploy.yaml
```

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/genaccounts/genaccounts.go` | 选机、拼命令、并发 SSH |
| `ydyl-deploy-client/internal/genaccounts/genaccounts_test.go` | 选机、命令、mock SSH、部分失败 |
| `ydyl-deploy-client/cmd/gen_accounts.go` | cobra `gen-accounts` 及 start/stop/resume |
| `ydyl-deploy-client/cmd/gen_accounts_test.go` | 子命令与默认 `--servers` 注册校验 |
| `ydyl-deploy-client/internal/deploy/deploy.go` | 导出 `SSHKeyPath` / `SSHMaxConcurrency` |
| `ydyl-deploy-client/internal/deploy/exec_helpers.go` | 导出 `RemoteRepoDirDefault` |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig_test.go` | 测试 YAML 补齐 DeployConfig 新增字段 |
| `README.md` | 用本组命令替换不存在的 `monitor-gen-accounts` |

## 用法注意

- 在 `ydyl-deploy-client` 目录执行，以便默认路径生效
- `stop` 只暂停 PM2 进程；`resume` 用 `pm2 restart` 拉起；`start` 走 `3_concurrency.ts` 全流程
