#!/bin/bash

echo "[*] Installing required tools for recon..."

# Update and install dependencies
sudo apt update && sudo apt install -y git curl jq python3 python3-pip golang unzip

# Create ~/tools directory if not exists
mkdir -p ~/tools

# Add Go binaries to PATH (if not already)
if ! grep -q "export PATH=$PATH:$(go env GOPATH)/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
    export PATH=$PATH:$(go env GOPATH)/bin
fi

# Install Sublist3r
if ! command -v sublist3r &>/dev/null; then
    echo "[*] Installing Sublist3r..."
    git clone https://github.com/aboul3la/Sublist3r.git ~/tools/Sublist3r
    sudo pip3 install -r ~/tools/Sublist3r/requirements.txt
    sudo ln -sf ~/tools/Sublist3r/sublist3r.py /usr/local/bin/sublist3r
fi

# Install assetfinder
if ! command -v assetfinder &>/dev/null; then
    echo "[*] Installing assetfinder..."
    go install github.com/tomnomnom/assetfinder@latest
fi

# Install subfinder
if ! command -v subfinder &>/dev/null; then
    echo "[*] Installing subfinder..."
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
fi

# Install github-subdomains
if ! command -v github-subdomains &>/dev/null; then
    echo "[*] Installing github-subdomains..."
    go install github.com/gwen001/github-subdomains@latest
fi

# Install waybackurls
if ! command -v waybackurls &>/dev/null; then
    echo "[*] Installing waybackurls..."
    go install github.com/tomnomnom/waybackurls@latest
fi

# Install gau
if ! command -v gau &>/dev/null; then
    echo "[*] Installing gau..."
    go install github.com/lc/gau/v2/cmd/gau@latest
fi

# Install amass
if ! command -v amass &>/dev/null; then
    echo "[*] Installing amass..."
    sudo snap install amass
fi

# Install httpx
if ! command -v httpx &>/dev/null; then
    echo "[*] Installing httpx..."
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest
fi

# Install dnsx
if ! command -v dnsx &>/dev/null; then
    echo "[*] Installing dnsx..."
    go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
fi

# Install getJS
if ! command -v getJS &>/dev/null; then
    echo "[*] Installing getJS..."
    go install github.com/003random/getJS@latest
fi

# Install xnLinkFinder
if [ ! -d ~/tools/xnLinkFinder ]; then
    echo "[*] Installing xnLinkFinder..."
    git clone https://github.com/xnl-h4ck3r/xnLinkFinder.git ~/tools/xnLinkFinder
    cd ~/tools/xnLinkFinder || exit
    pip3 install -r requirements.txt
    sudo ln -sf ~/tools/xnLinkFinder/xnLinkFinder.py /usr/local/bin/xnLinkFinder
    cd - || exit
fi

# Install urless
if ! command -v urless &>/dev/null; then
    echo "[*] Installing urless..."
    go install github.com/fixthebug/urless@latest
fi

# Install nuclei
if ! command -v nuclei &>/dev/null; then
    echo "[*] Installing nuclei..."
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
fi

# Install rustscan
if ! command -v rustscan &>/dev/null; then
    echo "[*] Installing rustscan..."
    curl -s https://api.github.com/repos/RustScan/RustScan/releases/latest |
    grep "browser_download_url.*linux_amd64.deb" |
    cut -d '"' -f 4 |
    wget -qi - -O rustscan.deb &&
    sudo dpkg -i rustscan.deb && rm rustscan.deb
fi

echo "[✔] All tools installed successfully."
