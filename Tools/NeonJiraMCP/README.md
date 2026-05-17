# Neon Jira MCP

Local stdio MCP for turning NeoQuill meeting actions into Jira issues.

This is not a generic Jira replacement. Atlassian already has a remote MCP. Neon Jira MCP is the narrow bridge from meeting output to reviewable Jira work items, using the local `jira` CLI and the user's existing Jira auth.

## Tools

- `draft_jira_issue`: returns normalized Jira fields plus a runnable `jira create` command.
- `create_jira_issue`: creates the issue through the local `jira` CLI only when `confirmed: true`.

Default labels: `neoquill`, `meeting-action`.

## Install

```sh
cd Tools/NeonJiraMCP
npm install
npm run build
```

## MCP config

```json
{
  "mcpServers": {
    "neon-jira": {
      "command": "node",
      "args": ["/absolute/path/to/NeoQuill/Tools/NeonJiraMCP/dist/index.js"]
    }
  }
}
```

## Auth

Neon Jira MCP does not store Jira credentials. It shells out to the configured local `jira` CLI. Run `jira login` outside the MCP if Jira auth is missing.

## Safety

The draft tool never writes to Jira. The create tool requires `confirmed: true` and uses `execFile`, not shell execution, for the real create call.
