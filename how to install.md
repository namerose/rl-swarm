
# RL Swarm Setup Guide

## 1. Update System Packages

### ✅ Quickpod Provider or Similar (No `sudo` at first login)
```bash
apt update && apt install -y sudo
cd $HOME
sudo apt-get update && sudo apt-get upgrade -y
```

### ✅ Non-Quickpod (Already Supports `sudo`)
```bash
sudo apt-get update && sudo apt-get upgrade -y
```

## 2. Install General Utilities and Tools
```bash
sudo apt install screen curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y
```

## 3. Install Python
```bash
sudo apt-get install python3 python3-pip python3-venv python3-dev -y
```

## 4. Install Node
```bash
sudo apt-get update
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v
sudo npm install -g yarn
yarn -v
```

## 5. Install Yarn (Alt Method)
```bash
curl -o- -L https://yarnpkg.com/install.sh | bash
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
source ~/.bashrc
```

## 6. Clone the Repository and Start
```bash
git clone https://github.com/namerose/rl-swarm.git
cd rl-swarm
python3 -m venv .venv
source .venv/bin/activate
screen
./run_rl_swarm.sh
```

> ✅ Press `Y` when prompted.
