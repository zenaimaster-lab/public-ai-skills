---
name: mt5-session-isolation-fix
description: Resolve MetaTrader 5 (MT5) AutoTrading issues and Market Watch synchronization problems by bypassing Windows Session 0 isolation through an interactive orchestration workflow.
---

# MT5 Session Isolation Fix

## Context & The Problem
When automating MetaTrader 5 (MT5) using the Python `MetaTrader5` package (`mt5.initialize()`), developers often deploy the adapter as a Windows Background Service (using NSSM or similar) for persistence.

This introduces a fatal flaw known as **Session 0 Isolation**:
- Windows Services run in a hidden, non-interactive session (Session 0).
- The user's desktop applications (including the visible MT5 UI) run in Session 1+.
- MT5 uses a strict IPC mechanism bound to the session's active AppData profile.
- When the adapter initializes from Session 0, it fails to connect to the Session 1 terminal. Instead, it spawns a hidden "Ghost" terminal process (`terminal64.exe` with `MainWindowHandle == 0`).
- This Ghost terminal loads a default clean profile:
  - **Market Watch is reset:** Only default symbols (like EURUSD) are available. Custom symbols (e.g., XAUUSD, NAS100) fail to load.
  - **AutoTrading is disabled:** Security policies disable Algo Trading for non-interactive profiles. Attempting to execute an order results in `Error 10027: AutoTrading disabled by client`.

## The Solution: Interactive Orchestration Workflow
To fix this without destroying the user's desktop profile (which happens if you use `portable=True`), the adapter must run interactively in the same session as the desktop (Session 1). 

Instead of a Background Service, implement a 4-step orchestration script:

### Step 1: Kill Ghost Processes
Use PowerShell to safely terminate any hidden MT5 terminals that might block IPC ports, while leaving visible desktop terminals untouched.
```powershell
Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -eq 0 } | ForEach-Object { Stop-Process -Id $_.Id -Force }
```

### Step 2: Fetch Active Client Paths
Retrieve the installation paths of the required MT5 terminals (often stored in a database like Redis, or an `.env` file).

### Step 3: Launch UI Terminals Programmatically
Use Python's `subprocess.Popen([client_path])` to launch the MT5 terminals in the active desktop session. Since they are launched in Session 1, they will load the user's profile, including their custom Market Watch list and their manual "Algo Trading" toggle state.

### Step 4: Attach the Adapter
Wait 5 seconds for the terminals to boot, then execute the Python MT5 adapter script (`subprocess.run(["python", "adapter.py"])`). The `mt5.initialize()` call will now flawlessly attach to the visible terminals.

## When to Use This Skill
Invoke this skill when a user reports:
- Orders failing with `AutoTrading disabled by client (10027)` despite the button being green on the MT5 UI.
- `mt5.initialize()` returning symbols that do not match the visible Market Watch.
- The Python script spawning unseen MT5 processes in the background.
- Requests to migrate an MT5 script from a Windows Service to an interactive process.
