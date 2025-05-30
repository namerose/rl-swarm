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
export TUNNEL_TYPE=""

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
    
    # Shutdown tunnels based on TUNNEL_TYPE
    if [ -n "$TUNNEL_TYPE" ]; then
        echo ">> Shutting down $TUNNEL_TYPE tunnel..."
        
        # Kill by PID if we have it
        if [ -n "${TUNNEL_PID+x}" ]; then
            # Check if process exists before attempting to kill it
            if ps -p $TUNNEL_PID > /dev/null 2>&1; then
                kill $TUNNEL_PID 2> /dev/null || true
            fi
        fi
        
        # Also try to kill by process name as a backup
        case "$TUNNEL_TYPE" in
            "cloudflared")
                pkill -f "cloudflared tunnel" 2> /dev/null || true
                ;;
            "ngrok")
                pkill -f "ngrok http" 2> /dev/null || true
                ;;
            "localtunnel")
                pkill -f "lt --port" 2> /dev/null || true
                ;;
        esac
    fi
    
    # Kill server process if it exists
    if [ -n "${SERVER_PID+x}" ]; then
        echo ">> Shutting down server process..."
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            kill $SERVER_PID 2> /dev/null || true
        fi
    fi

    # Kill all processes belonging to this script's process group as a last resort
    kill -- -$$ 2> /dev/null || true

    echo_green ">> Cleanup completed. Exiting..."
    exit 0
}

trap cleanup EXIT

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn

EOF

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

# Add memory fraction customization
while true; do
    echo -en $GREEN_TEXT
    read -p ">> Would you like to customize the memory fraction to avoid OOM issues? [y/N] " mf_yn
    echo -en $RESET_TEXT
    mf_yn=${mf_yn:-N}  # Default to "N" if the user presses Enter
    case $mf_yn in
        [Yy]*)
            while true; do
                echo -en $GREEN_TEXT
                read -p ">> Enter memory fraction value (min: 0.82, default: 0.95): " mem_fraction
                echo -en $RESET_TEXT
                mem_fraction=${mem_fraction:-0.95}  # Default to 0.95 if the user presses Enter
                
                # Validate the input is a number and meets the minimum requirement
                if [[ $mem_fraction =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    # Extract integer and decimal parts
                    int_part=${mem_fraction%.*}
                    if [[ $mem_fraction == *.* ]]; then
                        dec_part=${mem_fraction#*.}
                    else
                        dec_part=0
                    fi
                    
                    # Compare with 0.82: either integer part > 0 or decimal part >= 82
                    if [[ $int_part -gt 0 ]] || [[ $int_part -eq 0 && $dec_part -ge 82 ]]; then
                        # Update memory_utils.py with the new value
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            # macOS version
                            sed -i '' "s/DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+/DEFAULT_MEMORY_FRACTION = $mem_fraction/" "$ROOT/hivemind_exp/runner/memory_utils.py"
                        else
                            # Linux version
                            sed -i "s/DEFAULT_MEMORY_FRACTION = 0\.[0-9]\+/DEFAULT_MEMORY_FRACTION = $mem_fraction/" "$ROOT/hivemind_exp/runner/memory_utils.py"
                        fi
                        echo_green ">> Memory fraction updated to $mem_fraction"
                        break
                    else
                        echo ">>> Please enter a valid number greater than or equal to 0.82."
                    fi
                else
                    echo ">>> Please enter a valid number."
                fi
            done
            break ;;
        [Nn]*)  
            echo_green ">> Using default memory fraction (0.95)"
            break ;;
        *)  echo ">>> Please answer yes or no." ;;
    esac
done

while true; do
    echo -en $GREEN_TEXT
    read -p ">> Which swarm would you like to join (Math (A) or Math Hard (B))? [A/b] " ab
    echo -en $RESET_TEXT
    ab=${ab:-A}  # Default to "A" if the user presses Enter
    case $ab in
        [Aa]*)  USE_BIG_SWARM=false && break ;;
        [Bb]*)  USE_BIG_SWARM=true && break ;;
        *)  echo ">>> Please answer A or B." ;;
    esac
