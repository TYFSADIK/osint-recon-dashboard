#!/usr/bin/env bash
set -e

echo "========================================"
echo "  OSINT Recon Dashboard - Installer"
echo "========================================"

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get &>/dev/null; then
        DISTRO="debian"
    elif command -v dnf &>/dev/null; then
        DISTRO="fedora"
    elif command -v pacman &>/dev/null; then
        DISTRO="arch"
    else
        echo "Unsupported Linux distro. Supported: Debian/Ubuntu, Fedora/RHEL, Arch."
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    DISTRO="macos"
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is required on macOS. Install from https://brew.sh"
        exit 1
    fi
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

echo "Detected: $DISTRO"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Step 1: Python ---
echo ""
echo "[1/6] Installing Python..."
if [[ "$DISTRO" == "debian" ]]; then
    sudo apt-get update -q
    sudo apt-get install -y python3 python3-pip python3-venv
elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y python3 python3-pip
elif [[ "$DISTRO" == "arch" ]]; then
    sudo pacman -Sy --noconfirm python python-pip
elif [[ "$DISTRO" == "macos" ]]; then
    brew install python3 || true
fi

VENV_DIR="$HOME/.local/share/osint-dashboard-venv"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip -q
pip install -r "$SCRIPT_DIR/requirements.txt" -q
echo "  Python venv ready at $VENV_DIR"

# --- Step 2: System security tools ---
echo ""
echo "[2/6] Installing security tools..."
if [[ "$DISTRO" == "debian" ]]; then
    sudo apt-get install -y \
        nmap masscan nikto sqlmap hydra john hashcat \
        ncat gobuster ffuf whatweb enum4linux \
        amass 2>/dev/null || true
elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y \
        nmap masscan hydra john hashcat \
        ncat gobuster whatweb --skip-unavailable 2>/dev/null || true
    # nikto, sqlmap, enum4linux not in Fedora repos — installed below
elif [[ "$DISTRO" == "arch" ]]; then
    sudo pacman -Sy --noconfirm \
        nmap masscan nikto sqlmap hydra john hashcat \
        ncat gobuster ffuf whatweb || true
elif [[ "$DISTRO" == "macos" ]]; then
    brew install nmap masscan nikto sqlmap hydra john hashcat ncat whatweb gobuster ffuf || true
fi

# --- Step 3: Go tools ---
echo ""
echo "[3/6] Installing Go-based tools (subfinder, gau, ffuf, httpx)..."
if ! command -v go &>/dev/null; then
    if [[ "$DISTRO" == "debian" ]];  then sudo apt-get install -y golang-go
    elif [[ "$DISTRO" == "fedora" ]]; then sudo dnf install -y golang
    elif [[ "$DISTRO" == "arch" ]];   then sudo pacman -Sy --noconfirm go
    elif [[ "$DISTRO" == "macos" ]];  then brew install go
    fi
fi

export PATH="$PATH:$(go env GOPATH)/bin"

go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest  2>/dev/null || echo "  subfinder: failed (check Go install)"
go install github.com/lc/gau/v2/cmd/gau@latest                            2>/dev/null || echo "  gau: failed"
go install github.com/ffuf/ffuf/v2@latest                                  2>/dev/null || echo "  ffuf: failed"
go install github.com/projectdiscovery/httpx/cmd/httpx@latest              2>/dev/null || echo "  httpx: failed"
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest         2>/dev/null || echo "  nuclei: failed"
go install github.com/owasp-amass/amass/v4/...@master                      2>/dev/null || echo "  amass: failed"

# --- Step 4: Python-based tools ---
echo ""
echo "[4/6] Installing Python-based tools..."
pip install sqlmap      2>/dev/null || echo "  sqlmap: failed"
pip install sherlock-project 2>/dev/null || echo "  sherlock: failed"
pip install h8mail      2>/dev/null || echo "  h8mail: failed"
pip install pwntools    2>/dev/null || echo "  pwntools: failed"

# Nikto via git if not installed
if ! command -v nikto &>/dev/null; then
    NIKTO_DIR="$HOME/.local/share/nikto"
    if [[ ! -d "$NIKTO_DIR" ]]; then
        git clone --depth=1 https://github.com/sullo/nikto "$NIKTO_DIR"
    fi
    sudo ln -sf "$NIKTO_DIR/program/nikto.pl" /usr/local/bin/nikto 2>/dev/null || \
        echo "  nikto wrapper: needs manual setup — run: perl $NIKTO_DIR/program/nikto.pl"
fi

# enum4linux if not installed
if ! command -v enum4linux &>/dev/null; then
    curl -sL https://raw.githubusercontent.com/CiscoCXSecurity/enum4linux/master/enum4linux.pl \
        -o "$HOME/.local/bin/enum4linux.pl" 2>/dev/null || true
    if [[ -f "$HOME/.local/bin/enum4linux.pl" ]]; then
        printf '#!/bin/bash\nperl %s/.local/bin/enum4linux.pl "$@"\n' "$HOME" \
            > "$HOME/.local/bin/enum4linux"
        chmod +x "$HOME/.local/bin/enum4linux"
    fi
fi

# --- Step 5: Wordlists ---
echo ""
echo "[5/6] Setting up wordlists..."
WORDLIST_DIR="/usr/share/wordlists"
sudo mkdir -p "$WORDLIST_DIR/dirb"

if [[ ! -f "$WORDLIST_DIR/dirb/common.txt" ]]; then
    sudo curl -sL "https://raw.githubusercontent.com/v0re/dirb/master/wordlists/common.txt" \
        -o "$WORDLIST_DIR/dirb/common.txt" || echo "  common.txt: download failed"
fi

if [[ ! -f "$WORDLIST_DIR/rockyou.txt" ]]; then
    echo "  Downloading rockyou.txt (~134MB)..."
    sudo curl -sL \
        "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
        -o "$WORDLIST_DIR/rockyou.txt" 2>/dev/null || \
        echo "  rockyou.txt: download failed — install wordlists package manually"
fi

read -r -p "  Download SecLists (~2.5GB)? [y/N] " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SECLISTS_DIR="$HOME/SecLists"
    if [[ ! -d "$SECLISTS_DIR" ]]; then
        git clone --depth=1 https://github.com/danielmiessler/SecLists "$SECLISTS_DIR"
        echo "  SecLists at $SECLISTS_DIR"
    else
        echo "  SecLists already present at $SECLISTS_DIR"
    fi
fi

# --- Step 6: Systemd service (Linux only) ---
echo ""
echo "[6/6] Creating systemd service..."
if [[ "$DISTRO" != "macos" ]]; then
    SERVICE_FILE="/etc/systemd/system/osint-dashboard.service"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=OSINT Recon Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
Environment=PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$VENV_DIR/bin/python $SCRIPT_DIR/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    echo "  Service created."
    echo "  Start now:       sudo systemctl start osint-dashboard"
    echo "  Enable on boot:  sudo systemctl enable osint-dashboard"
fi

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo "  Manual start:"
echo "    source $VENV_DIR/bin/activate"
echo "    python $SCRIPT_DIR/main.py"
echo ""
echo "  Then open: http://localhost:5002"
echo ""
echo "  To add a tool: see CONTRIBUTING.md"
