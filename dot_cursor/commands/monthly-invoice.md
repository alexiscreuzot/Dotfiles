Report monthly Forum invoice for the month I name (e.g. August, 2026-08). Default to the previous calendar month if I do not specify one.

This is local-only. Read and run files under `~/.cursor/monthly-hours/` and follow `~/.cursor/skills/monthly-invoice/SKILL.md`. Do not write anything into a git repo.

**Stop and confirm before writing any invoice file.**

1. Dry-run: `python3 ~/.cursor/monthly-hours/invoice.py YYYY-MM --dry-run`
2. Show me the proposed **invoice number**, **issue date**, **OOO dates**, hours, and total. Wait until I say it is correct, or I give replacements.
3. Then generate with those values, e.g. `python3 ~/.cursor/monthly-hours/invoice.py YYYY-MM --number 2026-010 --issue-date 2026-09-01 --ooo none` (or `--ooo 2026-08-15,2026-08-16`).
4. Tell me the PDF path in Downloads. Do not invent hours — use the script output.
