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
```


