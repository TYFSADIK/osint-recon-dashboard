# osint-recon-dashboard

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL2-lightgrey.svg)

A browser-based dashboard that runs 22 security reconnaissance tools from a single interface. Built with FastAPI. Results are stored in SQLite and polled live from the UI.

Designed for CTF competitions, home labs, and security research. **Only use against systems you have permission to test.**

---

![Dashboard Screenshot](https://photo.tyfsadik.org/share/Oq45sk6htnBBym1iqIAClzJSqCmDsfWZIwxqHQkIrYCN6VpCNiqcVJUU2gW1RAA5tnk)

> 

---

## Quick Start

```bash
git clone https://github.com/your-username/osint-recon-dashboard
cd osint-recon-dashboard
bash install.sh
python main.py
```

Open `http://localhost:5002`.

---

## Installation

### Linux (Debian/Ubuntu, Fedora, Arch)

```bash
bash install.sh
```

The script:
- Detects your distro and installs system packages
- Creates a Python virtualenv at `~/.local/share/osint-dashboard-venv`
- Installs Go-based tools (subfinder, gau, ffuf, httpx, nuclei)
- Installs Python-based tools (sqlmap, sherlock, h8mail, pwntools)
- Downloads `rockyou.txt` and `dirb/common.txt` wordlists
- Optionally downloads SecLists (~2.5GB)
- Creates a systemd service

Start on boot:

```bash
sudo systemctl enable --now osint-dashboard
```

### macOS

```bash
brew install go python3
bash install.sh
```

### Windows

Requires PowerShell 5.1+ and Python 3.10+ already installed.

```powershell
.\install.ps1
```

Note: `masscan` and `enum4linux` are Linux-only. Use WSL2 for full tool coverage.

### Manual (any OS)

```bash
pip install -r requirements.txt
python main.py
```

Then install the tools you want individually and verify each one is on your `PATH`.

---

## Tools

| Tool | Category | Description |
|---|---|---|
| subfinder | OSINT | Fast passive subdomain discovery |
| amass | OSINT | Deep DNS enumeration (50+ sources) |
| theHarvester | OSINT | Email, employee, and subdomain harvesting |
| sherlock | OSINT | Username enumeration across 400+ sites |
| gau | OSINT | URL enumeration from archives and crawlers |
| h8mail | OSINT | Email breach and credential lookup |
| nmap (top 1000) | Active Recon | Service/version scan, top 1000 ports |
| nmap (full) | Active Recon | All 65535 ports |
| masscan | Active Recon | Ultra-fast full port scan |
| httpx | Active Recon | Probe live hosts and grab HTTP banners |
| whatweb | Active Recon | Web technology fingerprinting |
| gobuster-dns | Active Recon | Subdomain brute force |
| gobuster-dir | Web | Directory brute force |
| gobuster-dir-big | Web | Deep directory brute force (medium wordlist) |
| ffuf-dir | Web | Fast directory fuzzer |
| ffuf-param | Web | Parameter name discovery |
| nikto | Web | Web server vulnerability scan |
| nuclei | Web | Template-based vulnerability scanner |
| sqlmap | Web | SQL injection detection |
| enum4linux | Network | SMB/Windows enumeration (users, shares, policies) |
| john | Password | Hash cracking with rockyou.txt |
| hashcat | Password | GPU-accelerated MD5 cracking |

---

## Architecture

```
main.py          FastAPI app — routes, input validation, scan runner
static/
  index.html     Single-page frontend — no build step, no dependencies
scans.db         SQLite — created on first run, gitignored
```

**How a scan works:**

1. Browser POSTs `tool` and `target` to `/scan`
2. Backend validates `tool` against an allowlist and `target` against a strict regex
3. Scan is launched as a `BackgroundTask` using `subprocess.run()` with `shell=False`
4. Browser polls `/results/{scan_id}` every 2 seconds until `status == done`
5. Result is written to SQLite and returned

**Security model:**

- `shell=False` on all subprocess calls — shell metacharacters in the target have no effect
- Target input is validated against `^[a-zA-Z0-9@._:\-/]{1,512}$` before any command is built
- Scan ID is validated as `^[a-f0-9]{8}$` before any database lookup
- All user-supplied strings are HTML-escaped before insertion into the DOM

The dashboard is intended for trusted local networks. Do not expose port 5002 to the internet without adding authentication.

---

## Adding a New Tool

See [CONTRIBUTING.md](CONTRIBUTING.md) for a step-by-step guide with a full example.

Short version:

1. Install the tool on your system
2. Add one entry to `TOOL_DEFS` in `main.py` (list format, `{target}` placeholder)
3. Add one card to `static/index.html` in the right section
4. Add a row to the tool table in this README

---

## Troubleshooting

**Tool not found error in the output panel**

The tool is not on the PATH that the dashboard uses. Check:

```bash
which <toolname>
```

If it is in `~/.local/bin` or `~/go/bin`, these are included in the dashboard's PATH automatically. If it is elsewhere, add the directory to the `PATH` value in the systemd service file or at the top of `main.py`.

**Scan times out**

The timeout is 10 minutes per scan. Nmap full-port and amass scans can exceed this on large targets. Run them from the terminal directly for long jobs.

**Port 5002 already in use**

```bash
sudo lsof -i :5002
```

Kill the conflicting process or change the port in `main.py`:

```python
uvicorn.run(app, host='0.0.0.0', port=5003)
```

**masscan requires root**

```bash
sudo masscan ...
```

The dashboard runs as your user. masscan will fail without root unless you set the capability:

```bash
sudo setcap cap_net_raw+ep $(which masscan)
```

**SQLite database locked**

Multiple simultaneous scans share one SQLite connection. This is handled by opening and closing a connection per operation. If you see lock errors under heavy load, reduce concurrent scans.

---

## License

MIT — see [LICENSE](LICENSE).
