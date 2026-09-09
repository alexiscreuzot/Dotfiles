Report monthly Forum timesheet hours for the month I name (e.g. August, 2026-08). Default to the previous calendar month if I do not specify one.

This is local-only. Read and run files under `~/.cursor/monthly-hours/` and follow `~/.cursor/skills/monthly-hours/SKILL.md`. Do not write anything into a git repo.

1. If Graph is not logged in, try `python3 ~/.cursor/monthly-hours/graph-auth.py login`. If the tenant requires admin consent, do not publish a calendar URL. Ask me for a **local** `.ics` (Outlook Calendar → select Scrum meetings → drag to Desktop) and run `python3 ~/.cursor/monthly-hours/report.py YYYY-MM --ics PATH`.
2. Run: `python3 ~/.cursor/monthly-hours/report.py YYYY-MM`
3. `report.py` opens an HTML table of numbers only (CapEx / Scrum / IriusRisk / KTLO × working weeks, no leading 0-day week). Tell me to copy that table into the online Excel doc. Do not paste the grid as a chat code block — it does not land in cells.
4. Also print the four monthly totals and the work summary. Do not invent hours — use the script output.
