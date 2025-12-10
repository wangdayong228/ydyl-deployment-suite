#!/bin/zsh
# 自动监听 docker 容器事件，一旦发现名字里带 logs-collector 的容器，就把日志 dump 出来

OUT_DIR=/tmp/kurtosis-logs-collector-logs
mkdir -p "$OUT_DIR"

echo "保存目录: $OUT_DIR"
echo "现在可以在另一个终端里跑你的 kurtosis 命令了..."

docker events \
  --filter 'type=container' \
  --filter 'event=start' \
  --format '{{.ID}} {{.Actor.Attributes.name}}' | while read -r id name; do
    if [[ "$name" == *logs-collector* ]]; then
      ts=$(date +%Y%m%d-%H%M%S)
      outfile="$OUT_DIR/${name}_${id}_${ts}.log"
      inspect_outfile="$OUT_DIR/${name}_${id}_${ts}.inspect.json"
      echo "检测到 logs-collector 容器: $name ($id)"
      echo "  - 日志输出文件: $outfile"
      echo "  - inspect 信息文件: $inspect_outfile"
      # 先立即抓一份 inspect，避免容器用 --rm 很快被删除后无法排查
      docker inspect "$id" > "$inspect_outfile" 2>/dev/null || echo "docker inspect $id 失败" >> "$inspect_outfile"
      # 抓启动到退出整个生命周期的日志
      docker logs -f "$id" &> "$outfile" &
    fi
  done