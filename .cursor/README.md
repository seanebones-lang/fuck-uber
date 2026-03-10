# Cursor MCP (cto-eleven)

The **cto-eleven** server is configured in `mcp.json`. It runs `mcp-server/server.mjs` and talks to your deployed API.

**To use the full API:** set these in your environment (e.g. in your shell profile or Cursor’s env) so the MCP server can see them:

- `BASE_URL` – your deployed API URL (e.g. Vercel or Railway)
- `GITHUB_TOKEN` – optional; for GitHub/repo tools

Then in Cursor: **Settings → Tools & MCP** and refresh/reconnect the cto-eleven server.

**Swarm tip:** If `run_orchestrate` returns 500, use `run_swarm` with `agents: ["orchestrator"]` and put your task in `code` for the same kind of coordination.
