# Decision: Neon Jira MCP

Date: 2026-05-17

## Decision

Build the first public connector slice as **Neon Jira MCP**.

The scope is Jira-only: transform NeoQuill meeting actions into reviewable Jira issue fields and optionally create issues through the local `jira` CLI after explicit confirmation.

## Why

- Jira is the highest-value action target for meeting output.
- Atlassian already provides a broad remote MCP, so NeoQuill should not compete as a generic Jira client.
- The product-specific value is converting meeting context into clean execution packets.
- Local CLI auth keeps tokens out of NeoQuill, MCP config, git, and logs.

## Current Scope

- `draft_jira_issue` builds a Jira draft and CLI command.
- `create_jira_issue` executes `jira create` only with `confirmed: true`.
- Package lives in `Tools/NeonJiraMCP`.

## Out Of Scope

- Gmail and Calendar connectors.
- Hosted multi-tenant Jira OAuth service.
- Native Jira REST integration inside NeoQuill.
- Automatic issue creation without a confirmation flag.
