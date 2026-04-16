#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFileSync } from "child_process";

const server = new McpServer({
  name: "nvim-claude",
  version: "0.3.0",
});

server.tool(
  "open_in_nvim",
  "Open a file in the user's connected Neovim editor, optionally jumping to a specific line",
  {
    file: z.string().describe("Path to the file to open (relative to cwd or absolute)"),
    line: z.number().optional().describe("Line number to jump to"),
  },
  async ({ file, line }) => {
    const nvimServer = process.env.NVIM_CLAUDE_SERVER;
    if (!nvimServer) {
      return {
        content: [{ type: "text", text: "Not connected to a Neovim session (NVIM_CLAUDE_SERVER not set)" }],
        isError: true,
      };
    }

    try {
      const keys = line
        ? `:e ${file}\n:${line}\n`
        : `:e ${file}\n`;

      execFileSync("nvim", ["--server", nvimServer, "--remote-send", keys], {
        timeout: 5000,
      });

      const location = line ? `${file}:${line}` : file;
      return {
        content: [{ type: "text", text: `Opened ${location} in Neovim` }],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Failed to open file in Neovim: ${err.message}` }],
        isError: true,
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
