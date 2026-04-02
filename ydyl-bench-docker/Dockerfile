FROM node:20-bookworm

WORKDIR /app

COPY ./zk-claim-service .

RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/* && yarn

ENTRYPOINT ["node", "./scripts/7s_multijob.js"]