# confura 配置
## 主服务配置
- 版本 main, commint 18a9559d404985ef318ad29be0a3376eac9b1687; 开了 grpc
  -  v1.3.7-mainnet-hotfix-3 是以前用的稳定版，但没有 grpc，性能会差
- .env 配置见[这里](./confura_env.env)
- docker-compose.yml 见[这里](./docker-compose.yml)
- nginx 配置见[这里](./confura_nginx)

## 负载均衡第二台 confura 配置
- commit 9387821e926d447890047dcc17ac2d2ab1323fd4； tag v1.7.1-testnet
- .env 配置见[这里](./confura_env_2.env)
- docker-compose.yml 见[这里](./docker-compose_2.yml)
- 无 nginx 配置
