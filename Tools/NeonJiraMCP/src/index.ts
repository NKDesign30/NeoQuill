#!/usr/bin/env node
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);
const version = "0.1.0";

const jiraIssueShape = {
  projectKey: z.string().trim().min(1).describe("Jira project key, for example NEO."),
  issueType: z.string().trim().min(1).default("Task").describe("Jira issue type, for example Task or Bug."),
  summary: z.string().trim().min(1).max(255).describe("Short Jira issue summary."),
  description: z.string().trim().min(1).describe("Issue body. Include acceptance criteria if available."),
  labels: z.array(z.string().trim().min(1)).default([]).describe("Additional Jira labels."),
  priority: z.string().trim().optional().describe("Optional Jira priority name."),
  assignee: z.string().trim().optional().describe("Optional Jira assignee account/name accepted by the local CLI."),
  meetingTitle: z.string().trim().optional().describe("Optional source meeting title."),
  source: z.string().trim().optional().describe("Optional source URL, file path, or NeoQuill meeting id."),
};

const createJiraIssueShape = {
  ...jiraIssueShape,
  confirmed: z.boolean().default(false).describe("Must be true after reviewing the generated Jira fields."),
};

const jiraIssueSchema = z.object(jiraIssueShape);
const createJiraIssueSchema = z.object(createJiraIssueShape);

interface IJiraIssueFields {
  projectKey: string;
  issueType: string;
  summary: string;
  description: string;
  labels: string[];
  priority?: string;
  assignee?: string;
  meetingTitle?: string;
  source?: string;
}

interface IJiraDraft {
  fields: IJiraIssueFields;
  args: string[];
  command: string;
  description: string;
}

interface IExecError extends Error {
  stdout?: string;
  stderr?: string;
  code?: string | number;
}

const server = new McpServer({
  name: "neon-jira-mcp",
  version,
});

server.registerTool(
  "draft_jira_issue",
  {
    title: "Draft Jira Issue",
    description: "Build a reviewable Jira issue draft and local jira CLI command from a meeting action.",
    inputSchema: jiraIssueShape,
  },
  async (input) => {
    const draft = buildJiraDraft(jiraIssueSchema.parse(input));
    return {
      content: [
        {
          type: "text",
          text: formatDraft(draft),
        },
      ],
    };
  }
);

server.registerTool(
  "create_jira_issue",
  {
    title: "Create Jira Issue",
    description: "Create a Jira issue through the local jira CLI. Requires confirmed=true after field review.",
    inputSchema: createJiraIssueShape,
  },
  async (input) => {
    const parsed = createJiraIssueSchema.parse(input);
    const draft = buildJiraDraft(parsed);

    if (!parsed.confirmed) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: [
              "Nicht erstellt: `confirmed` muss nach Review auf `true` gesetzt werden.",
              "",
              formatDraft(draft),
            ].join("\n"),
          },
        ],
      };
    }

    try {
      const result = await execFileAsync("jira", draft.args, {
        timeout: 30_000,
        maxBuffer: 1024 * 1024,
      });
      return {
        content: [
          {
            type: "text",
            text: ["Jira Issue erstellt.", "", result.stdout.trim(), result.stderr.trim()]
              .filter((line) => line.length > 0)
              .join("\n"),
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: [
              "Jira CLI konnte das Issue nicht erstellen.",
              "",
              formatExecError(error),
              "",
              "Draft bleibt ausführbar:",
              draft.command,
            ].join("\n"),
          },
        ],
      };
    }
  }
);

function buildJiraDraft(input: z.infer<typeof jiraIssueSchema>): IJiraDraft {
  const fields = normalizeIssue(input);
  const description = buildDescription(fields);
  const args = buildCreateArgs(fields, description);

  return {
    fields,
    args,
    command: ["jira", ...args].map(shellQuote).join(" "),
    description,
  };
}

function normalizeIssue(input: z.infer<typeof jiraIssueSchema>): IJiraIssueFields {
  return {
    projectKey: input.projectKey.trim(),
    issueType: input.issueType.trim(),
    summary: input.summary.trim(),
    description: input.description.trim(),
    labels: uniqueLabels(["neoquill", "meeting-action", ...input.labels]),
    priority: cleanOptional(input.priority),
    assignee: cleanOptional(input.assignee),
    meetingTitle: cleanOptional(input.meetingTitle),
    source: cleanOptional(input.source),
  };
}

function buildDescription(fields: IJiraIssueFields): string {
  return [
    fields.description,
    "",
    fields.meetingTitle ? `Meeting: ${fields.meetingTitle}` : undefined,
    fields.source ? `Quelle: ${fields.source}` : undefined,
    "",
    "Erstellt via Neon Jira MCP.",
  ]
    .filter(isNonEmptyString)
    .join("\n");
}

function buildCreateArgs(fields: IJiraIssueFields, description: string): string[] {
  const overrides = [
    ["summary", fields.summary],
    ["description", description],
    ["labels", fields.labels.join(",")],
    fields.priority ? ["priority", fields.priority] : undefined,
    fields.assignee ? ["assignee", fields.assignee] : undefined,
  ].filter(isStringPair);

  return [
    "create",
    "--noedit",
    "--project",
    fields.projectKey,
    "--issuetype",
    fields.issueType,
    ...overrides.flatMap(([key, value]) => ["--override", `${key}=${value}`]),
  ];
}

function formatDraft(draft: IJiraDraft): string {
  return [
    "# Jira Draft",
    "",
    `Projekt: ${draft.fields.projectKey}`,
    `Typ: ${draft.fields.issueType}`,
    `Summary: ${draft.fields.summary}`,
    `Labels: ${draft.fields.labels.join(", ")}`,
    draft.fields.priority ? `Priority: ${draft.fields.priority}` : undefined,
    draft.fields.assignee ? `Assignee: ${draft.fields.assignee}` : undefined,
    "",
    "## Description",
    "",
    draft.description,
    "",
    "## CLI",
    "",
    "```sh",
    draft.command,
    "```",
  ]
    .filter(isNonEmptyString)
    .join("\n");
}

function formatExecError(error: unknown): string {
  if (!(error instanceof Error)) {
    return String(error);
  }

  const execError = error as IExecError;
  return [
    execError.message,
    execError.code !== undefined ? `Code: ${execError.code}` : undefined,
    execError.stdout ? `stdout:\n${execError.stdout.trim()}` : undefined,
    execError.stderr ? `stderr:\n${execError.stderr.trim()}` : undefined,
  ]
    .filter(isNonEmptyString)
    .join("\n");
}

function uniqueLabels(labels: string[]): string[] {
  return Array.from(
    new Set(labels.map((label) => label.trim()).filter((label) => label.length > 0))
  );
}

function cleanOptional(value: string | undefined): string | undefined {
  const cleaned = value?.trim();
  return cleaned && cleaned.length > 0 ? cleaned : undefined;
}

function isNonEmptyString(value: string | undefined): value is string {
  return typeof value === "string" && value.length > 0;
}

function isStringPair(value: string[] | undefined): value is [string, string] {
  return Array.isArray(value) && value.length === 2;
}

function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_/:=.,@+-]+$/.test(value)) {
    return value;
  }

  return `'${value.replaceAll("'", "'\"'\"'")}'`;
}

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error: unknown) => {
  console.error(formatExecError(error));
  process.exit(1);
});
