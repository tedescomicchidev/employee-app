# agents/toolboxes
Toolbox and connection definitions, referenced from `azure.yaml` with `$ref`.

- `tools-conn.yaml`: Foundry project connection to `api/` `/mcp` (`UserEntraToken`, audience `api://employee-tools`).
- `core-tools.yaml`: the shared `core-tools` toolbox (all MCP tools of `api/`).

Creating connections and toolboxes is human-only (`azd provision`, or `azd ai connection` /
`azd ai toolbox`). Tool names and arguments are defined in `api/app/mcp/server.py`.