done
if [ "$USE_BIG_SWARM" = true ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
fi
while true; do
    echo -en $GREEN_TEXT
    read -p ">> How many parameters (in billions)? [0.5, 1.5, 7, 32, 72] " pc
    echo -en $RESET_TEXT
    pc=${pc:-0.5}  # Default to "0.5" if the user presses Enter
    case $pc in
        0.5 | 1.5 | 7 | 32 | 72) PARAM_B=$pc && break ;;
        *)  echo ">>> Please answer in [0.5, 1.5, 7, 32, 72]." ;;
    esac
done

# Add training parameters customization
CUSTOM_PARAMS=false
while true; do
    echo -en $GREEN_TEXT
    read -p ">> Would you like to customize the training parameters? [y/N] " tp_yn
    echo -en $RESET_TEXT
    tp_yn=${tp_yn:-N}  # Default to "N" if the user presses Enter
    case $tp_yn in
        [Yy]*)
            CUSTOM_PARAMS=true
            # Ask for parameters one by one
            echo_green ">> Please enter values for the following parameters (press Enter to keep default):"
            
            # Get default values from the YAML file (will only be used as display defaults)
            DEFAULT_MAX_STEPS=20
            DEFAULT_NUM_GENERATIONS=4
            DEFAULT_BATCH_SIZE=4
            DEFAULT_GRAD_ACCUM=4
            DEFAULT_GRAD_CHECK="true"
            DEFAULT_LR_COEF=5
            DEFAULT_LOGGING_STEPS=2
            DEFAULT_SAVE_STEPS=25
            DEFAULT_WARMUP_RATIO=0.03
            DEFAULT_BETA=0.001
            DEFAULT_MAX_PROMPT_LENGTH=256
            DEFAULT_MAX_COMPLETION_LENGTH=1024
            
            # max_steps
            echo -en $GREEN_TEXT
            read -p ">> max_steps (default: $DEFAULT_MAX_STEPS): " max_steps
            echo -en $RESET_TEXT
            max_steps=${max_steps:-$DEFAULT_MAX_STEPS}
            
            # num_generations
            echo -en $GREEN_TEXT
            read -p ">> num_generations (default: $DEFAULT_NUM_GENERATIONS): " num_generations
            echo -en $RESET_TEXT
            num_generations=${num_generations:-$DEFAULT_NUM_GENERATIONS}
            
            # per_device_train_batch_size
            echo -en $GREEN_TEXT
            read -p ">> per_device_train_batch_size (default: $DEFAULT_BATCH_SIZE): " batch_size
            echo -en $RESET_TEXT
            batch_size=${batch_size:-$DEFAULT_BATCH_SIZE}
            
            # gradient_accumulation_steps
            echo -en $GREEN_TEXT
            read -p ">> gradient_accumulation_steps (default: $DEFAULT_GRAD_ACCUM): " grad_accum
            echo -en $RESET_TEXT
            grad_accum=${grad_accum:-$DEFAULT_GRAD_ACCUM}
            
            # gradient_checkpointing
            while true; do
                echo -en $GREEN_TEXT
                read -p ">> gradient_checkpointing [true/false] (default: $DEFAULT_GRAD_CHECK): " grad_check
                echo -en $RESET_TEXT
                grad_check=${grad_check:-$DEFAULT_GRAD_CHECK}
                case $grad_check in
                    true|false) break ;;
                    *) echo ">>> Please enter true or false." ;;
                esac
            done
            
            # learning_rate - only allow changing the coefficient (1-7), keep .0e-7 fixed
            while true; do
                echo -en $GREEN_TEXT
                read -p ">> learning_rate coefficient (1-7, default: $DEFAULT_LR_COEF): " lr_coef
                echo -en $RESET_TEXT
                lr_coef=${lr_coef:-$DEFAULT_LR_COEF}
                
                # Validate that input is a number between 1-7
                if [[ $lr_coef =~ ^[1-7]$ ]]; then
                    learning_rate="${lr_coef}.0e-7"
                    break
                else
                    echo ">>> Please enter a number between 1 and 7."
                fi
            done
            
            # logging_steps
            echo -en $GREEN_TEXT
            read -p ">> logging_steps (default: $DEFAULT_LOGGING_STEPS): " logging_steps
            echo -en $RESET_TEXT
            logging_steps=${logging_steps:-$DEFAULT_LOGGING_STEPS}
            
            # save_steps
            echo -en $GREEN_TEXT
            read -p ">> save_steps (default: $DEFAULT_SAVE_STEPS): " save_steps
            echo -en $RESET_TEXT
            save_steps=${save_steps:-$DEFAULT_SAVE_STEPS}
            
            # warmup_ratio
            echo -en $GREEN_TEXT
            read -p ">> warmup_ratio (default: $DEFAULT_WARMUP_RATIO): " warmup_ratio
            echo -en $RESET_TEXT
            warmup_ratio=${warmup_ratio:-$DEFAULT_WARMUP_RATIO}
            
            # beta
            echo -en $GREEN_TEXT
            read -p ">> beta (default: $DEFAULT_BETA): " beta
            echo -en $RESET_TEXT
            beta=${beta:-$DEFAULT_BETA}
            
            # max_prompt_length
            echo -en $GREEN_TEXT
            read -p ">> max_prompt_length (default: $DEFAULT_MAX_PROMPT_LENGTH): " max_prompt_length
            echo -en $RESET_TEXT
            max_prompt_length=${max_prompt_length:-$DEFAULT_MAX_PROMPT_LENGTH}
            
            # max_completion_length
            echo -en $GREEN_TEXT
            read -p ">> max_completion_length (default: $DEFAULT_MAX_COMPLETION_LENGTH): " max_completion_length
            echo -en $RESET_TEXT
            max_completion_length=${max_completion_length:-$DEFAULT_MAX_COMPLETION_LENGTH}
            
            echo_green ">> Parameters will be updated in the selected configuration file."
            break ;;
        [Nn]*)  
            # When user selects N, don't modify any YAML parameters
            echo_green ">> Using default training parameters from original YAML file (no modifications)"
            break ;;
        *)  echo ">>> Please answer yes or no." ;;
    esac
