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

# Find and install CUDA using the cuda.sh script
echo -e "${CYAN}${BOLD}[✓] Installing CUDA...${NC}"
# First, look for cuda.sh in the same directory as install.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUDA_SCRIPT="$SCRIPT_DIR/cuda.sh"

# If cuda.sh is not in the same directory, check the working directory
if [ ! -f "$CUDA_SCRIPT" ]; then
    CUDA_SCRIPT="$(pwd)/cuda.sh"
fi

# If cuda.sh is still not found, check in rl-swarm-main directory
if [ ! -f "$CUDA_SCRIPT" ] && [ -d "/rl-swarm" ]; then
    CUDA_SCRIPT="/rl-swarm/cuda.sh"
elif [ ! -f "$CUDA_SCRIPT" ] && [ -d "/rl-swarm-main" ]; then
    CUDA_SCRIPT="/rl-swarm-main/cuda.sh"
elif [ ! -f "$CUDA_SCRIPT" ] && [ -d "$HOME/rl-swarm-main" ]; then
    CUDA_SCRIPT="$HOME/rl-swarm-main/cuda.sh"
fi

# If cuda.sh is found, make it executable and run it
if [ -f "$CUDA_SCRIPT" ]; then
    echo -e "${GREEN}${BOLD}[✓] Found CUDA script at: $CUDA_SCRIPT${NC}"
    sudo chmod +x "$CUDA_SCRIPT"
    sudo bash "$CUDA_SCRIPT"
else
    echo -e "${RED}${BOLD}[✗] Could not find cuda.sh. CUDA installation skipped.${NC}"
    echo -e "${YELLOW}${BOLD}[!] Please install CUDA manually or run cuda.sh separately.${NC}"
fi

# Find and make run_rl_swarm.sh executable
echo -e "${CYAN}${BOLD}[✓] Making run_rl_swarm.sh executable...${NC}"
RL_SWARM_SCRIPT="$SCRIPT_DIR/run_rl_swarm.sh"

# If not in the same directory, check the working directory
if [ ! -f "$RL_SWARM_SCRIPT" ]; then
    RL_SWARM_SCRIPT="$(pwd)/run_rl_swarm.sh"
fi

# Check in other common locations
if [ ! -f "$RL_SWARM_SCRIPT" ] && [ -d "/rl-swarm" ]; then
    RL_SWARM_SCRIPT="/rl-swarm/run_rl_swarm.sh"
elif [ ! -f "$RL_SWARM_SCRIPT" ] && [ -d "/rl-swarm-main" ]; then
    RL_SWARM_SCRIPT="/rl-swarm-main/run_rl_swarm.sh"
elif [ ! -f "$RL_SWARM_SCRIPT" ] && [ -d "$HOME/rl-swarm-main" ]; then
    RL_SWARM_SCRIPT="$HOME/rl-swarm-main/run_rl_swarm.sh"
fi

if [ -f "$RL_SWARM_SCRIPT" ]; then
    echo -e "${GREEN}${BOLD}[✓] Found run_rl_swarm.sh at: $RL_SWARM_SCRIPT${NC}"
    sudo chmod +x "$RL_SWARM_SCRIPT"
    # Get the directory of the script
    RL_SWARM_DIR="$(dirname "$RL_SWARM_SCRIPT")"
    
    # Start a screen session named "gensyn"
    echo -e "${CYAN}${BOLD}[✓] Starting screen session named 'gensyn'...${NC}"
    echo -e "${YELLOW}${BOLD}[!] You can detach from the screen session using Ctrl+A+D${NC}"
    echo -e "${YELLOW}${BOLD}[!] You can reattach to the session using 'screen -r gensyn'${NC}"
    echo -e "${GREEN}${BOLD}[✓] Installation complete! Starting RL-Swarm in screen session...${NC}"

    # Start the screen session and run the script
    screen -dmS gensyn bash -c "cd \"$RL_SWARM_DIR\" && \"$RL_SWARM_SCRIPT\"; exec bash"
    
    echo -e "${GREEN}${BOLD}[✓] RL-Swarm is now running in a screen session named 'gensyn'${NC}"
    echo -e "${BLUE}${BOLD}[i] To view the running process, type: screen -r gensyn${NC}"
else
    echo -e "${RED}${BOLD}[✗] Could not find run_rl_swarm.sh. Cannot start RL-Swarm.${NC}"
    echo -e "${YELLOW}${BOLD}[!] Please locate run_rl_swarm.sh and run it manually.${NC}"
fi
