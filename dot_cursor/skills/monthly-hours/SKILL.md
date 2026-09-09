---
name: monthly-hours
description: >
  Builds Alexis's monthly Forum timesheet (CapEx UK Forum, Scrum meetings,
  IriusRisk, KTLO) from git, Jira, and the Outlook calendar via Microsoft Graph.
  Use when he asks for monthly hours, timesheet hours, August/September hours,
  or invokes the monthly-hours command.
---

# Monthly hours

Scripts live under `~/.cursor/monthly-hours/` (managed by chezmoi). `config.json` is age-encrypted. Do not commit generated reports, Graph tokens, `.ics` files, or `.venv`.

## Budget and buckets

- Budget = weekdays in the month × 8 (from `config.json` `hourPerWeekday`).
- **Scrum meetings** = exact durations of Outlook events whose title matches `config.json` `scrumTitleRegex`.
- **IriusRisk** = assessment tickets (`Forum Mobile (Apple iOS)`, key range ENT-3154–3171). Hours: implemented 8, in progress 4, comment-only 0.5. Older IriusRisk close-outs without commits this month (e.g. ENT-2801) do not count.
- **CapEx UK Forum** = remaining Forum product / feature work (stories, technical improvements).
- **KTLO** = bugs, ops, version bumps, internal tooling.
- After Scrum + IriusRisk, leftover budget is split CapEx vs KTLO by relative effort (story points, else 2 for a bug / 3 for a story, +0.5 per extra commit).

## Steps

1. Resolve the month to `YYYY-MM`. Default: previous calendar month.
2. Check Graph login:

   ```bash
   python3 ~/.cursor/monthly-hours/graph_auth.py status
   ```

   If that fails, run `python3 ~/.cursor/monthly-hours/graph_auth.py login` (device flow). Sorenson requires **admin consent** for Microsoft Graph Command Line Tools — if the page says the admin was notified, stop. Do **not** publish a calendar (that ICS URL is public). Ask for a **local** `.ics`: in Outlook Calendar, select the Scrum meetings and drag them to the Desktop, then `python3 ~/.cursor/monthly-hours/report.py YYYY-MM --ics ~/Desktop/that-file.ics`. See `~/.cursor/monthly-hours/ICS.md`.
3. Run the report (do not run `xcodebuild` or tests):

   ```bash
   python3 ~/.cursor/monthly-hours/report.py YYYY-MM
   ```

4. The script writes `~/.cursor/monthly-hours/YYYY-MM-hours.html` (and `.csv`) and opens the HTML. That table is **numbers only**: rows CapEx / Scrum / IriusRisk / KTLO, columns = working weeks (skip a leading 0-day week). Tell him to select the table, copy, click the first Excel cell, paste. Do **not** put the grid in a chat code block — Excel Online will not paste that as cells.
5. Also show the four monthly totals and the “what was done” list. Mention the Scrum source (`graph`, `ics`, `ics-url`, or `placeholder`).
6. Do not commit, push, or write these files into `forum-iOS` or any other repo.

## Scripts

| Script | Role |
|--------|------|
| `graph_auth.py login\|status\|token` | Device-code OAuth; tokens in `graph-token.json` (blocked at Sorenson until IT consents) |
| `scrum_hours.py YYYY-MM [--ics FILE]` | Calendar events + hours |
| `month_work.py YYYY-MM` | Git commits + Jira tickets |
| `report.py YYYY-MM [--ics FILE]` | Classification + timesheet lines |

Jira credentials come from `forum-iOS/.env` (`jiraEnvPath` in config).
