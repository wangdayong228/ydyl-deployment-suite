# ydyl-deployment-suite

一个用于部署与运维多种 Layer2（ZK 与 OP）的自动化脚本与服务集合。

## 顶层脚本

- `cdk_pipe.sh`：用来自动化执行所有 ZK Layer2 相关服务
- `op_pipe.sh`：用来自动化执行所有 OP Layer2 相关服务

## 子模块一览（一句话介绍）

- `cdk-work`：CDK（ZK L2）相关的部署与运维脚本、文档与 Nginx 配置
- `op-work`：OP Stack 相关的部署与运维脚本、示例与 Nginx 配置
- `op-claim-service`：OP 跨域消息监听、证明生成与中继/完成的后台服务（Node.js/PM2）
- `zk-claim-service`：ZK 跨域消息监听、证明获取与交易发送的后台服务与脚本
- `ydyl-gen-accounts`：批量生成账户与资金发放工具（Hardhat/TypeScript），用于压测与演示

## 快速开始

```bash
# ZK L2 全链路自动化
bash cdk_pipe.sh

# OP L2 全链路自动化
bash op_pipe.sh

# XJST # OP L2 全链路自动化
bash xjst_pipe.sh
```

## 说明：Counter 部署与 bridgeHub 注册（step7）

`cdk_pipe.sh/op_pipe.sh` 的 step7 会执行 `zk-claim-service/scripts/i_deployCounterAndRegisterBridge.js`，它读取 `zk-claim-service/.env.counter-bridge-register` 来完成：
- 在 L2 部署 `Counter`
- 在 L1 的 `bridgeHub` 调用 `addBridgeService` 批量注册桥合约地址

其中桥地址使用 **`BRIDGES`（数组）**：\n- `.env.counter-bridge-register`：`BRIDGES=0xaaa...,0xbbb...`（逗号分隔）
- CLI：可重复传参 `--bridges 0x... --bridges 0x...`


## 重置 fullnode 后环境配置
1. confura
2. scan
3. 运行 [setup-cfxnode.sh](./setup-cfxnode.sh) 部署 determistic 合约和启动 jsonrpc-proxy-op