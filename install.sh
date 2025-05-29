#!/bin/bash

set -e

# ANSI color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}=========================================================${NC}"
echo -e "${BLUE}${BOLD}               RL-Swarm One-Step Installer               ${NC}"
echo -e "${BLUE}${BOLD}     Installs all dependencies and starts RL-Swarm       ${NC}"
echo -e "${BLUE}${BOLD}=========================================================${NC}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#--------------------
# CUDA Configuration
#--------------------
CPU_ONLY="false"
CUDA_INSTALLED=false
NVCC_PATH=""
CUDA_PATH=""
CUDA_VERSION=""
DRIVER_VERSION=""

detect_environment() {
    echo -e "\n${CYAN}${BOLD}>> Detecting system environment...${NC}"
    
    IS_WSL=false
    IS_RENTED_SERVER=false
    
    if grep -q Microsoft /proc/version 2>/dev/null; then
        echo -e "${YELLOW}${BOLD}[!] WSL environment detected${NC}"
        IS_WSL=true
    fi
    
    if [ -d "/opt/deeplearning" ] || [ -d "/opt/aws" ] || [ -d "/opt/cloud" ] || [ -f "/.dockerenv" ]; then
        echo -e "${YELLOW}${BOLD}[!] Rented/Cloud server environment detected${NC}"
        IS_RENTED_SERVER=true
    fi
    
    UBUNTU_VERSION=""
    if [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        UBUNTU_VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/os-release ]; then
        source /etc/os-release
        UBUNTU_VERSION=$(echo $VERSION_ID | tr -d '"')
    elif [ -f /etc/issue ]; then
        UBUNTU_VERSION=$(cat /etc/issue | grep -oP 'Ubuntu \K[0-9]+\.[0-9]+' | head -1)
    fi
    
    if [ -z "$UBUNTU_VERSION" ]; then
        if command -v lsb_release >/dev/null 2>&1; then
            UBUNTU_VERSION=$(lsb_release -rs)
        else
            apt-get update >/dev/null 2>&1
            apt-get install -y lsb-release >/dev/null 2>&1
            if command -v lsb_release >/dev/null 2>&1; then
                UBUNTU_VERSION=$(lsb_release -rs)
            else
                UBUNTU_VERSION="22.04"
            fi
        fi
    fi
    
    echo -e "${CYAN}${BOLD}[✓] System: Ubuntu ${UBUNTU_VERSION}, Architecture: $(uname -m)${NC}"
}

detect_gpu() {
    echo -e "\n${CYAN}${BOLD}>> Detecting NVIDIA GPU...${NC}"
    
    GPU_AVAILABLE=false
    
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via nvidia-smi)${NC}"
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        echo -e "${GREEN}${BOLD}[✓] NVIDIA driver version: ${DRIVER_VERSION}${NC}"
        
        # Get CUDA version directly from nvidia-smi
        DRIVER_CUDA_VERSION=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9.]+" 2>/dev/null)
        if [ -n "$DRIVER_CUDA_VERSION" ]; then
            echo -e "${GREEN}${BOLD}[✓] NVIDIA driver supports CUDA ${DRIVER_CUDA_VERSION}${NC}"
        fi
        
        GPU_AVAILABLE=true
        return 0
    fi
    
    if command -v lspci &> /dev/null && lspci | grep -i nvidia &> /dev/null; then
        echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via lspci)${NC}"
        GPU_AVAILABLE=true
        return 0
    fi
    
    if [ -d "/proc/driver/nvidia" ] || [ -d "/dev/nvidia0" ]; then
        echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via system directories)${NC}"
        GPU_AVAILABLE=true
        return 0
    fi
    
    if [ "$IS_RENTED_SERVER" = true ]; then
        echo -e "${YELLOW}${BOLD}[!] Running on a cloud/rented server, assuming GPU is available${NC}"
        GPU_AVAILABLE=true
        return 0
    fi
    
    if [ "$IS_WSL" = true ] && grep -q "nvidia" /mnt/c/Windows/System32/drivers/etc/hosts 2>/dev/null; then
        echo -e "${YELLOW}${BOLD}[!] WSL environment with potential NVIDIA drivers on Windows host${NC}"
        GPU_AVAILABLE=true
        return 0
    fi
    
    echo -e "${YELLOW}${BOLD}[!] No NVIDIA GPU detected - using CPU-only mode${NC}"
    CPU_ONLY="true"
    return 1
}

