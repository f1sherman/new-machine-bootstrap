import fs from "node:fs";
const database = "/workspace/.issues/issues.json";
function readIssues() { return JSON.parse(fs.readFileSync(database, "utf8")); }
function result(value) { return { content: [{ type: "text", text: JSON.stringify(value) }], details: value }; }
export default function (pi) {
  pi.registerTool({
    name: "create_issue", label: "Create local project issue",
    description: "Create an issue in this project's local tracker. Include a clear title, reproduction steps, observed behavior, and expected behavior. Returns its ID. No external service is contacted.",
    parameters: { type: "object", properties: { title: { type: "string" }, body: { type: "string" } }, required: ["title", "body"], additionalProperties: false },
    async execute(_id, { title, body }) {
      const issues = readIssues();
      const issue = { id: "issue-" + (issues.length + 1), title, body, status: "open" };
      issues.push(issue);
      fs.writeFileSync(database, JSON.stringify(issues, null, 2) + "\n");
      return result(issue);
    }
  });
  pi.registerTool({
    name: "get_issue", label: "Read local project issue",
    description: "Read a local project issue by its ID, including the full report.",
    parameters: { type: "object", properties: { id: { type: "string" } }, required: ["id"], additionalProperties: false },
    async execute(_id, { id }) {
      const issue = readIssues().find(issue => issue.id === id);
      if (!issue) throw new Error("Issue not found: " + id);
      return result(issue);
    }
  });
}
