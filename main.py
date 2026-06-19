from fastapi import FastAPI, Form, BackgroundTasks, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import subprocess
import sqlite3
import re
import os
from datetime import datetime
import uuid

app = FastAPI(title="Recon Dashboard")

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scans.db')

# Whitelist: domain, IP, IP:port, username, email, URL host, or absolute file path for crack tools
TARGET_RE = re.compile(r'^[a-zA-Z0-9@._:\-/]{1,512}$')

TOOL_DEFS = {
    # OSINT / Passive recon
    'subfinder':        ['subfinder', '-d', '{target}'],
    'amass':            ['amass', 'enum', '-d', '{target}'],
    'httpx':            ['httpx', '-u', '{target}'],
    'nuclei':           ['nuclei', '-u', '{target}', '-severity', 'low,medium,high,critical'],
    'theharvester':     ['theHarvester', '-d', '{target}', '-b', 'all'],
    'sherlock':         ['sherlock', '{target}'],
    'gau':              ['gau', '{target}'],
    'h8mail':           ['h8mail', '-t', '{target}'],
    # Active recon
    'nmap':             ['nmap', '-sV', '-sC', '-T4', '--top-ports', '1000', '{target}'],
    'nmap-full':        ['nmap', '-sV', '-sC', '-T4', '-p-', '{target}'],
    'masscan':          ['masscan', '{target}', '--rate=1000', '-p', '1-65535'],
    'gobuster-dir':     ['gobuster', 'dir', '-u', 'http://{target}', '-w',
                         '/usr/share/wordlists/dirb/common.txt', '-t', '50', '-q'],
    'gobuster-dir-big': ['gobuster', 'dir', '-u', 'http://{target}', '-w',
                         '/usr/share/wordlists/dirb/common.txt', '-t', '50', '-q'],
    'gobuster-dns':     ['gobuster', 'dns', '-d', '{target}', '-w',
                         '/usr/share/wordlists/dirb/common.txt', '-t', '50', '-q'],
    'ffuf-dir':         ['ffuf', '-u', 'http://{target}/FUZZ',
                         '-w', '/usr/share/wordlists/dirb/common.txt',
                         '-t', '50', '-mc', '200,301,302,403'],
    'ffuf-param':       ['ffuf', '-u', 'http://{target}?FUZZ=test',
                         '-w', '/usr/share/wordlists/dirb/common.txt',
                         '-t', '50', '-mc', '200,301,302'],
    'nikto':            ['nikto', '-h', '{target}'],
    # Web exploitation
    'sqlmap':           ['sqlmap', '-u', 'http://{target}',
                         '--batch', '--level=2', '--risk=1'],
    'whatweb':          ['whatweb', '{target}'],
    # Network / Windows
    'enum4linux':       ['enum4linux', '{target}'],
    # Password cracking (target = path to hash file)
    'john-common':      ['john', '{target}', '--wordlist=/usr/share/wordlists/rockyou.txt'],
    'hashcat-md5':      ['hashcat', '-m', '0', '{target}',
                         '/usr/share/wordlists/rockyou.txt', '--force'],
}

ALLOWED_TOOLS = set(TOOL_DEFS.keys())


def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS scans
                 (id TEXT PRIMARY KEY, tool TEXT, target TEXT,
                  status TEXT, result TEXT, created_at TEXT)''')
    conn.commit()
    conn.close()


init_db()

_static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')
app.mount('/static', StaticFiles(directory=_static_dir), name='static')


@app.get('/', response_class=HTMLResponse)
async def dashboard():
    with open(os.path.join(_static_dir, 'index.html'), 'r') as f:
        return f.read()


@app.post('/scan')
async def start_scan(background_tasks: BackgroundTasks,
                     tool: str = Form(...), target: str = Form(...)):
    if tool not in ALLOWED_TOOLS:
        raise HTTPException(status_code=400, detail='Unknown tool')
    if not TARGET_RE.match(target):
        raise HTTPException(
            status_code=400,
            detail='Invalid target — only alphanumeric, dots, hyphens, underscores, @, colons, and slashes allowed'
        )

    scan_id = str(uuid.uuid4())[:8]
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('INSERT INTO scans VALUES (?, ?, ?, ?, ?, ?)',
              (scan_id, tool, target, 'running', '', datetime.now().isoformat()))
    conn.commit()
    conn.close()

    background_tasks.add_task(run_scan, scan_id, tool, target)
    return {'scan_id': scan_id}


def build_cmd(tool: str, target: str) -> list:
    return [arg.replace('{target}', target) for arg in TOOL_DEFS[tool]]


def run_scan(scan_id: str, tool: str, target: str):
    cmd = build_cmd(tool, target)
    env = {
        **os.environ,
        'PATH': '/usr/local/bin:/usr/bin:/bin:'
                + os.path.expanduser('~/.local/bin') + ':'
                + os.path.expanduser('~/go/bin'),
    }
    try:
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=600, env=env
        )
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        output = 'Scan timed out after 10 minutes.'
    except FileNotFoundError:
        output = f'Tool not found: {cmd[0]}. Is it installed?'
    except Exception as e:
        output = f'Error: {e}'

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE scans SET status = ?, result = ? WHERE id = ?',
              ('done', output, scan_id))
    conn.commit()
    conn.close()


@app.get('/results/{scan_id}')
async def get_results(scan_id: str):
    if not re.match(r'^[a-f0-9]{8}$', scan_id):
        raise HTTPException(status_code=400, detail='Invalid scan ID')
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT * FROM scans WHERE id = ?', (scan_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return {'id': row[0], 'tool': row[1], 'target': row[2],
                'status': row[3], 'result': row[4]}
    return {'status': 'not_found'}


@app.get('/history')
async def get_history():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT * FROM scans ORDER BY created_at DESC LIMIT 50')
    rows = c.fetchall()
    conn.close()
    return [{'id': r[0], 'tool': r[1], 'target': r[2],
             'status': r[3], 'created_at': r[5]} for r in rows]


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=5002)
