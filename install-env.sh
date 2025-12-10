#! /bin/bash
#! /bin/bash
set -xeuo pipefail
trap 'echo "Line $LINENO: Error: $?"' ERR

curl -L https://foundry.paradigm.xyz | bash
echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.zshrc
# 临时让当前脚本能找到 foundryup
export PATH="$HOME/.foundry/bin:$PATH"
foundryup

wget -v https://go.dev/dl/go1.25.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
export PATH="$PATH:/usr/local/go/bin"

wget -v https://github.com/0xPolygon/polygon-cli/releases/download/v0.1.97/polycli_v0.1.97_linux_amd64.tar.gz
tar -xzvf polycli_v0.1.97_linux_amd64.tar.gz
sudo mv ./polycli_v0.1.97_linux_amd64 /usr/local/go/bin/polycli

sudo apt update
sudo apt install make

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
echo 'export NVM_DIR="$HOME/.nvm"' >>~/.zshrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >>~/.zshrc
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm i 22 && nvm use 22
npm install -g yarn
