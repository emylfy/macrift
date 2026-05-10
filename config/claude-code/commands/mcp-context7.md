---
description: Create .mcp.json in cwd with context7 MCP server config
---

Create `.mcp.json` in the current working directory with context7 MCP config so Claude Code activates context7 for this project.

Steps:

1. Check if `.mcp.json` already exists in `$PWD`. If yes — refuse, tell user to merge manually.
2. Otherwise, write `.mcp.json` with this content:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

3. After writing, tell the user:
   - Restart Claude Code in this directory (or quit and reopen)
   - Approve the context7 MCP server when prompted on first use
   - It will auto-pull library docs (e.g. for `react`, `next`, `python` packages) when generating code
