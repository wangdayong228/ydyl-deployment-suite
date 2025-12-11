#! /bin/bash
set -xeuo pipefail
trap 'echo "Line $LINENO: Error: $?"' ERR

sudo apt update && sudo apt install -y zsh
sudo chsh -s "$(which zsh)" ubuntu

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