done

# Create logs directory if it doesn't exist
mkdir -p "$ROOT/logs"

if [ "$CONNECT_TO_TESTNET" = true ]; then
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
    yarn start >> "$ROOT/logs/yarn.log" 2>&1 & # Run in background and log output

    SERVER_PID=$!  # Store the process ID
    echo "Started server process: $SERVER_PID"
    sleep 5

    # Set default server URL
    SERVER_URL="http://localhost:3000"
    
    # Ask user if they want to use a tunneling service
    while true; do
        echo -en $GREEN_TEXT
        echo ">> Choose access method:"
        echo "   1. localhost (default, only accessible on this machine)"
        echo "   2. Cloudflare Tunnel (expose to internet)"
        echo "   3. Ngrok (expose to internet)"
        echo "   4. Localtunnel (expose to internet)"
        read -p ">> Enter your choice [1-4]: " tunnel_choice
        echo -en $RESET_TEXT
        tunnel_choice=${tunnel_choice:-1}  # Default to "1" if the user presses Enter
        
        case $tunnel_choice in
            1)  
                echo_green ">> Using localhost only." 
                break 
                ;;
            2)  
                echo_green ">> Setting up Cloudflare Tunnel..."
                # Check if cloudflared is installed
                if ! command -v cloudflared &> /dev/null; then
                    echo ">> Cloudflared not found. Installing..."
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        # macOS
                        brew install cloudflare/cloudflare/cloudflared
                    elif grep -qi "ubuntu\|debian" /etc/os-release 2> /dev/null; then
                        # Ubuntu/Debian
                        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
                        sudo dpkg -i cloudflared.deb
                        rm cloudflared.deb
                    else
                        echo ">> Automatic installation not supported for your OS."
                        echo ">> Please install cloudflared manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation"
                        echo ">> Using localhost instead."
                        break
                    fi
                fi
                
                # Start cloudflared tunnel in background with improved handling
                echo ">> Starting Cloudflare tunnel..."
                TUNNEL_TYPE="cloudflared"
                
                # Use nohup to ensure the process keeps running even if the parent shell exits
                nohup cloudflared tunnel --url http://localhost:3000 > "$ROOT/logs/cloudflared.log" 2>&1 &
                TUNNEL_PID=$!
                
                # Monitor to ensure the process starts and stays running
                counter=0
                MAX_WAIT=15
                TUNNEL_STARTED=false
                
                while [ $counter -lt $MAX_WAIT ]; do
                    # Check if process is still running
                    if ! ps -p $TUNNEL_PID > /dev/null; then
                        echo ">> Cloudflared process died. Trying to restart..."
                        nohup cloudflared tunnel --url http://localhost:3000 > "$ROOT/logs/cloudflared.log" 2>&1 &
                        TUNNEL_PID=$!
                    fi
                    
                    # Try to extract the URL from the log file
                    TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare\.com' "$ROOT/logs/cloudflared.log" | head -1)
                    
                    if [ -n "$TUNNEL_URL" ]; then
                        echo_green ">> Cloudflare Tunnel created: $TUNNEL_URL"
                        SERVER_URL="$TUNNEL_URL"
                        TUNNEL_STARTED=true
                        break
                    fi
                    
                    echo ">> Waiting for Cloudflare tunnel to initialize... ($counter/$MAX_WAIT)"
                    sleep 2
                    counter=$((counter + 1))
                done
                
                if [ "$TUNNEL_STARTED" = false ]; then
                    echo ">> Failed to create Cloudflare Tunnel after multiple attempts. Using localhost instead."
                    # Kill the process if it's still running but not producing a URL
                    if ps -p $TUNNEL_PID > /dev/null; then
                        kill $TUNNEL_PID 2>/dev/null || true
                        unset TUNNEL_PID
                    fi
                fi
                break 
                ;;
            3)  
                echo_green ">> Setting up Ngrok tunnel..."
                # Check if ngrok is installed
                if ! command -v ngrok &> /dev/null; then
                    echo ">> Ngrok not found. Installing..."
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        # macOS
                        brew install ngrok/ngrok/ngrok
                    else
                        # Download and install for Linux
                        curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
                        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
                        sudo apt update && sudo apt install ngrok
                    fi
                fi
                
                # Start ngrok tunnel in background with improved handling
                echo ">> Starting Ngrok tunnel..."
                TUNNEL_TYPE="ngrok"
                
                # Use nohup to ensure the process keeps running even if the parent shell exits
                nohup ngrok http 3000 > "$ROOT/logs/ngrok.log" 2>&1 &
                TUNNEL_PID=$!
                
                # Define multiple ways to extract the URL for resilience
                get_ngrok_url() {
                    # Method 1: Extract from API
                    local url=$(curl -s --connect-timeout 5 --max-time 10 http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"https://[^"]*' | sed 's/"public_url":"//g' | head -1)
                    
                    # If method 1 fails, try method 2: Extract directly from logs
                    if [ -z "$url" ]; then
                        url=$(grep -o "https://.*\.ngrok\.io" "$ROOT/logs/ngrok.log" 2>/dev/null | tail -1)
                    fi
                    
                    # If method 2 fails, try method 3: Look for Forwarding lines
                    if [ -z "$url" ]; then
                        url=$(grep -o "Forwarding.*https://[^ ]*" "$ROOT/logs/ngrok.log" 2>/dev/null | grep -o "https://[^ ]*" | tail -1)
                    fi
                    
                    echo "$url"
                }
                
                # Monitor to ensure the process starts and stays running
                counter=0
                MAX_WAIT=15
                TUNNEL_STARTED=false
                
                while [ $counter -lt $MAX_WAIT ]; do
                    # Check if process is still running
                    if ! ps -p $TUNNEL_PID > /dev/null 2>&1; then
                        echo ">> Ngrok process died. Trying to restart..."
                        nohup ngrok http 3000 > "$ROOT/logs/ngrok.log" 2>&1 &
                        TUNNEL_PID=$!
                        sleep 3
                    fi
                    
                    # Try to extract the URL
                    TUNNEL_URL=$(get_ngrok_url)
                    
                    if [ -n "$TUNNEL_URL" ]; then
                        echo_green ">> Ngrok Tunnel created: $TUNNEL_URL"
                        SERVER_URL="$TUNNEL_URL"
                        TUNNEL_STARTED=true
                        break
                    fi
                    
                    echo ">> Waiting for Ngrok tunnel to initialize... ($counter/$MAX_WAIT)"
                    sleep 2
                    counter=$((counter + 1))
                done
                
                if [ "$TUNNEL_STARTED" = false ]; then
                    echo ">> Failed to create Ngrok Tunnel after multiple attempts. Using localhost instead."
                    # Kill the process if it's still running but not producing a URL
                    if ps -p $TUNNEL_PID > /dev/null 2>&1; then
                        kill $TUNNEL_PID 2>/dev/null || true
                        unset TUNNEL_PID
                    fi
                fi
                break 
                ;;
            4)  
                echo_green ">> Setting up Localtunnel..."
                # Check if localtunnel is installed
                if ! command -v lt &> /dev/null; then
                    echo ">> Localtunnel not found. Installing..."
                    npm install -g localtunnel
                fi
                
                # Get the local IP address to use as password
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    LOCAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
                else
                    # Linux
                    LOCAL_IP=$(hostname -I | awk '{print $1}')
                fi
                
                # Start localtunnel in background with improved handling
                echo ">> Starting Localtunnel..."
                TUNNEL_TYPE="localtunnel"
                
                # Use nohup to ensure the process keeps running even if the parent shell exits
                nohup lt --port 3000 > "$ROOT/logs/localtunnel.log" 2>&1 &
                TUNNEL_PID=$!
                
                # Function to extract localtunnel URL using multiple methods
                get_localtunnel_url() {
                    # Method 1: Try the standard pattern
                    local url=$(grep -o 'https://.*\.loca\.lt' "$ROOT/logs/localtunnel.log" 2>/dev/null | head -1)
                    
                    # Method 2: Try a different pattern if method 1 fails
                    if [ -z "$url" ]; then
                        url=$(grep -o 'url: https://[^ ]*' "$ROOT/logs/localtunnel.log" 2>/dev/null | cut -d' ' -f2 | head -1)
                    fi
                    
                    # Method 3: Try to find any URL with loca.lt domain
                    if [ -z "$url" ]; then
                        url=$(grep -o 'https://[^[:space:]]*loca\.lt[^[:space:]]*' "$ROOT/logs/localtunnel.log" 2>/dev/null | head -1)
                    fi
                    
                    echo "$url"
                }
                
                # Monitor to ensure the process starts and stays running
                counter=0
                MAX_WAIT=15
                TUNNEL_STARTED=false
                
                while [ $counter -lt $MAX_WAIT ]; do
                    # Check if process is still running
                    if ! ps -p $TUNNEL_PID > /dev/null 2>&1; then
                        echo ">> Localtunnel process died. Trying to restart..."
                        nohup lt --port 3000 > "$ROOT/logs/localtunnel.log" 2>&1 &
                        TUNNEL_PID=$!
                        sleep 3
                    fi
                    
                    # Try to extract the URL
                    TUNNEL_URL=$(get_localtunnel_url)
                    
                    if [ -n "$TUNNEL_URL" ]; then
                        echo_green ">> Localtunnel created: $TUNNEL_URL"
                        echo_green ">> IMPORTANT: If prompted for a password, use your local IP address: $LOCAL_IP"
                        SERVER_URL="$TUNNEL_URL"
                        TUNNEL_STARTED=true
                        break
                    fi
                    
                    echo ">> Waiting for Localtunnel to initialize... ($counter/$MAX_WAIT)"
                    sleep 2
                    counter=$((counter + 1))
                done
                
                if [ "$TUNNEL_STARTED" = false ]; then
                    echo ">> Failed to create Localtunnel after multiple attempts. Using localhost instead."
                    # Kill the process if it's still running but not producing a URL
                    if ps -p $TUNNEL_PID > /dev/null 2>&1; then
                        kill $TUNNEL_PID 2>/dev/null || true
                        unset TUNNEL_PID
                    fi
                fi
                break 
                ;;
            *)  
                echo ">> Please enter a valid option (1-4)." 
                ;;
        esac
    done
    
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
    
    # Add a timeout mechanism (10 minutes = 600 seconds)
    TIMEOUT=600
    START_TIME=$(date +%s)
    
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
        
        if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
            echo "Timeout reached waiting for API key activation. Continuing anyway..."
            break
        fi
        
        # Add error handling for curl command
        STATUS=$(curl -s --connect-timeout 10 --max-time 30 "$SERVER_URL/api/get-api-key-status?orgId=$ORG_ID" || echo "connection_error")
        
        if [[ "$STATUS" == "activated" ]]; then
            echo "API key is activated! Proceeding..."
            break
        elif [[ "$STATUS" == "connection_error" ]]; then
            echo "Connection error when checking API key status. Retrying in 10 seconds..."
            sleep 10
        else
            REMAINING=$((TIMEOUT - ELAPSED_TIME))
            echo "Waiting for API key to be activated... (Timeout in $REMAINING seconds)"
            sleep 5
        fi
    done
