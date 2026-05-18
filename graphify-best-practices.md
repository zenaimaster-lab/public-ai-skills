---
name: graphify-best-practices
description: Best practices, workflow rules, and guidelines for using the Graphify tool optimally to save tokens and time.
---

# Graphify Workflow Best Practices & Rules

Graphify is a powerful tool to generate a knowledge graph (AST & Semantic) of a codebase. However, running it improperly can waste massive amounts of LLM tokens and time.

These rules must be followed by any AI agent, IDE, or platform using Graphify:

## 1. When to Run Graphify (Trigger Frequency)
- **DO NOT** run `graphify update .` after every minor code change (e.g., bug fixes, UI tweaks, variable renames).
- **DO** run Graphify at the **END of a working session** or after a **significant milestone/feature completion**.
- Think of Graphify as a "full X-ray" of the system. You don't take an X-ray for a scratch; you take it after major surgery or for a periodic checkup.

## 2. Semantic vs. Structural (AST) Extraction
Graphify has two core mechanisms:
1. **Structural (AST) Extraction:** Reads code structure (classes, functions, variables) locally. This is very fast and **costs ZERO tokens**.
2. **Semantic Extraction:** Uses an LLM to read and summarize what the code actually does. This is slow and **consumes API tokens**.
   - If you only need to update the folder structure or check basic dependencies, run AST only or bypass the semantic step.
   - If an API key is NOT provided, semantic extraction will fail or fall back to the AI agent's own context window (via subagents), which burns the current session's token budget.

## 3. Why Reinstallation Occurs
- AI execution environments (like PowerShell on Windows via an agent) often run in isolated or reset sessions. 
- If the AI runs `import graphify` and fails, it is programmed defensively to run `pip install graphifyy` to ensure the tool is available.
- **This does NOT reset the graph data.** The actual knowledge graph is stored persistently in the `.graphify-out` or similar local project directory. Reinstalling the Python package only restores the tool itself, not the data it processes.

## 4. Why Use a Script File (`.py`) Instead of CLI
- Agents often write a `.py` script (e.g., `graphify_run.py`) and execute it rather than running complex inline `python -c "..."` commands.
- This avoids escaping issues (quotes) in PowerShell and allows the agent to precisely control the Graphify pipeline (e.g., skipping semantic extraction to save time).

## 5. Ignore Lists (`.gitignore`)
- Always ensure the project has a `.gitignore` that excludes folders like `venv`, `node_modules`, `__pycache__`, `logs/`, and `.git`.
- Graphify will respect these ignore rules, preventing it from wasting time and tokens scanning irrelevant cache or dependency files.

## Summary of the Ideal Graphify Workflow
1. **Develop/Code:** Work normally, modify files, run tests.
2. **Commit:** Push minor changes without updating Graphify.
3. **End of Session / Milestone:** Run `graphify update .` to update both AST and Semantic extraction.
4. **Review:** Check the `GRAPH_REPORT.md` to restore context for the next session.
