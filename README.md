# RL Swarm

TODO

## Requirements

Ensure you that you are using a supported machine/device/environment:

- arm64 or x86 CPU with minimum 16gb ram

OR

- CUDA devices (officially supported):
    - RTX 3090
    - RTX 4090
    - A100
    - H100

WITH

-  Python >=3.10 (for Mac, you will likely need to upgrade)


## Instructions:

### Run the swarm

```sh
python3 -m venv .venv
source .venv/bin/activate
./run_rl_swarm.sh
```

### Testnet participation

Please answer 'Y' (or just press enter), N is provided as an alternative flow but isn't currently maintained.


### Login

1. A browser window will pop open (you'll need to manually navigate to http://localhost:3000/ if you're on a VM).
2. Click 'login'.
3. Login with your preferred method.

### Huggingface

Optionally pair your HF account by using your HF token - [more here](https://huggingface.co/docs/hub/en/security-tokens).

### Initial peering and training

From this stage onward your device will be used to train a hyperscale machine learning system. You should see your peer register and vote on-chain [here](https://gensyn-testnet.explorer.alchemy.com/address/0x2fC68a233EF9E9509f034DD551FF90A79a0B8F82?tab=logs).


## Troubleshooting

- **My model doesn't seem to be training?**
    - If you're using a consumer device (e.g. a MacBook), it is likely just running slowly - check back in 20 minutes.
- **Logging in with a new account after previous login?**
    
    - Make sure you click 'Logout' on the login screen before you leave your previous session
    - Make sure you delete `swarm.pem` from the root directory (try `sudo rm swarm.pem`). If you don't do this, and you previously registered with the peer-id stored in this file, it will disrupt the training process.
- **Issues on VMs?**

    - **How do I access the login screen if I'm running in a VM?**: port forwarding. Add this SSH flag: `-L 3000:localhost:3000` when connecting to your VM. E.g. `gcloud compute ssh --zone "us-central1-a" [your-vm] --project [your-project] -- -L 3000:localhost:3000`
    - **Disconnection/general issues**: If you are tunneling to a VM and suffer a broken pipe, you will likely encounter OOM or unexepected behaviour the first time you relaunch the script. If you `control + c` and kill the script it should spin down all background processes. Restart the script and everything should work normally.
- **Issues with npm/general installation?**

    - Try  `npm install -g node@latest`

- **OOM errors on MacBook?**
    - Try this (experimental) fix to increase memory:
        ```
        export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
        ```
- **I have multiple GPUs on one machine, can I run multiple peers?**: Yes - but you'll need to manually change things. You'll need to isolate each GPU, install this repo for each GPU, and expose each peer under a different port to pass the modal onboard.

- **My round/stage is behind the smart contract/other peers?**: This is expected behaviour given the different speeds of machines in the network. Once your machine completes it's current round, it will move to the the current round.

## Swarm UI
To launch the Swarm UI, run `docker-compose up --build` and open `0.0.0.0:8080` in your browser.

See the [web/README](./web/README.md) for more details.