fi

echo_green ">> Getting requirements..."

pip install --upgrade pip
# Function to update YAML config file with EXTENSIVE debugging
update_yaml_config() {
    local config_file=$1
    local temp_file="${config_file}.tmp"
    
    echo_green "======================= CONFIG UPDATE DEBUGGING ======================="
    echo_green ">> SELECTED MODEL: ${PARAM_B}B"
    echo_green ">> UPDATING CONFIG FILE: $config_file"
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        echo_green "ERROR: Config file does not exist: $config_file"
        echo_green "Current directory: $(pwd)"
        echo_green "Listing configs directory:"
        ls -la "$ROOT/hivemind_exp/configs/gpu/"
        return 1
    fi
    
    echo_green ">> Config file exists and is being read"
    echo_green ">> File size: $(wc -c < "$config_file") bytes"
    echo_green ">> File permissions: $(ls -l "$config_file")"
    
    # Display entire file content for debugging
    echo_green ">> ORIGINAL CONFIG FILE CONTENT:"
    cat "$config_file" | tee "$ROOT/logs/original_config.log"
    echo_green ">> End of original config"
    
    # Create a temporary file with clear error handling
    if ! > "$temp_file"; then
        echo_green "ERROR: Could not create temporary file: $temp_file"
        echo_green "Checking directory permissions: $(ls -ld "$(dirname "$temp_file")")"
        return 1
    fi
    
    echo_green ">> Successfully created temp file: $temp_file"
    
    # Count matches for each parameter before changes
    echo_green ">> PARAMETER SEARCH RESULTS:"
    echo "max_steps matches: $(grep -c "^[[:space:]]*max_steps:" "$config_file")"
    echo "num_generations matches: $(grep -c "^[[:space:]]*num_generations:" "$config_file")"
    echo "per_device_train_batch_size matches: $(grep -c "^[[:space:]]*per_device_train_batch_size:" "$config_file")"
    echo "gradient_accumulation_steps matches: $(grep -c "^[[:space:]]*gradient_accumulation_steps:" "$config_file")"
    echo "gradient_checkpointing matches: $(grep -c "^[[:space:]]*gradient_checkpointing:" "$config_file")"
    echo "learning_rate matches: $(grep -c "^[[:space:]]*learning_rate:" "$config_file")"
    echo "logging_steps matches: $(grep -c "^[[:space:]]*logging_steps:" "$config_file")"
    echo "save_steps matches: $(grep -c "^[[:space:]]*save_steps:" "$config_file")"
    echo "warmup_ratio matches: $(grep -c "^[[:space:]]*warmup_ratio:" "$config_file")"
    echo "beta matches: $(grep -c "^[[:space:]]*beta:" "$config_file")"
    echo "max_prompt_length matches: $(grep -c "^[[:space:]]*max_prompt_length:" "$config_file")"
    echo "max_completion_length matches: $(grep -c "^[[:space:]]*max_completion_length:" "$config_file")"
    
    # Show current parameter values
    echo_green ">> CURRENT PARAMETER VALUES:"
    grep "^[[:space:]]*max_steps:" "$config_file" || echo "max_steps not found"
    grep "^[[:space:]]*num_generations:" "$config_file" || echo "num_generations not found"
    grep "^[[:space:]]*per_device_train_batch_size:" "$config_file" || echo "per_device_train_batch_size not found"
    grep "^[[:space:]]*gradient_accumulation_steps:" "$config_file" || echo "gradient_accumulation_steps not found"
    grep "^[[:space:]]*gradient_checkpointing:" "$config_file" || echo "gradient_checkpointing not found"
    grep "^[[:space:]]*learning_rate:" "$config_file" || echo "learning_rate not found"
    grep "^[[:space:]]*logging_steps:" "$config_file" || echo "logging_steps not found"
    grep "^[[:space:]]*save_steps:" "$config_file" || echo "save_steps not found"
    grep "^[[:space:]]*warmup_ratio:" "$config_file" || echo "warmup_ratio not found"
    grep "^[[:space:]]*beta:" "$config_file" || echo "beta not found"
    grep "^[[:space:]]*max_prompt_length:" "$config_file" || echo "max_prompt_length not found"
    grep "^[[:space:]]*max_completion_length:" "$config_file" || echo "max_completion_length not found"
    
    echo_green ">> NEW PARAMETER VALUES TO SET:"
    echo "max_steps: $max_steps"
    echo "num_generations: $num_generations"
    echo "per_device_train_batch_size: $batch_size"
    echo "gradient_accumulation_steps: $grad_accum"
    echo "gradient_checkpointing: $grad_check"
    echo "learning_rate: $learning_rate"
    echo "logging_steps: $logging_steps"
    echo "save_steps: $save_steps"
    echo "warmup_ratio: $warmup_ratio"
    echo "beta: $beta"
    echo "max_prompt_length: $max_prompt_length"
    echo "max_completion_length: $max_completion_length"
    
    # Process the file line by line with detailed logging
    local changes_made=0
    local line_number=0
    
    echo_green ">> PROCESSING FILE LINE BY LINE:"
    while IFS= read -r line; do
        ((line_number++))
        # Check for each parameter and replace if found
        if [[ $line =~ ^[[:space:]]*max_steps:[[:space:]]* ]]; then
            echo "max_steps: $max_steps" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [max_steps: $max_steps]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*num_generations:[[:space:]]* ]]; then
            echo "num_generations: $num_generations" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [num_generations: $num_generations]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*per_device_train_batch_size:[[:space:]]* ]]; then
            echo "per_device_train_batch_size: $batch_size" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [per_device_train_batch_size: $batch_size]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*gradient_accumulation_steps:[[:space:]]* ]]; then
            echo "gradient_accumulation_steps: $grad_accum" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [gradient_accumulation_steps: $grad_accum]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*gradient_checkpointing:[[:space:]]* ]]; then
            echo "gradient_checkpointing: $grad_check" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [gradient_checkpointing: $grad_check]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*learning_rate:[[:space:]]* ]]; then
            echo "learning_rate: $learning_rate" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [learning_rate: $learning_rate]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*logging_steps:[[:space:]]* ]]; then
            echo "logging_steps: $logging_steps" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [logging_steps: $logging_steps]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*save_steps:[[:space:]]* ]]; then
            echo "save_steps: $save_steps" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [save_steps: $save_steps]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*warmup_ratio:[[:space:]]* ]]; then
            echo "warmup_ratio: $warmup_ratio" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [warmup_ratio: $warmup_ratio]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*beta:[[:space:]]* ]]; then
            echo "beta: $beta" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [beta: $beta]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*max_prompt_length:[[:space:]]* ]]; then
            echo "max_prompt_length: $max_prompt_length" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [max_prompt_length: $max_prompt_length]"
            ((changes_made++))
        elif [[ $line =~ ^[[:space:]]*max_completion_length:[[:space:]]* ]]; then
            echo "max_completion_length: $max_completion_length" >> "$temp_file"
            echo "Line $line_number: Changed [${line}] to [max_completion_length: $max_completion_length]"
            ((changes_made++))
        else
            # Keep unchanged lines
            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"
    
    echo_green ">> TOTAL CHANGES MADE: $changes_made"
    
    # Make a backup of the original file
    if ! cp "$config_file" "${config_file}.bak"; then
        echo_green "ERROR: Could not create backup file: ${config_file}.bak"
        return 1
    fi
    
    echo_green ">> Successfully created backup: ${config_file}.bak"
    
    # Replace the original file with our modified version
    if ! mv "$temp_file" "$config_file"; then
        echo_green "ERROR: Could not replace original file with modified version"
        echo_green "Temp file exists: $([ -f "$temp_file" ] && echo "Yes" || echo "No")"
        return 1
    fi
    
    echo_green ">> Successfully replaced original file with modified version"
    
    # Verify changes by displaying diff
    echo_green ">> DIFF BETWEEN ORIGINAL AND MODIFIED CONFIG:"
    diff "${config_file}.bak" "$config_file" || echo "No changes detected in diff! Check file format or permissions."
    
    # Final verification
    echo_green ">> FINAL CONFIG FILE CONTENT:"
    cat "$config_file" | tee "$ROOT/logs/updated_config.log"
    
    # Double-check parameters in final file
    echo_green ">> VERIFYING PARAMETERS IN FINAL FILE:"
    grep "^[[:space:]]*max_steps:" "$config_file" || echo "WARNING: max_steps not found in final file!"
    grep "^[[:space:]]*num_generations:" "$config_file" || echo "WARNING: num_generations not found in final file!"
    grep "^[[:space:]]*per_device_train_batch_size:" "$config_file" || echo "WARNING: per_device_train_batch_size not found in final file!"
    grep "^[[:space:]]*gradient_accumulation_steps:" "$config_file" || echo "WARNING: gradient_accumulation_steps not found in final file!"
    grep "^[[:space:]]*gradient_checkpointing:" "$config_file" || echo "WARNING: gradient_checkpointing not found in final file!"
    grep "^[[:space:]]*learning_rate:" "$config_file" || echo "WARNING: learning_rate not found in final file!"
    grep "^[[:space:]]*logging_steps:" "$config_file" || echo "WARNING: logging_steps not found in final file!"
    grep "^[[:space:]]*save_steps:" "$config_file" || echo "WARNING: save_steps not found in final file!"
    grep "^[[:space:]]*warmup_ratio:" "$config_file" || echo "WARNING: warmup_ratio not found in final file!"
    grep "^[[:space:]]*beta:" "$config_file" || echo "WARNING: beta not found in final file!"
    grep "^[[:space:]]*max_prompt_length:" "$config_file" || echo "WARNING: max_prompt_length not found in final file!"
    grep "^[[:space:]]*max_completion_length:" "$config_file" || echo "WARNING: max_completion_length not found in final file!"
    
    echo_green ">> Config file update process completed"
    echo_green "========================= END DEBUGGING ========================="
    
    # Return success if changes were made
    if [ $changes_made -gt 0 ]; then
        return 0
    else
        echo_green "WARNING: No changes were made to the config file!"
        return 1
    fi
}

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

# Update config with custom parameters ONLY if user requested customization
if [ "$CUSTOM_PARAMS" = true ]; then
    echo_green ">> Updating configuration with custom parameters"
    # Call the function but don't let its return code affect the script execution
    update_yaml_config "$CONFIG_PATH" || {
        echo_green ">> Warning: Configuration update may not have been successful, but proceeding anyway"
    }
    # Make sure the script continues even if the config update failed
    echo_green ">> Configuration update step completed, continuing with training"
else
    echo_green ">> Using original YAML file without modifications"
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
