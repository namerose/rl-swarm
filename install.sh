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

# Setup compiler tools based on OS
echo -e "${CYAN}${BOLD}[✓] Setting up compiler tools...${NC}"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if command -v apt &>/dev/null; then
    echo -e "${CYAN}${BOLD}[✓] Debian/Ubuntu detected. Installing build-essential, gcc, g++...${NC}"
    sudo apt update > /dev/null 2>&1
    sudo apt install -y build-essential gcc g++ > /dev/null 2>&1

  elif command -v yum &>/dev/null; then
    echo -e "${CYAN}${BOLD}[✓] RHEL/CentOS detected. Installing Development Tools...${NC}"
    sudo yum groupinstall -y "Development Tools" > /dev/null 2>&1
    sudo yum install -y gcc gcc-c++ > /dev/null 2>&1

  elif command -v pacman &>/dev/null; then
    echo -e "${CYAN}${BOLD}[✓] Arch Linux detected. Installing base-devel...${NC}"
    sudo pacman -Sy --noconfirm base-devel gcc > /dev/null 2>&1

  else
    echo -e "${YELLOW}${BOLD}[!] Linux detected but unsupported package manager.${NC}"
  fi

elif [[ "$OSTYPE" == "darwin"* ]]; then
  echo -e "${CYAN}${BOLD}[✓] macOS detected. Installing Xcode Command Line Tools...${NC}"
  xcode-select --install > /dev/null 2>&1

else
  echo -e "${YELLOW}${BOLD}[!] Unsupported OS: $OSTYPE. Continuing anyway...${NC}"
fi

if command -v gcc &>/dev/null; then
  export CC=$(command -v gcc)
  echo -e "${CYAN}${BOLD}[✓] Exported CC=$CC${NC}"
else
  echo -e "${YELLOW}${BOLD}[!] gcc not found. CUDA installation may fail.${NC}"
fi

# Install CUDA
echo -e "${CYAN}${BOLD}[✓] Installing CUDA using local cuda.sh...${NC}"

# Find cuda.sh in standard locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUDA_SCRIPT="$SCRIPT_DIR/cuda.sh"

# If cuda.sh is not in the same directory, check the working directory
if [ ! -f "$CUDA_SCRIPT" ]; then
    CUDA_SCRIPT="$(pwd)/cuda.sh"
fi

# If cuda.sh is still not found, check in common locations
if [ ! -f "$CUDA_SCRIPT" ] && [ -d "/rl-swarm" ]; then
    CUDA_SCRIPT="/rl-swarm/cuda.sh"
elif [ ! -f "$CUDA_SCRIPT" ] && [ -d "$HOME/rl-swarm" ]; then
    CUDA_SCRIPT="$HOME/rl-swarm/cuda.sh"
fi

# If cuda.sh is found, fix line endings, make it executable and run it
if [ -f "$CUDA_SCRIPT" ]; then
    echo -e "${GREEN}${BOLD}[✓] Found CUDA script at: $CUDA_SCRIPT${NC}"
    
    # Fix Windows line endings (CRLF to LF)
    echo -e "${CYAN}${BOLD}[✓] Fixing Windows line endings in CUDA script...${NC}"
    
    # Method 1: Direct sed replacement for shebang line
    echo -e "${CYAN}${BOLD}[✓] Using sed to fix first line (shebang)...${NC}"
    sudo sed -i -e '1s/\r$//' "$CUDA_SCRIPT" 2>/dev/null || true
    
    # Method 2: Create a new script with correct line endings
    echo -e "${CYAN}${BOLD}[✓] Creating a clean version of the script...${NC}"
    TMP_SCRIPT=$(mktemp)
    cat "$CUDA_SCRIPT" | tr -d '\r' > "$TMP_SCRIPT"
    sudo chmod +x "$TMP_SCRIPT"
    
    # Execute the fixed script
    echo -e "${CYAN}${BOLD}[✓] Running CUDA installation...${NC}"
    sudo bash "$TMP_SCRIPT"
    rm "$TMP_SCRIPT"
else
    echo -e "${RED}${BOLD}[✗] Could not find cuda.sh. CUDA installation skipped.${NC}"
    echo -e "${YELLOW}${BOLD}[!] Please make sure cuda.sh is in the same directory as install.sh${NC}"
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
elif [ ! -f "$RL_SWARM_SCRIPT" ] && [ -d "$HOME/rl-swarm" ]; then
    RL_SWARM_SCRIPT="$HOME/rl-swarm/run_rl_swarm.sh"
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
