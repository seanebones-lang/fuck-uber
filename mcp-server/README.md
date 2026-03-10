# cto-eleven MCP bridge

MCP server that connects Cursor (stdio) to your deployed cto-eleven API.

## Setup

```bash
npm install
```

## Cursor configuration

Edit `.cursor/mcp.json` at the project root and set:

- **BASE_URL** – Your deployed API (e.g. Vercel or Railway URL).
- **GITHUB_TOKEN** – GitHub token for repo/PR tools (optional).

Then in Cursor: **Settings → Tools & MCP**. The `cto-eleven` server should appear; if it shows disconnected, use the refresh/reconnect control.

## Tools

- **health_check** – Local; always works. With a valid BASE_URL, also checks API health.
- **proxy_tool** – Forwards a single tool call to the API (`/api/tools/call`). Your API can expose more tools by implementing that endpoint and optionally listing them via MCP.