detect_cuda() {
    echo -e "\n${CYAN}${BOLD}>> Checking for CUDA installation...${NC}"
    
    CUDA_AVAILABLE=false
    NVCC_AVAILABLE=false
    CUDA_INSTALLED=false
    
    # First check for CUDA in common locations
    for cuda_dir in /usr/local/cuda* /usr/local/cuda; do
        if [ -d "$cuda_dir" ] && [ -d "$cuda_dir/bin" ] && [ -f "$cuda_dir/bin/nvcc" ]; then
            CUDA_PATH=$cuda_dir
            NVCC_PATH="$cuda_dir/bin/nvcc"
            
            if [ -x "$NVCC_PATH" ]; then
                CUDA_VERSION=$($NVCC_PATH --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
                [ -z "$CUDA_VERSION" ] && CUDA_VERSION=$(echo $cuda_dir | grep -oP 'cuda-\K[0-9.]+' || echo $(echo $cuda_dir | grep -oP 'cuda\K[0-9.]+'))
                echo -e "${GREEN}${BOLD}[✓] CUDA detected at ${CUDA_PATH} (version ${CUDA_VERSION})${NC}"
                CUDA_AVAILABLE=true
                CUDA_INSTALLED=true
                break
            fi
        fi
    done
    
    # If CUDA wasn't found in standard locations but nvcc is in PATH
    if [ "$CUDA_INSTALLED" = false ] && command -v nvcc &> /dev/null; then
        NVCC_PATH=$(which nvcc)
        CUDA_PATH=$(dirname $(dirname $NVCC_PATH))
        CUDA_VERSION=$(nvcc --version | grep -oP 'release \K[0-9.]+' | head -1)
        echo -e "${GREEN}${BOLD}[✓] NVCC detected: ${NVCC_PATH} (version ${CUDA_VERSION})${NC}"
        NVCC_AVAILABLE=true
        CUDA_AVAILABLE=true
        CUDA_INSTALLED=true
    fi
    
    # Use CUDA version from nvidia-smi if available
    if command -v nvidia-smi &> /dev/null; then
        DRIVER_CUDA_VERSION=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9.]+" 2>/dev/null)
        if [ -n "$DRIVER_CUDA_VERSION" ]; then
            # Use driver's CUDA version if we couldn't detect it through nvcc
            if [ -z "$CUDA_VERSION" ]; then
                CUDA_VERSION=$DRIVER_CUDA_VERSION
            fi
            CUDA_AVAILABLE=true
        fi
    fi
    
    # Check if environment paths are set up correctly
    if [ "$CUDA_INSTALLED" = true ]; then
        check_cuda_path
    fi
    
    return 0
}

check_cuda_path() {
    PATH_SET=false
    LD_LIBRARY_PATH_SET=false
    
    if [ -n "$CUDA_PATH" ]; then
        if [[ ":$PATH:" == *":$CUDA_PATH/bin:"* ]]; then
            PATH_SET=true
        fi
        
        if [[ ":$LD_LIBRARY_PATH:" == *":$CUDA_PATH/lib64:"* ]]; then
            LD_LIBRARY_PATH_SET=true
        fi
    fi
    
    if [ "$PATH_SET" = false ] || [ "$LD_LIBRARY_PATH_SET" = false ]; then
        echo -e "${YELLOW}${BOLD}[!] CUDA environment paths not properly set - auto-configuring now${NC}"
        setup_cuda_env
        return 1
    fi
    
    echo -e "${GREEN}${BOLD}[✓] CUDA environment paths are properly configured${NC}"
    return 0
}

setup_cuda_env() {
    echo -e "\n${CYAN}${BOLD}>> Setting up CUDA environment variables...${NC}"
    
    if [ -z "$CUDA_PATH" ]; then
        for cuda_dir in /usr/local/cuda* /usr/local/cuda; do
            if [ -d "$cuda_dir" ] && [ -d "$cuda_dir/bin" ]; then
                CUDA_PATH=$cuda_dir
                break
            fi
        done
    fi
    
    if [ -z "$CUDA_PATH" ] || [ ! -d "$CUDA_PATH" ]; then
        echo -e "${RED}${BOLD}[✗] Cannot find CUDA directory${NC}"
        return 1
    fi
    
    echo -e "${GREEN}${BOLD}[✓] Using CUDA path: ${CUDA_PATH}${NC}"
    
    # Create systemwide path setup
    sudo bash -c "cat > /etc/profile.d/cuda.sh" << EOL
#!/bin/bash
export PATH=${CUDA_PATH}/bin\${PATH:+:\${PATH}}
export LD_LIBRARY_PATH=${CUDA_PATH}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}
EOL
    sudo chmod +x /etc/profile.d/cuda.sh
    
    # Update current session
    export PATH=${CUDA_PATH}/bin${PATH:+:${PATH}}
    export LD_LIBRARY_PATH=${CUDA_PATH}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    
    # Add to .bashrc if it's not already there
    if ! grep -q "CUDA_HOME=${CUDA_PATH}" ~/.bashrc 2>/dev/null; then
        echo -e "\n# CUDA Path" >> ~/.bashrc
        echo "export CUDA_HOME=${CUDA_PATH}" >> ~/.bashrc
        echo "export PATH=\$CUDA_HOME/bin\${PATH:+:\${PATH}}" >> ~/.bashrc
        echo "export LD_LIBRARY_PATH=\$CUDA_HOME/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}" >> ~/.bashrc
    fi
    
    # Source bashrc to apply changes in current session
    source ~/.bashrc 2>/dev/null || true
    
    echo -e "${GREEN}${BOLD}[✓] CUDA environment variables configured and applied${NC}"
    return 0
}

#--------------------
# Main Installation Functions
#--------------------

