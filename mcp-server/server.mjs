#!/usr/bin/env node
/**
 * cto-eleven MCP bridge: Cursor (stdio) <-> deployed API (BASE_URL).
 * Exposes tools by forwarding to the API; health_check is local so the server always starts.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const BASE_URL = process.env.BASE_URL || "";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || "";

const mcpServer = new McpServer({
  name: "cto-eleven",
  version: "1.0.0",
});

// Local health check so Cursor can connect even when BASE_URL is not set
mcpServer.registerTool(
  "health_check",
  {
    description: "Check MCP bridge and optional API health",
    inputSchema: {},
  },
  async () => {
    if (!BASE_URL || BASE_URL.includes("your-actual")) {
      return {
        content: [
          {
            type: "text",
            text: "cto-eleven MCP bridge is running. Set BASE_URL and GITHUB_TOKEN in .cursor/mcp.json to use the full API.",
          },
        ],
      };
    }
    try {
      const res = await fetch(`${BASE_URL.replace(/\/$/, "")}/health`, {
        headers: GITHUB_TOKEN ? { Authorization: `Bearer ${GITHUB_TOKEN}` } : {},
      });
      const text = await res.text();
      return {
        content: [
          {
            type: "text",
            text: res.ok ? `API health: ${text}` : `API health check failed: ${res.status} ${text}`,
          },
        ],
      };
    } catch (e) {
      return {
        content: [{ type: "text", text: `Bridge OK; API unreachable: ${e.message}` }],
      };
    }
  }
);

// Generic proxy tool: forwards any tool call to the deployed API
mcpServer.registerTool(
  "proxy_tool",
  {
    description: "Internal: forwards a single tool call to the cto-eleven API",
    inputSchema: {
      name: z.string().describe("Tool name"),
      arguments: z.record(z.unknown()).optional().describe("Tool arguments"),
    },
  },
  async ({ name, arguments: args }) => {
    if (!BASE_URL || BASE_URL.includes("your-actual")) {
      return {
        content: [{ type: "text", text: "Set BASE_URL in .cursor/mcp.json to use API tools." }],
        isError: true,
      };
    }
    const url = `${BASE_URL.replace(/\/$/, "")}/api/tools/call`;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(GITHUB_TOKEN ? { Authorization: `Bearer ${GITHUB_TOKEN}` } : {}),
        },
        body: JSON.stringify({ name, arguments: args || {} }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        return {
          content: [{ type: "text", text: `API error ${res.status}: ${JSON.stringify(data)}` }],
          isError: true,
        };
      }
      if (data.content) return { content: data.content };
      return {
        content: [{ type: "text", text: typeof data === "string" ? data : JSON.stringify(data) }],
      };
    } catch (e) {
      return {
        content: [{ type: "text", text: `Request failed: ${e.message}` }],
        isError: true,
      };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await mcpServer.connect(transport);
}

main().catch((err) => {
  console.error("MCP server error:", err);
  process.exit(1);
});
