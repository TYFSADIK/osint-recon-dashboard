# OSINT Recon Dashboard - Windows Installer
# Requires: PowerShell 5.1+ or PowerShell Core
# Some tools require Administrator rights

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OSINT Recon Dashboard - Installer"    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator"
)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator. Some installs may fail."
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Step 1: Python ---
Write-Host "`n[1/5] Checking Python..." -ForegroundColor Green
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python not found. Install Python 3.10+ from https://python.org and re-run."
    exit 1
}

$VenvDir = "$env:LOCALAPPDATA\osint-dashboard-venv"
python -m venv $VenvDir
& "$VenvDir\Scripts\Activate.ps1"
pip install --upgrade pip -q
pip install -r "$ScriptDir\requirements.txt" -q
Write-Host "  Python venv ready at $VenvDir"

# --- Step 2: Python-based security tools ---
Write-Host "`n[2/5] Installing Python-based tools..." -ForegroundColor Green
pip install sqlmap pwntools sherlock-project h8mail 2>$null
Write-Host "  sqlmap, pwntools, sherlock, h8mail installed via pip"

# --- Step 3: Native tools via winget ---
Write-Host "`n[3/5] Installing native tools via winget..." -ForegroundColor Green
$wingetTools = @(
    @{ id = "Nmap.Nmap";       name = "nmap" },
    @{ id = "OWASPFoundation.Gobuster"; name = "gobuster" },
    @{ id = "OpenSSL.OpenSSL"; name = "openssl" }
)
foreach ($t in $wingetTools) {
    try {
        winget install --id $t.id --accept-source-agreements --accept-package-agreements --silent 2>$null
        Write-Host "  $($t.name): installed"
    } catch {
        Write-Warning "  $($t.name): winget install failed — install manually"
    }
}

# hashcat
if (-not (Get-Command hashcat -ErrorAction SilentlyContinue)) {
    Write-Warning "  hashcat not found. Download from https://hashcat.net/hashcat/"
}

# john
if (-not (Get-Command john -ErrorAction SilentlyContinue)) {
    Write-Warning "  john not found. Download from https://www.openwall.com/john/"
}

# --- Step 4: Go-based tools ---
Write-Host "`n[4/5] Installing Go-based tools..." -ForegroundColor Green
if (Get-Command go -ErrorAction SilentlyContinue) {
    $gobin = "$(go env GOPATH)\bin"
    $env:PATH += ";$gobin"
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>$null
    go install github.com/lc/gau/v2/cmd/gau@latest                           2>$null
    go install github.com/ffuf/ffuf/v2@latest                                 2>$null
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest             2>$null
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest        2>$null
    Write-Host "  subfinder, gau, ffuf, httpx, nuclei installed to $gobin"
} else {
    Write-Warning "  Go not found. Install from https://go.dev to get subfinder, gau, ffuf, httpx, nuclei."
}

# --- Step 5: Wordlists ---
Write-Host "`n[5/5] Setting up wordlists..." -ForegroundColor Green
$WordlistDir = "$env:LOCALAPPDATA\wordlists"
New-Item -ItemType Directory -Force -Path $WordlistDir | Out-Null

$commonTxt = "$WordlistDir\common.txt"
if (-not (Test-Path $commonTxt)) {
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/v0re/dirb/master/wordlists/common.txt" `
            -OutFile $commonTxt -UseBasicParsing
        Write-Host "  common.txt downloaded to $WordlistDir"
    } catch {
        Write-Warning "  common.txt download failed — add wordlists manually"
    }
}

Write-Host ""
Write-Host "NOTE: masscan and enum4linux are Linux-only tools."
Write-Host "      Use WSL2 for full compatibility on Windows."
Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Installation Complete!"                 -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Start the dashboard:"
Write-Host "  & '$VenvDir\Scripts\Activate.ps1'"
Write-Host "  python $ScriptDir\main.py"
Write-Host ""
Write-Host "Then open: http://localhost:5002"
Write-Host ""
Write-Host "See CONTRIBUTING.md to add more tools."
