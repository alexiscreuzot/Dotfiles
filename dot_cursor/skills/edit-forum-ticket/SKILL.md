---
name: edit-forum-ticket
description: >
  Edits a Forum-iOS Jira ticket. Use when the user asks to update, comment on,
  transition, reassign, estimate, or otherwise change an existing ticket
  (e.g. "move ENT-1234 to In Progress", "comment on ENT-1234", "set points").
---

# Edit Forum ticket

## Instructions

1. Fetch current state first with `jira get <KEY>` when the edit depends on existing values (labels and components are replaced, not merged).
2. Run `jira edit <KEY>` with the applicable flags:
   - Fields: `--summary`, `--description`, `--ac`, `--steps`, `--points`, `--priority`, `--assignee me|<accountId>`, `--developer me|<accountId>`, `--team <uuid>`, `--category "Parent"` or `"Parent/Child"`, `--components "Forum Client"`, `--labels "a,b"`, `--parent <EPIC-KEY>`, `--sprint active|<id>|none`
   - `--comment "..."` adds a comment; `--transition "In Progress"` moves status (names are matched case-insensitively against the transitions available to that ticket).
   - Text fields accept `- ` bullets and `## ` / `### ` headings.
3. Confirm with the user before transitions that close or reopen a ticket, and before reassigning away from them.
4. Report the ticket URL and what changed.

## Examples

- User: `move ENT-3241 to In Progress` → `jira edit ENT-3241 --transition "In Progress"`.
- User: `comment on ENT-3241 that the fix is on main` → `--comment "Fixed on main."`.
- User: `estimate ENT-3241 at 3 points and assign me` → `--points 3 --assignee me`.
