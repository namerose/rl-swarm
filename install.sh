#!/bin/bash

# Set colors for output
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
NC="\033[0m"

echo -e "${CYAN}${BOLD}[✓] Starting RL-Swarm installation process...${NC}"

# Change to home directory
cd $HOME

# Install sudo if not already installed
echo -e "${CYAN}${BOLD}[✓] Updating system and installing sudo...${NC}"
apt update && apt install -y sudo

# Install basic dependencies
echo -e "${CYAN}${BOLD}[✓] Installing required packages...${NC}"
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl wget screen git lsof nano unzip iproute2

# Install Node.js 20 and npm
echo -e "${CYAN}${BOLD}[✓] Installing Node.js 20 and npm...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
echo -e "${GREEN}${BOLD}[✓] Node.js $(node -v) and npm $(npm -v) installed successfully${NC}"

# Install CUDA using the cuda.sh script
echo -e "${CYAN}${BOLD}[✓] Installing CUDA...${NC}"
cd $(dirname $0)  # Go back to the script directory
chmod +x cuda.sh
./cuda.sh

# Make run_rl_swarm.sh executable
echo -e "${CYAN}${BOLD}[✓] Making run_rl_swarm.sh executable...${NC}"
chmod +x run_rl_swarm.sh

# Start a screen session named "gensyn"
echo -e "${CYAN}${BOLD}[✓] Starting screen session named 'gensyn'...${NC}"
echo -e "${YELLOW}${BOLD}[!] You can detach from the screen session using Ctrl+A+D${NC}"
echo -e "${YELLOW}${BOLD}[!] You can reattach to the session using 'screen -r gensyn'${NC}"
echo -e "${GREEN}${BOLD}[✓] Installation complete! Starting RL-Swarm in screen session...${NC}"

# Start the screen session and run the script
screen -dmS gensyn bash -c "cd $(pwd) && ./run_rl_swarm.sh; exec bash"

echo -e "${GREEN}${BOLD}[✓] RL-Swarm is now running in a screen session named 'gensyn'${NC}"
echo -e "${BLUE}${BOLD}[i] To view the running process, type: screen -r gensyn${NC}"
