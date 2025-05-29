#!/bin/bash

set -euo pipefail

# General arguments
ROOT=$PWD

export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes

# Check if public multi-address is given else set to default
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

# Check if peer multi-address is given else set to default
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ" # gensyn coordinator node
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

# Check if host multi-address is given else set to default
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

# Path to an RSA private key. If this path does not exist, a new key pair will be created.
# Remove this file if you want a new PeerID.
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

SMALL_SWARM_CONTRACT="0x69C6e1D608ec64885E7b185d39b04B491a71768C"
BIG_SWARM_CONTRACT="0x6947c6E196a48B77eFa9331EC1E3e45f3Ee5Fd58"

# Will ignore any visible GPUs if set.
CPU_ONLY=${CPU_ONLY:-""}

# Set if successfully parsed from modal-login/temp-data/userData.json.
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

# Function to clean up the server process upon exit
cleanup() {
    echo_green ">> Shutting down trainer..."

    # Remove modal credentials if they exist
    rm -r $ROOT_DIR/modal-login/temp-data/*.json 2> /dev/null || true

    # Kill all processes belonging to this script's process group
    kill -- -$$ || true

    exit 0
}

trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect and display OS information
detect_os() {
    echo_green ">> System Detection:"
    echo -n "   OS: "
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        OS_NAME="macOS"
        OS_VERSION=$(sw_vers -productVersion)
        echo "macOS $OS_VERSION"
    elif [[ -f /etc/os-release ]]; then
        # Linux with /etc/os-release (most modern distros)
        source /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        echo "$NAME $VERSION_ID"
    elif command_exists lsb_release; then
        # Linux with lsb_release
        OS_NAME=$(lsb_release -si)
        OS_VERSION=$(lsb_release -sr)
        echo "$OS_NAME $OS_VERSION"
    elif [[ -f /etc/lsb-release ]]; then
        # Ubuntu/Debian style
        source /etc/lsb-release
        OS_NAME=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
        echo "$DISTRIB_ID $DISTRIB_RELEASE"
    elif [[ -f /etc/debian_version ]]; then
        # Debian without lsb-release
        OS_NAME="Debian"
        OS_VERSION=$(cat /etc/debian_version)
        echo "Debian $OS_VERSION"
    elif [[ -f /etc/redhat-release ]]; then
        # Red Hat/CentOS/Fedora
        OS_INFO=$(cat /etc/redhat-release)
        echo "$OS_INFO"
        OS_NAME=$(echo "$OS_INFO" | cut -d' ' -f1)
        OS_VERSION=$(echo "$OS_INFO" | grep -o '[0-9.]*' | head -1)
    else
        # Fallback for other Unix-like systems
        OS_NAME=$(uname -s)
        OS_VERSION=$(uname -r)
        echo "$OS_NAME $OS_VERSION"
    fi
    
    # Detect if running in WSL (Windows Subsystem for Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "   Running in Windows Subsystem for Linux (WSL)"
    fi
}

# Function to detect and display GPU information
detect_gpu() {
    # Check for NVIDIA GPU
    if command_exists nvidia-smi; then
        echo -n "   GPU: "
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
        GPU_NAME=$(echo "$GPU_INFO" | cut -d',' -f1 | xargs)
        GPU_MEMORY=$(echo "$GPU_INFO" | cut -d',' -f2 | xargs)
        echo "$GPU_NAME with ${GPU_MEMORY}MB VRAM"
        
        # Get available memory
        AVAILABLE_MEMORY=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1 | xargs)
        echo "   Available VRAM: ${AVAILABLE_MEMORY}MB"
        
        # Get CUDA version
        CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        echo "   CUDA Driver Version: $CUDA_VERSION"
        
        # Determine if memory is sufficient for different models based on updated requirements
        # Using available VRAM for better OOM protection
        if [ $AVAILABLE_MEMORY -ge 48000 ]; then
            echo "   Memory Status: Sufficient for all models (up to 72B parameters)"
            RECOMMENDED_MODEL="72B (or any smaller model)"
            VRAM_TIER="extreme" # Extreme VRAM (48GB+ free) - needed for 72B models
        elif [ $AVAILABLE_MEMORY -ge 30000 ]; then
            echo "   Memory Status: Sufficient for models up to 32B parameters"
            RECOMMENDED_MODEL="32B (or any smaller model)"
            VRAM_TIER="ultra_high" # Ultra-high VRAM (30GB+ free) - needed for 32B models
        elif [ $AVAILABLE_MEMORY -ge 19000 ]; then
            echo "   Memory Status: Sufficient for models up to 7B parameters"
            RECOMMENDED_MODEL="7B (or any smaller model)"
            VRAM_TIER="high" # High VRAM (19GB+ free) - minimum for 7B models
        elif [ $AVAILABLE_MEMORY -ge 10000 ]; then
            echo "   Memory Status: Sufficient for models up to 1.5B parameters"
            RECOMMENDED_MODEL="1.5B (or smaller)"
            VRAM_TIER="medium" # Medium available VRAM (10GB+ free)
        elif [ $AVAILABLE_MEMORY -ge 6000 ]; then
            echo "   Memory Status: Sufficient for models up to 0.5B parameters"
            RECOMMENDED_MODEL="0.5B"
            VRAM_TIER="low" # Low available VRAM (6GB+ free)
        else
            echo "   Memory Status: Limited VRAM. CPU mode recommended."
            RECOMMENDED_MODEL="0.5B (CPU mode)"
            VRAM_TIER="minimal" # Minimal VRAM (< 6GB free)
            CPU_ONLY="true"
        fi
        echo "   Recommended Model Size: $RECOMMENDED_MODEL"
        
    # Check for AMD GPU using rocm-smi
    elif command_exists rocm-smi; then
        echo -n "   GPU: "
        GPU_NAME=$(rocm-smi --showproductname | grep -oP 'GPU\[\d+\].*Card series:\K.*' | xargs)
        GPU_MEMORY=$(rocm-smi --showmeminfo vram | grep -oP 'GPU\[\d+\].*vram total memory:\s*\K\d+' | head -1)
        echo "AMD $GPU_NAME with ${GPU_MEMORY}MB VRAM"
        
        # Get available memory
        AVAILABLE_MEMORY=$(rocm-smi --showmeminfo vram | grep -oP 'GPU\[\d+\].*vram free memory:\s*\K\d+' | head -1)
        echo "   Available VRAM: ${AVAILABLE_MEMORY}MB"
        
        # Determine if memory is sufficient for different models based on updated requirements
        # Using available VRAM for better OOM protection
        if [ $AVAILABLE_MEMORY -ge 48000 ]; then
            echo "   Memory Status: Sufficient for all models (up to 72B parameters)"
            RECOMMENDED_MODEL="72B (or any smaller model)"
            VRAM_TIER="extreme" # Extreme VRAM (48GB+ free) - needed for 72B models
        elif [ $AVAILABLE_MEMORY -ge 30000 ]; then
            echo "   Memory Status: Sufficient for models up to 32B parameters"
            RECOMMENDED_MODEL="32B (or any smaller model)"
            VRAM_TIER="ultra_high" # Ultra-high VRAM (30GB+ free) - needed for 32B models
        elif [ $AVAILABLE_MEMORY -ge 19000 ]; then
            echo "   Memory Status: Sufficient for models up to 7B parameters"
            RECOMMENDED_MODEL="7B (or any smaller model)"
            VRAM_TIER="high" # High VRAM (19GB+ free) - minimum for 7B models
        elif [ $AVAILABLE_MEMORY -ge 10000 ]; then
            echo "   Memory Status: Sufficient for models up to 1.5B parameters"
            RECOMMENDED_MODEL="1.5B (or smaller)"
            VRAM_TIER="medium" # Medium available VRAM (10GB+ free)
        elif [ $AVAILABLE_MEMORY -ge 6000 ]; then
            echo "   Memory Status: Sufficient for models up to 0.5B parameters"
            RECOMMENDED_MODEL="0.5B"
            VRAM_TIER="low" # Low available VRAM (6GB+ free)
        else
            echo "   Memory Status: Limited VRAM. CPU mode recommended."
            RECOMMENDED_MODEL="0.5B (CPU mode)"
            VRAM_TIER="minimal" # Minimal VRAM (< 6GB free)
            CPU_ONLY="true"
        fi
        echo "   Recommended Model Size: $RECOMMENDED_MODEL"
        
    else
        # No GPU detected
        echo "   GPU: No compatible GPU detected. Using CPU mode."
        CPU_ONLY="true"
        VRAM_TIER="cpu" # CPU mode
    fi
}

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn

EOF

# Run system detection
detect_os
detect_gpu
echo ""

while true; do
    echo -en $GREEN_TEXT
    read -p ">> Would you like to connect to the Testnet? [Y/n] " yn
    echo -en $RESET_TEXT
    yn=${yn:-Y}  # Default to "Y" if the user presses Enter
    case $yn in
        [Yy]*)  CONNECT_TO_TESTNET=true && break ;;
        [Nn]*)  CONNECT_TO_TESTNET=false && break ;;
        *)  echo ">>> Please answer yes or no." ;;
    esac
done

# Determine swarm recommendation based on VRAM tier
RECOMMENDED_SWARM="A" # Default to Math (A) swarm

# Display recommendation based on available VRAM
if [[ "$VRAM_TIER" == "extreme" ]]; then
    # Extreme available VRAM (48GB+ free) - Both swarms are viable with larger models
    echo_green ">> Based on your system with ${AVAILABLE_MEMORY}MB available VRAM:"
    echo "   - You can join either Math (A) or Math Hard (B) swarm"
    echo "   - Your GPU can handle models up to 72B parameters for Math (A)"
    echo "   - For Math Hard (B), you can use up to 1.5B parameters"
    # No specific recommendation needed - both are fine
elif [[ "$VRAM_TIER" == "ultra_high" ]]; then
    # Ultra-high available VRAM (30GB+ free) - Both swarms are viable with 32B models
    echo_green ">> Based on your system with ${AVAILABLE_MEMORY}MB available VRAM:"
    echo "   - You can join either Math (A) or Math Hard (B) swarm"
    echo "   - Your GPU can handle models up to 32B parameters for Math (A)"
    echo "   - For Math Hard (B), you can use up to 1.5B parameters"
    # No specific recommendation needed - both are fine
elif [[ "$VRAM_TIER" == "high" ]]; then
    # High available VRAM (19GB+ free) - Math (A) swarm with 7B is viable
    echo_green ">> Based on your system with ${AVAILABLE_MEMORY}MB available VRAM:"
    echo "   - We recommend joining Math (A) swarm"
    echo "   - Your GPU has enough VRAM for 7B parameter models"
    echo "   - For Math Hard (B) swarm, you'll be limited to smaller models (0.5B, 1.5B)"
    RECOMMENDED_SWARM="A"
elif [[ "$VRAM_TIER" == "medium" ]]; then
    # Medium available VRAM (10GB+ free) - Math (A) with smaller models
    echo_green ">> Based on your system with ${AVAILABLE_MEMORY}MB available VRAM:"
    echo "   - We recommend joining Math (A) swarm"
    echo "   - Your GPU can handle models up to 1.5B parameters"
    echo "   - For Math Hard (B) swarm, you'll be limited to 0.5B parameter models"
    RECOMMENDED_SWARM="A"
else
    # Lower VRAM - Math (A) with 0.5B is safest
    echo_green ">> Based on your system with ${AVAILABLE_MEMORY}MB available VRAM:"
    echo "   - We recommend joining Math (A) swarm with the 0.5B parameter model"
    echo "   - Limited VRAM detected - using small models is recommended to avoid OOM errors"
    RECOMMENDED_SWARM="A"
fi

while true; do
    echo -en $GREEN_TEXT
    read -p ">> Which swarm would you like to join (Math (A) or Math Hard (B))? [${RECOMMENDED_SWARM}/$(if [[ "$RECOMMENDED_SWARM" == "A" ]]; then echo "b"; else echo "a"; fi)] " ab
    echo -en $RESET_TEXT
    ab=${ab:-$RECOMMENDED_SWARM}  # Default to recommended swarm if the user presses Enter
    case $ab in
        [Aa]*)  USE_BIG_SWARM=false && break ;;
        [Bb]*)  USE_BIG_SWARM=true && break ;;
        *)  echo ">>> Please answer A or B." ;;
    esac
done

if [ "$USE_BIG_SWARM" = true ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
    # Math Hard (B) has different parameter options
    echo_green ">> Selected Math Hard (B) swarm"
    
    # Set available parameter options based on VRAM tier
    if [[ "$VRAM_TIER" == "extreme" || "$VRAM_TIER" == "ultra_high" || "$VRAM_TIER" == "high" ]]; then
        # 19GB+ free VRAM - Can use 0.5B or 1.5B for Math Hard
        PARAM_OPTIONS="0.5, 1.5"
        RECOMMENDED_PARAM="1.5"
    else
        # Lower VRAM - Only 0.5B is safe for Math Hard
        PARAM_OPTIONS="0.5"
        RECOMMENDED_PARAM="0.5"
    fi
    
    echo "   Available parameter sizes for Math Hard: ${PARAM_OPTIONS} billion"
    
    # Get parameter selection
    while true; do
        echo -en $GREEN_TEXT
        read -p ">> How many parameters (in billions)? [${PARAM_OPTIONS}] (recommended: ${RECOMMENDED_PARAM}) " pc
        echo -en $RESET_TEXT
        pc=${pc:-$RECOMMENDED_PARAM}  # Default to recommended parameter size
        
        if [[ "$VRAM_TIER" == "extreme" || "$VRAM_TIER" == "ultra_high" || "$VRAM_TIER" == "high" ]]; then
            case $pc in
                0.5 | 1.5) PARAM_B=$pc && break ;;
                *) echo ">>> Please answer with one of these options: ${PARAM_OPTIONS}" ;;
            esac
        else
            case $pc in
                0.5) PARAM_B=$pc && break ;;
                1.5) 
                    echo ">>> Warning: 1.5B models for Math Hard require at least 19GB of free VRAM."
                    echo "   Your system has ${AVAILABLE_MEMORY}MB of free VRAM."
                    echo "   Downgrading to 0.5B parameters to avoid OOM errors."
                    PARAM_B="0.5" && break ;;
                *) echo ">>> With your current VRAM, only 0.5B parameter model is supported for Math Hard" && PARAM_B="0.5" && break ;;
            esac
        fi
    done
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
    # Math (A) has different parameter options
    echo_green ">> Selected Math (A) swarm"
    
    # Set available parameter options based on VRAM tier
    if [[ "$VRAM_TIER" == "extreme" ]]; then
        # 48GB+ free VRAM - Can use all models including 72B
        PARAM_OPTIONS="0.5, 1.5, 7, 32, 72"
        RECOMMENDED_PARAM="72"
    elif [[ "$VRAM_TIER" == "ultra_high" ]]; then
        # 30GB+ free VRAM - Can use models up to 32B
        PARAM_OPTIONS="0.5, 1.5, 7, 32"
        RECOMMENDED_PARAM="32"
    elif [[ "$VRAM_TIER" == "high" ]]; then
        # 19GB+ free VRAM - Can use models up to 7B
        PARAM_OPTIONS="0.5, 1.5, 7"
        RECOMMENDED_PARAM="7"
    else
        # Less than 19GB free VRAM - Can only safely use 0.5B and 1.5B
        PARAM_OPTIONS="0.5, 1.5"
        RECOMMENDED_PARAM="1.5"
    fi
    
    echo "   Available parameter sizes for Math: ${PARAM_OPTIONS} billion"
    
    # Get parameter selection
    while true; do
        echo -en $GREEN_TEXT
        read -p ">> How many parameters (in billions)? [${PARAM_OPTIONS}] (recommended: ${RECOMMENDED_PARAM}) " pc
        echo -en $RESET_TEXT
        pc=${pc:-$RECOMMENDED_PARAM}  # Default to recommended parameter size
        
        if [[ "$VRAM_TIER" == "extreme" ]]; then
            case $pc in
                0.5 | 1.5 | 7 | 32 | 72) PARAM_B=$pc && break ;;
                *) echo ">>> Please answer with one of these options: ${PARAM_OPTIONS}" ;;
            esac
        elif [[ "$VRAM_TIER" == "ultra_high" ]]; then
            case $pc in
                0.5 | 1.5 | 7 | 32) PARAM_B=$pc && break ;;
                72) 
                    echo ">>> Warning: 72B models require at least 48GB of free VRAM."
                    echo "   Your system has ${AVAILABLE_MEMORY}MB of free VRAM."
                    echo "   Downgrading to 32B parameters for better performance."
                    PARAM_B="32" && break ;;
                *) echo ">>> Please answer with one of these options: ${PARAM_OPTIONS}" ;;
            esac
        elif [[ "$VRAM_TIER" == "high" ]]; then
            case $pc in
                0.5 | 1.5 | 7) PARAM_B=$pc && break ;;
                32 | 72) 
                    echo ">>> Warning: ${pc}B models require more VRAM than your system has available."
                    echo "   Downgrading to 7B parameters for better performance."
                    PARAM_B="7" && break ;;
                *) echo ">>> Please answer with one of these options: ${PARAM_OPTIONS}" ;;
            esac
        else
            case $pc in
                0.5 | 1.5) PARAM_B=$pc && break ;;
                7 | 32 | 72) 
                    echo ">>> Warning: ${pc}B models require at least 19GB of free VRAM."
                    echo "   Your system has ${AVAILABLE_MEMORY}MB of free VRAM."
                    echo "   Downgrading to 1.5B parameters for better performance."
                    PARAM_B="1.5" && break ;;
                *) echo ">>> Please answer with one of these options: ${PARAM_OPTIONS}" ;;
            esac
        fi
    done
fi

# Parameter validation is now handled during the selection process above
# No additional validation needed

# Determine appropriate memory fraction based on model size and available VRAM
determine_memory_fraction() {
    local param_size=$1
    local available_vram=$2
    
    # Default memory fraction
    local memory_fraction=0.95
    
    # Adjust memory fraction based on model size and available VRAM
    if [[ "$param_size" == "72" ]]; then
        # 72B models need careful memory management
        if [ $available_vram -ge 60000 ]; then
            memory_fraction=0.92
        else
            memory_fraction=0.90
        fi
    elif [[ "$param_size" == "32" ]]; then
        # 32B models
        if [ $available_vram -ge 40000 ]; then
            memory_fraction=0.92
        else
            memory_fraction=0.88
        fi
    elif [[ "$param_size" == "7" ]]; then
        # 7B models
        if [ $available_vram -ge 24000 ]; then
            memory_fraction=0.90
        else
            memory_fraction=0.85
        fi
    elif [[ "$param_size" == "1.5" ]]; then
        # 1.5B models
        if [ $available_vram -ge 16000 ]; then
            memory_fraction=0.90
        else
            memory_fraction=0.85
        fi
    else
        # 0.5B models - use lower fraction as they're smaller
        memory_fraction=0.85
    fi
    
    echo $memory_fraction
}

# Get recommended memory fraction
RECOMMENDED_MEMORY_FRACTION=$(determine_memory_fraction "$PARAM_B" "$AVAILABLE_MEMORY")

# Allow user to customize memory fraction
echo_green ">> Memory Configuration:"
echo "   Recommended memory fraction for ${PARAM_B}B model: ${RECOMMENDED_MEMORY_FRACTION}"
echo "   (Memory fraction controls how much of your available VRAM will be used)"
echo -en $GREEN_TEXT
read -p ">> Enter memory fraction [0.5-0.95] or press Enter for recommended value (${RECOMMENDED_MEMORY_FRACTION}): " user_memory_fraction
echo -en $RESET_TEXT

# Validate and set the memory fraction
if [[ -z "$user_memory_fraction" ]]; then
    # User pressed Enter, use recommended value
    MEMORY_FRACTION=$RECOMMENDED_MEMORY_FRACTION
else
    # Validate user input (must be between 0.5 and 0.95)
    if [[ "$user_memory_fraction" =~ ^0?\.[5-9][0-9]?$ ]] && (( $(echo "$user_memory_fraction <= 0.95" | bc -l) )) && (( $(echo "$user_memory_fraction >= 0.5" | bc -l) )); then
        MEMORY_FRACTION=$user_memory_fraction
    else
        echo "   Invalid input. Using recommended value: ${RECOMMENDED_MEMORY_FRACTION}"
        MEMORY_FRACTION=$RECOMMENDED_MEMORY_FRACTION
    fi
fi

echo_green ">> Setting memory fraction to ${MEMORY_FRACTION} for ${PARAM_B}B parameter model"

# Update memory_utils.py with the new memory fraction
MEMORY_UTILS_PATH="$ROOT/hivemind_exp/runner/memory_utils.py"
if [[ -f "$MEMORY_UTILS_PATH" ]]; then
    # Create a backup of the original file
    cp "$MEMORY_UTILS_PATH" "${MEMORY_UTILS_PATH}.bak"
    
    # Read current value for comparison
    CURRENT_FRACTION=$(grep -o "DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+" "$MEMORY_UTILS_PATH" | cut -d= -f2 | xargs)
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "s/DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+/DEFAULT_MEMORY_FRACTION = ${MEMORY_FRACTION}/" "$MEMORY_UTILS_PATH"
    else
        # Linux version
        sed -i "s/DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+/DEFAULT_MEMORY_FRACTION = ${MEMORY_FRACTION}/" "$MEMORY_UTILS_PATH"
    fi
    
    # Verify the change was made
    NEW_FRACTION=$(grep -o "DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+" "$MEMORY_UTILS_PATH" | cut -d= -f2 | xargs)
    if [[ "$NEW_FRACTION" == "$MEMORY_FRACTION" ]]; then
        echo "   Successfully updated memory_utils.py from ${CURRENT_FRACTION} to ${MEMORY_FRACTION}"
    else
        echo "   Warning: Failed to update memory_utils.py. Using original settings."
        cp "${MEMORY_UTILS_PATH}.bak" "$MEMORY_UTILS_PATH"
    fi
    
    # Remove backup
    rm "${MEMORY_UTILS_PATH}.bak"
else
    echo "   Warning: memory_utils.py not found at expected path, using default memory settings"
fi

# Create logs directory if it doesn't exist
mkdir -p "$ROOT/logs"

if [ "$CONNECT_TO_TESTNET" = true ]; then
    # Select tunneling option
    echo -en $GREEN_TEXT
    echo ">> Select tunneling option for login server:"
    echo "   1) Local (default - http://localhost:3000)"
    echo "   2) Cloudflare Tunnel"
    echo "   3) Ngrok"
    echo "   4) Localtunnel"
    read -p ">> Enter option [1-4]: " tunnel_option
    echo -en $RESET_TEXT
    tunnel_option=${tunnel_option:-1}  # Default to option 1 if the user presses Enter
    
    # Run modal_login server.
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    # Check if the yarn command exists; if not, install Yarn.

    # Node.js + NVM setup
    if ! command -v node > /dev/null 2>&1; then
        echo "Node.js not found. Installing NVM and latest Node.js..."
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm install node
    else
        echo "Node.js is already installed: $(node -v)"
    fi

    if ! command -v yarn > /dev/null 2>&1; then
        # Detect Ubuntu (including WSL Ubuntu) and install Yarn accordingly
        if grep -qi "ubuntu" /etc/os-release 2> /dev/null || uname -r | grep -qi "microsoft"; then
            echo "Detected Ubuntu or WSL Ubuntu. Installing Yarn via apt..."
            curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
            echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
            sudo apt update && sudo apt install -y yarn
        else
            echo "Yarn not found. Installing Yarn globally with npm (no profile edits)…"
            # This lands in $NVM_DIR/versions/node/<ver>/bin which is already on PATH
            npm install -g --silent yarn
        fi
    fi

    ENV_FILE="$ROOT"/modal-login/.env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    else
        # Linux version
        sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    fi

    yarn install --immutable
    echo "Building server"
    yarn build > "$ROOT/logs/yarn.log" 2>&1
    
    # Start server based on selected tunneling option
    SERVER_URL="http://localhost:3000"
    
    case $tunnel_option in
        1)
            # Default local server
            echo_green ">> Starting server with local access..."
            yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
            SERVER_PID=$!
            echo "Started server process: $SERVER_PID"
            sleep 5
            ;;
        2)
            # Cloudflare Tunnel
            if ! command_exists cloudflared; then
                echo_green ">> Cloudflare Tunnel not found. Installing..."
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    brew install cloudflare/cloudflare/cloudflared
                elif grep -qi "ubuntu" /etc/os-release 2> /dev/null || uname -r | grep -qi "microsoft"; then
                    # Ubuntu/Debian
                    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
                    sudo dpkg -i cloudflared.deb
                    rm cloudflared.deb
                else
                    # Generic Linux
                    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
                    chmod +x cloudflared
                    sudo mv cloudflared /usr/local/bin/
                fi
            fi
            
            echo_green ">> Starting server with Cloudflare Tunnel..."
            yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
            SERVER_PID=$!
            sleep 5
            
            # Start Cloudflare Tunnel
            echo_green ">> Starting Cloudflare Tunnel..."
            cloudflared tunnel --url http://localhost:3000 > "$ROOT/logs/cloudflare_tunnel.log" 2>&1 &
            TUNNEL_PID=$!
            
            # Extract tunnel URL from logs
            sleep 5
            SERVER_URL=$(grep -o 'https://.*\.trycloudflare\.com' "$ROOT/logs/cloudflare_tunnel.log" | head -1)
            if [ -z "$SERVER_URL" ]; then
                echo "Could not find Cloudflare Tunnel URL, defaulting to localhost"
                SERVER_URL="http://localhost:3000"
            fi
            echo_green ">> Cloudflare Tunnel URL: $SERVER_URL"
            ;;
        3)
            # Ngrok
            if ! command_exists ngrok; then
                echo_green ">> Ngrok not found. Installing..."
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    brew install ngrok/ngrok/ngrok
                else
                    # Linux
                    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
                    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
                    sudo apt update && sudo apt install ngrok
                fi
                
                echo_green ">> Ngrok installed. Please configure your auth token:"
                echo ">> Visit https://dashboard.ngrok.com/get-started/your-authtoken to get your token"
                read -p ">> Enter your Ngrok auth token: " ngrok_token
                ngrok config add-authtoken "$ngrok_token"
            fi
            
            echo_green ">> Starting server with Ngrok tunnel..."
            yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
            SERVER_PID=$!
            sleep 5
            
            # Start Ngrok
            echo_green ">> Starting Ngrok tunnel..."
            ngrok http 3000 --log=stdout > "$ROOT/logs/ngrok.log" 2>&1 &
            TUNNEL_PID=$!
            
            # Extract tunnel URL from logs
            sleep 5
            SERVER_URL=$(grep -o 'https://.*\.ngrok\.io' "$ROOT/logs/ngrok.log" | head -1)
            if [ -z "$SERVER_URL" ]; then
                echo "Could not find Ngrok URL, defaulting to localhost"
                SERVER_URL="http://localhost:3000"
            fi
            echo_green ">> Ngrok tunnel URL: $SERVER_URL"
            ;;
        4)
            # Localtunnel
            if ! command_exists lt; then
                echo_green ">> Localtunnel not found. Installing..."
                npm install -g localtunnel
            fi
            
            echo_green ">> Starting server with Localtunnel..."
            yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
            SERVER_PID=$!
            sleep 5
            
            # Start Localtunnel
            echo_green ">> Starting Localtunnel..."
            lt --port 3000 > "$ROOT/logs/localtunnel.log" 2>&1 &
            TUNNEL_PID=$!
            
            # Extract tunnel URL from logs
            sleep 5
            SERVER_URL=$(grep -o 'https://.*\.loca\.lt' "$ROOT/logs/localtunnel.log" | head -1)
            if [ -z "$SERVER_URL" ]; then
                echo "Could not find Localtunnel URL, defaulting to localhost"
                SERVER_URL="http://localhost:3000"
            fi
            echo_green ">> Localtunnel URL: $SERVER_URL"
            ;;
        *)
            # Default to local in case of invalid input
            echo_green ">> Invalid option. Starting server with local access..."
            yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
            SERVER_PID=$!
            echo "Started server process: $SERVER_PID"
            sleep 5
            SERVER_URL="http://localhost:3000"
            ;;
    esac
    
    echo "Started server process: $SERVER_PID"
    
    # Try to open the URL in the default browser
    if open "$SERVER_URL" 2> /dev/null; then
        echo_green ">> Successfully opened $SERVER_URL in your default browser."
    else
        echo ">> Failed to open $SERVER_URL. Please open it manually."
    fi

    cd ..

    echo_green ">> Waiting for modal userData.json to be created..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 5  # Wait for 5 seconds before checking again
    done
    echo "Found userData.json. Proceeding..."

    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "Your ORG_ID is set to: $ORG_ID"

    # Wait until the API key is activated by the client
    echo "Waiting for API key to become activated..."
    while true; do
        # Use the appropriate URL based on the tunnel option
        STATUS=$(curl -s "$SERVER_URL/api/get-api-key-status?orgId=$ORG_ID")
        if [[ "$STATUS" == "activated" ]]; then
            echo "API key is activated! Proceeding..."
            break
        else
            echo "Waiting for API key to be activated..."
            sleep 5
        fi
    done
    
    # Kill the tunnel process if it exists
    if [ ! -z "$TUNNEL_PID" ]; then
        kill $TUNNEL_PID 2>/dev/null || true
        echo "Tunnel process terminated."
    fi
fi

echo_green ">> Getting requirements..."

pip install --upgrade pip
if [ -n "$CPU_ONLY" ] || ! command -v nvidia-smi &> /dev/null; then
    # CPU-only mode or no NVIDIA GPU found
    pip install -r "$ROOT"/requirements-cpu.txt
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml" # TODO: Fix naming.
    GAME="gsm8k"
else
    # NVIDIA GPU found
    pip install -r "$ROOT"/requirements-gpu.txt
    pip install flash-attn --no-build-isolation

    case "$PARAM_B" in
        32 | 72) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-bnb-4bit-deepseek-r1.yaml" ;;
        0.5 | 1.5 | 7) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml" ;;
        *) exit 1 ;;
    esac

    if [ "$USE_BIG_SWARM" = true ]; then
        GAME="dapo"
    else
        GAME="gsm8k"
    fi
fi

echo_green ">> Done!"

HF_TOKEN=${HF_TOKEN:-""}
if [ -n "${HF_TOKEN}" ]; then # Check if HF_TOKEN is already set and use if so. Else give user a prompt to choose.
    HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
    echo -en $GREEN_TEXT
    read -p ">> Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
    echo -en $RESET_TEXT
    yn=${yn:-N} # Default to "N" if the user presses Enter
    case $yn in
        [Yy]*) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN ;;
        [Nn]*) HUGGINGFACE_ACCESS_TOKEN="None" ;;
        *) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None" ;;
    esac
fi

echo_green ">> Good luck in the swarm!"
echo_blue ">> Post about rl-swarm on X/twitter! --> https://tinyurl.com/swarmtweet"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --contract_address "$SWARM_CONTRACT" \
        --config "$CONFIG_PATH" \
        --game "$GAME"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH" \
        --game "$GAME"
fi

wait  # Keep script running until Ctrl+C
