# agents/toolboxes
The `core-tools` toolbox and the `tools-conn` connection to `api/` `/mcp` are declared inline in
`azure.yaml` (`azure.ai.toolbox` and `azure.ai.connection` services), per the Learn
"Author azure.yaml for hosted agents" page. A `$ref` include was tried first and azd saw an empty toolbox.

- `tools-conn`: `UserEntraToken`, audience `api://<employee-tools client id>` (`TOOLS_CLIENT_ID`).
- `core-tools`: one MCP tool (`employee-api`) exposing every tool of `api/app/mcp/server.py`.

Creating connections and toolboxes is human-only (`azd deploy tools-conn`, `azd deploy core-tools`).
