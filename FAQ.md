# 快速查看地址和 URL

`ydyl-console-service` 默认 `http://<node-ip>:8080`，这些接口没有鉴权。

## 部署结果

```bash
curl -sS http://<node-ip>:8080/v1/result/pipeline/summary
```

本次部署的 L1/L2 RPC、L2 水龙头私钥、L2 部署账户私钥、claim-service 私钥、Counter 和 bridge hub。

## 桥合约

```bash
curl -sS http://<node-ip>:8080/v1/result/node-deployment-contracts
curl -sS http://<node-ip>:8080/v1/result/node-deployment-contracts/cdk
curl -sS http://<node-ip>:8080/v1/result/node-deployment-contracts/op
curl -sS http://<node-ip>:8080/v1/result/node-deployment-contracts/xjst
curl -sS http://<node-ip>:8080/v1/result/node-deployment-contracts/xjst/l1
```

第一条按当前链返回 L1/L2 桥地址。后面四条分别是 CDK、OP、XJST 合约，以及 XJST 的 L1 合约。