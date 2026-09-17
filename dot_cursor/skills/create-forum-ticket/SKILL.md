---
name: create-forum-ticket
description: >
  Creates a Forum-iOS Jira ticket end to end. Use when the user asks to create,
  file, or draft a Jira ticket (story, task, bug), or invokes the
  create-forum-ticket command. Drafts the ticket, confirms fields with
  recommendations, creates it assigned to the user, then saves reusable defaults.
---

# Create Forum ticket

## Instructions

1. Read `~/.cursor/forum/ticket-preferences.json` for saved defaults (summary prefix, components, team, priority, per-type Category of Work). Jira credentials live in `~/.secrets` (`JIRA_EMAIL`, `JIRA_TOKEN`, `JIRA_DOMAIN`).
2. Draft from the user's input: summary (apply the saved prefix, e.g. `iOS: ...`), description (context + what/why), and Acceptance Criteria (Story) or Steps to Reproduce (Bug). Explore the codebase to ground the ticket if useful; never implement.
3. Ask (recommendation pre-selected) for anything not clearly determined: issue type; Story Points for Stories (1/2/3/5/8, recommend from scope); Category of Work (saved per-type default; if KTLO, optionally ask which child — Emergency Work, High Risk Remediation, Reliability and Resilience, Operational Run the Business, Tech Debt Reduction / Lifecycle Management, Governance and Control Execution, Knowledge Management); priority (saved default, High for urgent bugs); components/team/labels (saved defaults). Parent epic only if the user explicitly names one.
4. Show the full payload and wait for confirmation.
5. Run `jira create` with the applicable env vars: `JIRA_ISSUE_TYPE`, `JIRA_SUMMARY`, `JIRA_DESCRIPTION`, `JIRA_AC` (Story), `JIRA_STEPS` (Bug), `JIRA_POINTS` (Story), `JIRA_CATEGORY` (+ optional `JIRA_CATEGORY_CHILD`), `JIRA_COMPONENTS`, `JIRA_TEAM_ID`, `JIRA_PRIORITY`, `JIRA_LABELS`, `JIRA_PARENT`. Assignee, reporter and developer default to the user. Sprint defaults to the active sprint of the Forum Sprint Board (`JIRA_SPRINT=none` skips, or pass a sprint id to pin).
6. Report the created key + URL, then update `~/.cursor/forum/ticket-preferences.json` with confirmed reusable choices (never one-off values like epic keys, labels, or points). Re-add it with `chezmoi add ~/.cursor/forum/ticket-preferences.json` if the defaults should survive the next machine.

## Examples

- User: `create a bug for session translation stopping after backgrounding` → draft Bug with steps, recommend KTLO + Medium, confirm, create.
- User: `file a story to add the updated UK terms of use, probably 2 points` → draft Story + AC, recommend Product Enhancement, confirm, create.
- User: `create a task to bump dependency versions` → draft Task, recommend Technical Improvement, confirm, create.
