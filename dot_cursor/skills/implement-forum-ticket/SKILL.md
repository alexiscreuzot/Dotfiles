---
name: implement-forum-ticket
description: >
  Implements a Forum-iOS Jira ticket end to end. Use when the user provides a
  ticket key (e.g. ENT-1234), asks to implement a Jira ticket, or invokes the
  implement-forum-ticket command. Fetches the ticket, reads matching docs, plans,
  branches, then implements.
---

# Implement Forum ticket

## Instructions

1. Run `jira get <KEY>` and read summary, description, and acceptance criteria. Credentials live in `~/.secrets` (`JIRA_EMAIL`, `JIRA_TOKEN`, `JIRA_DOMAIN`).
2. In the forum-iOS checkout, read `README.md`, then `docs/architecture.md`, then the topic doc for the affected area (session, networking, ASR, TTS, auth, etc.). Follow `~/.cursor/rules/forum-agents.mdc`.
3. Explore only the files needed to ground the plan.
4. Present an implementation plan: goal, affected files, approach, risks/edge cases. Wait for answers if the ticket is ambiguous or needs a product/architecture decision.
5. Base branch: use `current` if the user said so; else the named branch they gave; else `main`. Unless base is `current`, `git checkout <base> && git pull`. Always create `feature/<KEY>-<kebab-summary>` (lowercase, ~6 words max) and work only on that branch.
6. Implement according to the plan. Prefer existing Session helpers and Forum patterns; do not invent architecture. Do not build or run the app.
7. Report base branch, branch name, and what changed.

## Examples

- User: `ENT-2950` → fetch ticket, plan, branch `feature/ent-2950-…`, implement.
- User: `implement ENT-2917 from develop` → base `develop`, then feature branch.
- User: `ENT-1234 current` → branch from current checkout without switching/pulling the base.
