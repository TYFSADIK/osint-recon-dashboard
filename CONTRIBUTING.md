# Contributing

## Adding a New Tool

Adding a tool takes four steps. The example below adds `wapiti`, a web application vulnerability scanner.

---

### Step 1 — Install the tool

```bash
pip install wapiti3
```

Verify it works:

```bash
wapiti -u http://example.com --scope page -f txt -o /tmp/test
```

---

### Step 2 — Add an entry to `TOOL_DEFS` in `main.py`

Open `main.py` and find the `TOOL_DEFS` dictionary. Add your tool as a list (never a shell string):

```python
TOOL_DEFS = {
    # ... existing tools ...

    # Web exploitation
    'sqlmap':  ['sqlmap', '-u', 'http://{target}', '--batch', '--level=2', '--risk=1'],
    'whatweb': ['whatweb', '{target}'],
+   'wapiti':  ['wapiti', '-u', 'http://{target}', '--scope', 'page', '-f', 'txt'],
```

Rules:
- Always use a **list**, not a string. The backend calls `subprocess.run(cmd, ...)` with `shell=False`.
- Use `{target}` as the placeholder. It is substituted after input validation.
- Never pass shell metacharacters or pipeline characters. Each list element is one argument.
- Pick a key that is lowercase, alphanumeric, and uses hyphens for separators (e.g. `gobuster-dir`, not `GobusterDir`).

---

### Step 3 — Add a card to `static/index.html`

Find the section that fits your tool (OSINT, Active Recon, Web Exploitation, Network/Windows, Password Cracking) and add a card inside the `.tool-grid` div:

```html
        <!-- Web Exploitation section -->
        <div class="tool-grid">
            <!-- ... existing cards ... -->

+           <div class="tool-card">
+               <h3>Wapiti</h3>
+               <p>Web application vulnerability scanner</p>
+               <input type="text" id="t-wapiti" placeholder="example.com">
+               <button class="run-btn" onclick="runTool('wapiti','t-wapiti')">Run</button>
+           </div>
        </div>
```

The `id` on the input must be `t-` followed by the exact key you used in `TOOL_DEFS`.

---

### Step 4 — Update the tool table in `README.md`

Add a row to the tool table under the correct category:

```markdown
| wapiti | Web | Web application vulnerability scanner |
```

---

## Code Style

**Python (`main.py`)**
- PEP 8, 4-space indent
- All subprocess calls use lists, never strings with `shell=True`
- New tools go in the `TOOL_DEFS` dict only — no logic elsewhere

**HTML/JS (`static/index.html`)**
- 4-space indent
- All user-supplied strings rendered via `escapeHtml()` before being inserted into the DOM
- No external CDN dependencies — the file must work offline

---

## Testing Locally

```bash
python -m venv .venv
source .venv/bin/activate    # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

Open `http://localhost:5002`. Run a scan and confirm:
1. The tool executes (check terminal output from uvicorn)
2. Results appear in the output panel
3. The scan appears in Scan History

---

## Opening a Pull Request

1. Fork the repository
2. Create a branch: `git checkout -b add-wapiti`
3. Make your changes (steps 1–4 above)
4. Commit: `git commit -m "add wapiti web scanner"`
5. Push and open a PR against `main`

PR description should include:
- What the tool does
- Install command
- A short example of output
