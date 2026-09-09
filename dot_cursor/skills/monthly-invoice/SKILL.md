---
name: monthly-invoice
description: >
  Builds Alexis's weekly Forum invoice PDF from weekdays in the month minus
  Sorenson Outlook OOO (title contains OOO or Out of Office) at $66.15/h.
  Dry-runs first, confirms invoice number / issue date / OOO with him, then
  writes a one-page PDF to Downloads. Use when he asks for an invoice, invoice
  PDF, billing hours, or invokes the monthly-invoice command.
---

# Monthly invoice

Local-only. All files live under `~/.cursor/monthly-hours/`. Never add this to a repository.

## Rules

- Hours = weekdays in each ISO week (clipped to the month) × 8, minus OOO days.
- **OOO** = Outlook events whose title matches `config.json` `invoice.oooTitleRegex` (`OOO` or `Out of Office`), **or** Outlook Out of Office status (`X-MICROSOFT-CDO-BUSYSTATUS:OOF` / Graph `showAs=oof`). The published ICS feed often titles those `Away`. All-day events count. Any weekday overlapped by a matching event is a full non-working day.
- Do **not** subtract holidays, Busy, Vacation, PTO, or anything else unless the title matches.
- Rate and line description come from `config.json` `invoice.rate` / `invoice.description`.
- Skip a leading weekend-only week. Omit a week with 0 billable hours.
- Invoice number: scan `invoice.outputDir` (Downloads) for `YYYY-NNN [invoice] Alexis Creuzot Consulting.{docx,pdf}`, take the next `NNN` for the issue-date year. Filename is `{year}-{seq:03d} [invoice] Alexis Creuzot Consulting.pdf`.
- Issue date defaults to today in `config.json` timezone, but he must confirm it.
- NOTES: `OOO {Month} {D}` (comma-separated if several), plus `IVA no aplicable`. If there is no OOO, leave that line blank.
- Invoice PDF is Letter, **one page**. Header (tall blue BILL TO), line items, then NOTES / total / bank pinned to the bottom. Extra weeks shrink row height rather than spilling to page 2.
- Do not change the timesheet budget in `report.py`.

## Steps

1. Resolve the month to `YYYY-MM`. Default: previous calendar month.
2. Dry-run only (do not run `xcodebuild` or tests):

   ```bash
   python3 ~/.cursor/monthly-hours/invoice.py YYYY-MM --dry-run
   ```

   If the calendar is unavailable, ask for a **local** `.ics` that includes OOO and add `--ics PATH`. See `~/.cursor/monthly-hours/ICS.md`.
3. **Stop. Do not write the PDF yet.** Show the proposed values and wait for an explicit OK, or replacements:
   - Invoice number (`YYYY-NNN`)
   - Issue date
   - OOO dates (he may add, remove, or clear them)
   - Hours and total
4. Only after he confirms, generate:

   ```bash
   python3 ~/.cursor/monthly-hours/invoice.py YYYY-MM --number YYYY-NNN --issue-date YYYY-MM-DD --ooo none
   ```

   Use `--ooo 2026-08-15,2026-08-16` when there are OOO days. If he changed OOO, pass that list so hours/total match.
5. The script writes a numbered `.docx` + `.pdf` in Downloads and opens the PDF. Tell him the PDF path. Do **not** paste the line-item grid in a chat code block.
6. Do not commit, push, or write these files into `forum-iOS` or any other repo.

## Scripts

| Script | Role |
|--------|------|
| `invoice.py YYYY-MM --dry-run` | Propose number, date, OOO, totals (no files) |
| `invoice.py YYYY-MM [--number] [--issue-date] [--ooo]` | Write Word + PDF after confirm |
| `fill_docx.py` | Template fill |
| `pdf_invoice.py` | Letter PDF (reportlab, local venv) |