# Function to install base dependencies
install_base_dependencies() {
    echo -e "\n${GREEN}${BOLD}>> Installing base system dependencies...${NC}"
    
    # Install sudo if it doesn't exist
    if ! command_exists sudo; then
        echo -e "Installing sudo..."
        apt update && apt install -y sudo
    fi
    
    # Install basic dependencies
    echo -e "Installing required packages..."
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip curl wget screen git lsof nano unzip iproute2 build-essential
    
    echo -e "${GREEN}${BOLD}[✓] Base dependencies installed successfully!${NC}"
}

# Function to install Node.js and npm
install_nodejs() {
    echo -e "\n${GREEN}${BOLD}>> Installing Node.js 20 and npm...${NC}"
    
    if ! command_exists node || [[ $(node -v 2>/dev/null) != v20* ]]; then
        echo -e "Node.js 20 not found. Installing..."
        # Remove old Node.js if it exists
        if command_exists node; then
            echo -e "Removing old Node.js version: $(node -v)"
            sudo apt remove -y nodejs npm || true
        fi
        
        # Install Node.js 20
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
        echo -e "Node.js $(node -v) installed successfully!"
    else
        echo -e "Node.js 20 is already installed: $(node -v)"
    fi
}

# Function to install Yarn
install_yarn() {
    echo -e "\n${GREEN}${BOLD}>> Installing Yarn package manager...${NC}"
    
    if ! command_exists yarn; then
        echo -e "Yarn not found. Installing..."
        sudo npm install -g yarn
        echo -e "Yarn $(yarn --version) installed successfully!"
    else
        echo -e "Yarn is already installed: $(yarn --version)"
    fi
}

# Function to install tunneling tools
install_tunneling_tools() {
    echo -e "\n${GREEN}${BOLD}>> Installing tunneling tools...${NC}"
    
    # Cloudflare Tunnel
    if ! command_exists cloudflared; then
        echo -e "Installing Cloudflare Tunnel..."
        curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    else
        echo -e "Cloudflare Tunnel is already installed."
    fi
    
    # Ngrok
    if ! command_exists ngrok; then
        echo -e "Installing Ngrok..."
        curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
        sudo apt update && sudo apt install -y ngrok
    else
        echo -e "Ngrok is already installed."
    fi
    
    # Localtunnel
    if ! command_exists lt; then
        echo -e "Installing Localtunnel..."
        sudo npm install -g localtunnel
    else
        echo -e "Localtunnel is already installed."
    fi
}

check_cuda_installation() {
    echo -e "\n${CYAN}${BOLD}>> Checking CUDA installation status...${NC}"
    
    detect_environment
    detect_gpu
    detect_cuda
    
    if [ "$CUDA_INSTALLED" = true ] && command -v nvcc &> /dev/null; then
        echo -e "${GREEN}${BOLD}[✓] CUDA is properly installed and available${NC}"
        if ! check_cuda_path; then
            :
        fi
        CPU_ONLY="false"
    elif [ "$GPU_AVAILABLE" = true ]; then
        echo -e "${YELLOW}${BOLD}[!] NVIDIA GPU detected but CUDA environment not fully configured${NC}"
        echo -e "${YELLOW}${BOLD}[!] Proceeding in CPU-only mode for now${NC}"
        CPU_ONLY="true"
    else
        echo -e "${YELLOW}${BOLD}[!] No NVIDIA GPU detected - using CPU-only mode${NC}"
        CPU_ONLY="true"
    fi
    
    if [ "$CPU_ONLY" = "true" ]; then
        echo -e "\n${YELLOW}${BOLD}[✓] Running in CPU-only mode${NC}"
    else
        echo -e "\n${GREEN}${BOLD}[✓] Running with GPU acceleration${NC}"
        
        if command -v nvidia-smi &> /dev/null; then
            echo -e "${CYAN}${BOLD}[✓] GPU information:${NC}"
            nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu --format=csv,noheader
        fi
    fi
    
    export CPU_ONLY
    return 0
}

# Main installation process
main() {
    echo -e "${CYAN}${BOLD}>> Starting RL-Swarm installation process...${NC}"
    
    # Install all dependencies
    install_base_dependencies
    install_nodejs
    install_yarn
    install_tunneling_tools
    check_cuda_installation
    
    # Make run_rl_swarm.sh executable if it exists
    if [[ -f "run_rl_swarm.sh" ]]; then
        chmod +x run_rl_swarm.sh
    else
        echo -e "${RED}${BOLD}[✗] Error: run_rl_swarm.sh not found in the current directory.${NC}"
        exit 1
    fi
    
    # Installation complete
    echo -e "\n${GREEN}${BOLD}=========================================================${NC}"
    echo -e "${GREEN}${BOLD}       Installation complete! Starting RL-Swarm...        ${NC}"
    echo -e "${GREEN}${BOLD}=========================================================${NC}"
    
    # Run the RL-Swarm script
    echo -e "Launching RL-Swarm...\n"
    
    # Export CPU_ONLY for run_rl_swarm.sh
    export CPU_ONLY
    
    # Execute the run_rl_swarm.sh script
    ./run_rl_swarm.sh
}

# Execute main function
main
