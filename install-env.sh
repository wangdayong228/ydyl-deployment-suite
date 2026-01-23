#! /bin/bash

set -euo pipefail
trap 'echo "Line $LINENO: Error: $?"' ERR

ensure_cmd() {
  local cmd="$1"
  local installer="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "未安装 $cmd，开始安装"
    "$installer"
  else
    echo "已安装 $cmd"
  fi
}

install_foundry() {
  curl -L https://foundry.paradigm.xyz | bash
  echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
  echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.zshrc
  # 临时让当前脚本能找到 foundryup
  export PATH="$HOME/.foundry/bin:$PATH"
  foundryup
}

install_go() {
  wget -v https://go.dev/dl/go1.25.5.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.5.linux-amd64.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
  export PATH="$PATH:/usr/local/go/bin"
}

install_polycli() {
  wget -v https://github.com/0xPolygon/polygon-cli/releases/download/v0.1.97/polycli_v0.1.97_linux_amd64.tar.gz
  tar -xzvf polycli_v0.1.97_linux_amd64.tar.gz
  sudo mv ./polycli_v0.1.97_linux_amd64 /usr/local/go/bin/polycli
}

install_jq() {
  sudo apt update
  sudo apt install -y jq
}

install_make() {
  sudo apt update
  sudo apt install -y make
}

install_nvm() {
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  echo 'export NVM_DIR="$HOME/.nvm"' >>~/.zshrc
  echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >>~/.zshrc

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

install_node() {
  nvm i 22 && nvm use 22
}

install_yarn() {
  npm install -g yarn
}

install_pm2() {
  npm install -g pm2
}



ensure_cmd "cast"    install_foundry
ensure_cmd "go"      install_go
ensure_cmd "polycli" install_polycli
ensure_cmd "jq"      install_jq
ensure_cmd "make"    install_make
ensure_cmd "nvm"     install_nvm
ensure_cmd "node"    install_node
ensure_cmd "yarn"    install_yarn
ensure_cmd "pm2"     install_pm2

# shellcheck disable=SC1091
source "$HOME/.ydyl-env"

# 设置 oh-my-zsh
if [ -z "${ZSH_CUSTOM:-}" ]; then
  echo "ZSH_CUSTOM 环境变量未设置，请自行下载 plugin 并设置"
else
  cd "$ZSH_CUSTOM/plugins"
  git clone https://github.com/zsh-users/zsh-autosuggestions
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
  echo "请在 ~/.zshrc 文件手动设置 oh-my-zsh 插件"
  echo "plugins=("
  echo "    git"
  echo "    zsh-autosuggestions"
  echo "    z"
  echo "    zsh-syntax-highlighting"
  echo ")"
fi