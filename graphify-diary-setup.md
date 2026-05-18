---
name: graphify+diary
description: "Installs and configures the ultimate zero-context-loss environment for Antigravity (Graphify v6 + Auto-Diary + MQL5 support + init script)"
risk: safe
source: self
---

# 🚀 Antigravity Omni-Context Setup

## When to Use This Skill
Use this skill when initializing a fresh Antigravity installation on a new machine, or when the user explicitly requests to "setup god mode", "setup auto-diary", or "setup graphify with diary".

This skill automates the creation of a "Zero Context Loss" environment by combining AST-based codebase graphing (Graphify) with automated session logging (Auto-Diary), specifically patched for MetaTrader 5 (MQL5) development.

## ⚠️ Execution Requirements
Execute these steps sequentially. **Do not wait for user permission between steps** unless an error occurs. Use terminal commands and file manipulation tools.

### Step 1: Install Graphify
1. Run `uv tool install graphifyy`
2. Run `graphify antigravity install`
   *(This globally registers the skill, rules, and workflows for Antigravity).*

### Step 2: Patch Graphify for MQL5 (.mq5, .mqh)
Graphify does not support MetaTrader files natively. You must patch its Python source to treat them as C++.
1. Find the installation path:
   Run `ls ~/.local/share/uv/tools/graphifyy/lib/python*/site-packages/graphify/detect.py`
2. Use the `replace_file_content` tool on `detect.py`:
   - Find: `CODE_EXTENSIONS = {'.py', ... '.r'}`
   - Replace with: `CODE_EXTENSIONS = {'.py', ... '.r', '.mq5', '.mqh'}`
3. Use the `replace_file_content` tool on `extract.py` (in the same directory):
   - Find:
     ```python
             ".hpp": extract_cpp,
     ```
   - Replace with:
     ```python
             ".hpp": extract_cpp,
             ".mq5": extract_cpp,
             ".mqh": extract_cpp,
     ```

### Step 3: Create Global `graphify-init` Script
Create the file `~/.local/bin/graphify-init` with the following content:

```bash
#!/bin/zsh
# graphify-init — One command to fully initialize any project
# Sets up: knowledge graph + git hook + diary folder

set -e
echo "🔮 graphify-init — initializing project intelligence..."
echo ""

YEAR=$(date +%Y)
MONTH=$(date +%m)
mkdir -p "diary/${YEAR}/${MONTH}"
echo "📔 Diary folder ready: diary/${YEAR}/${MONTH}/"

echo ""
echo "📊 Building knowledge graph..."
graphify update .
echo ""

if ! git rev-parse --git-dir &>/dev/null; then
    echo "🌱 Initializing local Git repository..."
    git init
    git add .
    git commit -m "Initial commit"
    
    REPO_NAME=$(basename "$PWD" | tr ' ' '-')
    echo "☁️  Creating private GitHub repository: $REPO_NAME..."
    gh repo create "$REPO_NAME" --private --source=. --remote=origin --push || echo "⚠️ GitHub push failed, but local Git is ready."
    echo ""
fi

echo "🪝 Installing post-commit hook..."
graphify hook install
echo ""

echo "✅ Project fully initialized!"
echo ""
echo "   📊 Graph:  graphify-out/graph.json"
echo "   📝 Report: graphify-out/GRAPH_REPORT.md"
echo "   📔 Diary:  diary/${YEAR}/${MONTH}/"
if git rev-parse --git-dir &>/dev/null; then
echo "   🪝 Hook:   auto-rebuild on every git commit"
fi
echo ""
echo "   AI will auto-log decisions in diary/ at end of each session."
```
After creating, run `chmod +x ~/.local/bin/graphify-init`.

### Step 4: Create Always-On Rules
Write the following content to `~/.gemini/antigravity/.agents/rules/auto-diary.md`:

```markdown
## Auto-Diary — Mandatory Session Logging

### RULE: At the end of EVERY work session, BEFORE ending the conversation:
1. **Auto-generate a session diary entry** in the project's `diary/YYYY/MM/YYYY-MM-DD.md`
2. Contents MUST include:
   - What was changed (files modified, features added)
   - WHY decisions were made (architectural rationale)
   - Bugs found and how they were fixed
   - Constraints discovered
   - Next steps / TODO items
3. **Append** if file already exists (multiple sessions per day)
4. Create `diary/` directory structure automatically if it doesn't exist
5. **Auto-Git-Sync**: If the project is a git repository, automatically run `git add .`, `git commit -m "Auto-commit: <summary>"`, and `git push` without asking for permission.

### RULE: At the START of every session:
1. Check if `diary/` folder exists in the project
2. If YES → read the most recent diary entry to restore context
3. Combined with graphify's GRAPH_REPORT.md, this gives full project understanding without re-reading all code
```

### Step 5: Establish Knowledge Items (Mandatory Enforcement)
Create two KIs in `~/.gemini/antigravity/knowledge/`:

**1. KI for Auto-Diary:**
- Path: `~/.gemini/antigravity/knowledge/auto-diary/metadata.json`
- Content:
```json
{
  "title": "Auto-Diary — Mandatory Session Logging",
  "summary": "ALWAYS ACTIVE: At END of every session, auto-generate diary entry in project's diary/ folder. At START of every session, read most recent diary + GRAPH_REPORT.md for context restore. No exceptions.",
  "created": "2026-05-03T00:00:00Z",
  "lastAccessed": "2026-05-03T00:00:00Z",
  "references": [
    { "type": "rule", "value": "/Users/<USERNAME>/.gemini/antigravity/.agents/rules/auto-diary.md" }
  ]
}
```

**2. KI for Graphify:**
- Path: `~/.gemini/antigravity/knowledge/graphify-mandatory/metadata.json`
- Content:
```json
{
  "title": "Graphify — Mandatory Knowledge Graph",
  "summary": "ALWAYS ACTIVE: Before starting work on ANY project, run /graphify . or graphify update . to build the knowledge graph. Use GRAPH_REPORT.md as primary codebase navigation. Mandatory for every project, every session.",
  "created": "2026-05-03T00:00:00Z",
  "lastAccessed": "2026-05-03T00:00:00Z",
  "references": [
    { "type": "skill", "value": "/Users/<USERNAME>/.gemini/antigravity/skills/graphify/SKILL.md" }
  ]
}
```

### Verification
Inform the user when complete. Remind them that on any new project they just need to run `graphify-init` in the terminal to set everything up.
