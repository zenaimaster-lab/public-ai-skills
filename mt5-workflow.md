---
name: mt5-workflow
description: "ALWAYS ACTIVE for any MT5/MQL5 project. Enforces the complete post-change workflow: version bump → deploy to MetaTrader → compile → graphify update → diary write → git push."
trigger: auto
---

# MT5 Post-Change Workflow

**This skill is ALWAYS ACTIVE for any project containing `.mq5` or `.mqh` files.** It defines the mandatory end-of-task workflow that must execute after every code modification.

## When to Trigger

Execute this workflow after **every** code change in an MT5/MQL5 project:
- Bug fixes
- Feature additions
- Refactoring
- UI layout changes
- Any modification to `.mq5` or `.mqh` files

## The 5-Step Workflow

After completing code changes, execute ALL steps in this exact order. **Never skip a step.**

---

### Step 1 — Version Bump

Increment the EA version and update the build date in `Defines.mqh`:

```cpp
#define EA_VERSION        "X.XX"        // +0.01 per session (not per-file)
#define EA_BUILD_DATE     "DD Mon YYYY" // today's date
```

**Rules:**
- Increment `EA_VERSION` by `+0.01` (e.g., `0.81` → `0.82`)
- Update `EA_BUILD_DATE` to today in format `DD Mon YYYY` (e.g., `06 May 2026`)
- Multiple changes in one session = ONE version bump
- Do this FIRST, before deploy

---

### Step 2 — Deploy to MetaTrader

Copy all source files from the project workspace to the MetaTrader data directory.

#### Auto-detect paths

The skill needs 3 paths. Detect them as follows:

**Source path:** The project workspace root (contains `.mq5` and `.mqh` files).

**Target path:** The MetaTrader Experts subfolder. Structure:
```
C:\Users\<USER>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Experts\<EA_FOLDER>
```

To find the terminal ID and EA folder:
```powershell
# List all terminals
Get-ChildItem "C:\Users\$env:USERNAME\AppData\Roaming\MetaQuotes\Terminal" -Directory |
  ForEach-Object {
    $origin = Get-Content "$($_.FullName)\origin.txt" -ErrorAction SilentlyContinue
    Write-Host "$($_.Name) -> $origin"
  }
```

Then locate the EA folder:
```powershell
# Find EA folder within a terminal
Get-ChildItem "<TERMINAL_PATH>\MQL5\Experts" -Directory
```

**MQL5 Root:** The `MQL5` folder inside the terminal directory (needed for compiler include path).

#### Copy commands

```powershell
$src = "<PROJECT_PATH>"
$dst = "<TARGET_PATH>"
Copy-Item "$src\*.mq5" "$dst\" -Force
Copy-Item "$src\*.mqh" "$dst\" -Force
Write-Host "[DEPLOY] Files copied to MetaTrader" -ForegroundColor Green
```

---

### Step 3 — Compile

Compile the EA using MetaEditor64's command-line interface.

#### Find MetaEditor

```powershell
Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "metaeditor64.exe" -ErrorAction SilentlyContinue |
  Select-Object -First 5 FullName
```

#### Compile command

```powershell
$compiler = "<METAEDITOR_PATH>\MetaEditor64.exe"
$mq5File = "<TARGET_PATH>\<EA_NAME>.mq5"
$logFile = "<TARGET_PATH>\compile_log.txt"
$mql5Root = "<MQL5_ROOT>"

Start-Process -FilePath $compiler `
  -ArgumentList "/compile:`"$mq5File`" /log:`"$logFile`" /include:`"$mql5Root`"" `
  -Wait -NoNewWindow
Start-Sleep -Seconds 2
```

#### Verify result

```powershell
$content = Get-Content $logFile -Encoding Unicode
$result = $content | Where-Object { $_ -match "^Result:" } | Select-Object -Last 1
if ($result -match "0 errors") {
    Write-Host "[COMPILE] SUCCESS: $result" -ForegroundColor Green
} else {
    Write-Host "[COMPILE] FAILED: $result" -ForegroundColor Red
    $content | Where-Object { $_ -match "error" } | Select-Object -Last 15
}
```

**CRITICAL:**
- The `/include:` flag MUST point to the `MQL5` root directory (not the EA folder), so standard library includes like `<Controls/Dialog.mqh>` resolve correctly.
- If compilation fails, **STOP** and fix the errors before proceeding to Step 4.

---

### Step 4 — Graphify Update

Update the project knowledge graph:

```
/graphify . --update
```

Or run the incremental update pipeline manually following the graphify skill instructions. This keeps the knowledge graph in sync with code changes for context restoration in future sessions.

---

### Step 5 — Diary Write

Create or append to the session diary at `diary/YYYY/MM/YYYY-MM-DD-<topic>.md`:

```markdown
# Session: YYYY-MM-DD — <Topic>

## Objective
<What was the goal>

## Changes
- <List of changes made>
- Version bumped: X.XX → X.XX

## Files Modified
- <file1>
- <file2>

## Compile Result
0 errors, 0 warnings
```

---

## Known MT5 Project: KAT Strike

For the `mt5-kat-Strike` project, all paths are pre-configured:

| What | Path |
|------|------|
| **Source** | `c:\Users\<USERNAME>\Documents\all. Coding\mt5-kat-Strike` |
| **Target** | `C:\Users\<USERNAME>\AppData\Roaming\MetaQuotes\Terminal\<MT5_TERMINAL_ID>\MQL5\Experts\KAT Strike` |
| **MQL5 Root** | `C:\Users\<USERNAME>\AppData\Roaming\MetaQuotes\Terminal\<MT5_TERMINAL_ID>\MQL5` |
| **Compiler** | `C:\Program Files\MetaTrader 5\MetaEditor64.exe` |
| **Main file** | `kat-Strike.mq5` |
| **Version defines** | `Defines.mqh` lines 10-11 |

### KAT Strike one-liner deploy

```powershell
& "c:\Users\<USERNAME>\Documents\all. Coding\mt5-kat-Strike\deploy.ps1"
```

---

## Quick Reference

```
┌─────────────────────────────────────────────┐
│         MT5 POST-CHANGE WORKFLOW            │
├─────────────────────────────────────────────┤
│  1. VERSION BUMP    Defines.mqh +0.01       │
│  2. DEPLOY          Copy .mq5/.mqh → MT5    │
│  3. COMPILE         MetaEditor64 /compile   │
│  4. GRAPHIFY        /graphify . --update    │
│  5. DIARY           diary/YYYY/MM/...md     │
└─────────────────────────────────────────────┘
```

## Adding a New MT5 Project

When working on a new MT5 project for the first time:

1. **Identify the terminal** — run the terminal discovery command above
2. **Locate or create the EA folder** under `MQL5\Experts\`
3. **Create `deploy.ps1`** in the project root with the correct paths
4. **Create `Defines.mqh`** with `EA_VERSION` and `EA_BUILD_DATE` if not present
5. **Create `diary/` folder** for session logs
6. **Run `/graphify .`** for initial knowledge graph

Then the 5-step workflow applies identically.
