#!/usr/bin/env python3
"""Weekly invoice lines: weekdays in the month minus Outlook OOO."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import fill_docx

DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR))
import graph_auth
import report
import importlib.util

_scrum_spec = importlib.util.spec_from_file_location("scrum_hours", DIR / "scrum-hours.py")
scrum_hours = importlib.util.module_from_spec(_scrum_spec)
assert _scrum_spec.loader is not None
_scrum_spec.loader.exec_module(scrum_hours)


def _money(value: float) -> str:
    return f"${value:,.2f}"


def week_label(week: list[date], description: str) -> str:
    iso = week[0].isocalendar()[1]
    name = week[0].strftime("%B")
    return f"Week#{iso} ({name} {week[0].strftime('%d')} to {week[-1].strftime('%d')}) - {description}"


def _parse_ics_date(value: str) -> date:
    return datetime.strptime(value[:8], "%Y%m%d").date()


def _dates_in_span(start_d: date, end_exclusive: date):
    d = start_d
    while d < end_exclusive:
        yield d
        d += timedelta(days=1)


def _timed_dates(start: datetime, end: datetime, tz: ZoneInfo):
    local_start = start.astimezone(tz)
    local_end = end.astimezone(tz)
    if local_end <= local_start:
        return
    last = local_end.date()
    if local_end.timetz().replace(tzinfo=None) == time.min:
        last -= timedelta(days=1)
    d = local_start.date()
    while d <= last:
        yield d
        d += timedelta(days=1)


def _expand_all_day(dtstart: date, duration_days: int, rrule: str | None, window_start: date, window_end: date):
    if duration_days <= 0:
        duration_days = 1
    if not rrule:
        yield dtstart
        return
    parts = dict(p.split("=", 1) for p in rrule.split(";") if "=" in p)
    freq = parts.get("FREQ")
    interval = int(parts.get("INTERVAL") or 1)
    until = _parse_ics_date(parts["UNTIL"]) if parts.get("UNTIL") else None
    count = int(parts["COUNT"]) if parts.get("COUNT") else None
    last = window_end
    if until:
        last = min(last, until)
    n = 0
    if freq == "DAILY":
        cursor = dtstart
        while cursor <= last:
            if cursor >= window_start:
                yield cursor
                n += 1
                if count is not None and n >= count:
                    return
            cursor += timedelta(days=interval)
        return
    if freq == "WEEKLY":
        days = {scrum_hours._BYDAY[d] for d in (parts.get("BYDAY") or "").split(",") if d in scrum_hours._BYDAY}
        if not days:
            days = {dtstart.weekday()}
        cursor = dtstart
        while cursor <= last:
            if cursor >= window_start and cursor.weekday() in days:
                weeks = (cursor - dtstart).days // 7
                if weeks >= 0 and weeks % interval == 0:
                    yield cursor
                    n += 1
                    if count is not None and n >= count:
                        return
            cursor += timedelta(days=1)
        return
    yield dtstart


def parse_ics_ooo(path: Path, start: datetime, end: datetime, tz: ZoneInfo) -> list[dict]:
    text = path.read_text(errors="replace")
    blocks = re.split(r"\nBEGIN:VEVENT\n", text)
    events: list[dict] = []
    window_start, window_end = start.date(), end.date()
    for block in blocks[1:]:
        body = block.split("\nEND:VEVENT", 1)[0]
        fields: dict[str, str] = {}
        key = None
        for raw in body.splitlines():
            if raw.startswith(" ") and key:
                fields[key] += raw[1:]
                continue
            if ":" not in raw:
                continue
            k, v = raw.split(":", 1)
            key = k.split(";", 1)[0]
            fields[key] = v
        if fields.get("STATUS", "").upper() == "CANCELLED":
            continue
        dtstart = fields.get("DTSTART")
        dtend = fields.get("DTEND")
        if not dtstart:
            continue
        subject = scrum_hours._unescape_ics(fields.get("SUMMARY", ""))
        rrule = fields.get("RRULE")
        all_day = len(dtstart) == 8 or (fields.get("X-MICROSOFT-CDO-ALLDAYEVENT") or "").upper() == "TRUE"
        if all_day:
            start_d = _parse_ics_date(dtstart)
            end_d = _parse_ics_date(dtend) if dtend else start_d + timedelta(days=1)
            duration_days = max(1, (end_d - start_d).days)
            starts = list(_expand_all_day(start_d, duration_days, rrule if not fields.get("RECURRENCE-ID") else None, window_start, window_end))
            for inst in starts:
                inst_end = inst + timedelta(days=duration_days)
                if inst_end <= window_start or inst >= window_end:
                    continue
                events.append(
                    {
                        "subject": subject,
                        "start": inst.isoformat(),
                        "end": inst_end.isoformat(),
                        "isAllDay": True,
                        "busyStatus": fields.get("X-MICROSOFT-CDO-BUSYSTATUS") or "",
                    }
                )
            continue
        ev_start = scrum_hours._parse_ics_dt(dtstart, tz)
        ev_end = scrum_hours._parse_ics_dt(dtend, tz) if dtend else ev_start + timedelta(hours=1)
        duration = ev_end - ev_start
        starts = [ev_start]
        if rrule and not fields.get("RECURRENCE-ID"):
            starts = list(scrum_hours._expand_weekly(ev_start, rrule, start, end))
        for inst in starts:
            inst_end = inst + duration
            if inst_end <= start or inst >= end:
                continue
            events.append(
                {
                    "subject": subject,
                    "start": inst.isoformat(),
                    "end": inst_end.isoformat(),
                    "isAllDay": False,
                    "busyStatus": fields.get("X-MICROSOFT-CDO-BUSYSTATUS") or "",
                }
            )
    return events


def graph_to_events(raw: list[dict], tz: ZoneInfo) -> list[dict]:
    out = []
    for ev in raw:
        if not scrum_hours._response_ok(ev):
            continue
        start_raw = (ev.get("start") or {}).get("dateTime") or (ev.get("start") or {}).get("date") or ""
        end_raw = (ev.get("end") or {}).get("dateTime") or (ev.get("end") or {}).get("date") or ""
        if not start_raw or not end_raw:
            continue
        all_day = bool(ev.get("isAllDay"))
        if all_day and len(start_raw) >= 10 and "T" not in start_raw:
            start_s = start_raw[:10]
            end_s = end_raw[:10]
        elif all_day:
            start_s = scrum_hours._parse_dt(start_raw, tz).date().isoformat()
            end_s = scrum_hours._parse_dt(end_raw, tz).date().isoformat()
        else:
            start_s = scrum_hours._parse_dt(start_raw, tz).isoformat()
            end_s = scrum_hours._parse_dt(end_raw, tz).isoformat()
        out.append(
            {
                "subject": ev.get("subject") or "",
                "start": start_s,
                "end": end_s,
                "isAllDay": all_day,
                "showAs": (ev.get("showAs") or ""),
                "busyStatus": (ev.get("showAs") or ""),
            }
        )
    return out


def is_ooo(ev: dict, pattern: re.Pattern) -> bool:
    subject = ev.get("subject") or ""
    if pattern.search(subject):
        return True
    status = (ev.get("busyStatus") or ev.get("showAs") or "").lower()
    # Published Outlook ICS strips titles; OOO is SUMMARY "Away" + BUSYSTATUS OOF.
    return status in ("oof", "outofoffice")


def ooo_days(events: list[dict], pattern: re.Pattern, year: int, month: int, tz: ZoneInfo) -> list[dict]:
    month_start = date(year, month, 1)
    if month == 12:
        month_end = date(year + 1, 1, 1)
    else:
        month_end = date(year, month + 1, 1)
    found: dict[date, str] = {}
    for ev in events:
        if not is_ooo(ev, pattern):
            continue
        subject = ev.get("subject") or ""
        start_s, end_s = ev.get("start") or "", ev.get("end") or ""
        if ev.get("isAllDay") or (len(start_s) == 10 and "T" not in start_s):
            start_d = date.fromisoformat(start_s[:10])
            end_d = date.fromisoformat(end_s[:10]) if end_s else start_d + timedelta(days=1)
            days = _dates_in_span(start_d, end_d)
        else:
            start_dt = scrum_hours._parse_dt(start_s, tz)
            end_dt = scrum_hours._parse_dt(end_s, tz)
            days = _timed_dates(start_dt, end_dt, tz)
        for d in days:
            if d < month_start or d >= month_end or d.weekday() >= 5:
                continue
            found.setdefault(d, subject)
    return [{"date": d.isoformat(), "subject": found[d]} for d in sorted(found)]


def load_events(args, start: datetime, end: datetime, tz: ZoneInfo, cfg: dict) -> tuple[list[dict], str]:
    ics_url = args.ics_url or cfg.get("icsUrl")
    if args.ics:
        return parse_ics_ooo(Path(args.ics), start, end, tz), "ics"
    if ics_url:
        req = urllib.request.Request(ics_url, headers={"User-Agent": "monthly-invoice"})
        with urllib.request.urlopen(req) as resp:
            Path("/tmp/monthly-invoice.ics").write_bytes(resp.read())
        return parse_ics_ooo(Path("/tmp/monthly-invoice.ics"), start, end, tz), "ics-url"
    raw = scrum_hours.fetch_graph_events(start, end, tz)
    return graph_to_events(raw, tz), "graph"


def write_excel_copy(month: str, rows: list[tuple[str, str, int, str]]) -> Path:
    html_path = DIR / f"{month}-invoice.html"
    csv_path = DIR / f"{month}-invoice.csv"
    rows_html = []
    rows_csv = []
    for desc, rate, hours, amount in rows:
        rows_html.append(
            "<tr>"
            f"<td>{desc}</td><td>{rate}</td><td>{hours}</td><td>{amount}</td>"
            "</tr>"
        )
        rows_csv.append(",".join([desc.replace(",", " "), rate, str(hours), amount]))
    html_path.write_text(
        "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>\n"
        "<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">\n"
        + "\n".join(rows_html)
        + "\n</table>\n<p>Select the table, copy, click the first invoice cell, paste.</p>\n"
        "</body></html>\n"
    )
    csv_path.write_text("\n".join(rows_csv) + "\n")
    print(f"EXCEL_COPY {html_path}", flush=True)
    return html_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("month", help="YYYY-MM")
    parser.add_argument("--ics")
    parser.add_argument("--ics-url")
    parser.add_argument("--number", help="Invoice number YYYY-NNN (default: next in Downloads)")
    parser.add_argument("--issue-date", help="YYYY-MM-DD (default: today)")
    parser.add_argument("--ooo", help="Comma-separated YYYY-MM-DD, or 'none' to override the calendar")
    parser.add_argument("--dry-run", action="store_true", help="Print proposed values; do not write files")
    args = parser.parse_args()
    year, month = map(int, args.month.split("-"))
    cfg = graph_auth.load_config()
    inv = cfg.get("invoice") or {}
    rate = float(inv.get("rate") or 66.15)
    description = inv.get("description") or "Software consulting"
    hour = int(cfg.get("hourPerWeekday") or 8)
    tz = ZoneInfo(cfg.get("timezone") or "America/Mexico_City")
    start, end = scrum_hours.month_bounds(year, month, tz)
    pattern = re.compile(inv.get("oooTitleRegex") or r"\bOOO\b|out of office", re.I)

    try:
        events, source = load_events(args, start, end, tz, cfg)
    except Exception as e:
        raise SystemExit(
            "Calendar unavailable. Pass --ics PATH (Outlook drag of OOO events).\n" + str(e)
        )

    calendar_ooo = ooo_days(events, pattern, year, month, tz)
    if args.ooo is None:
        ooo = calendar_ooo
    elif args.ooo.strip().lower() in ("none", ""):
        ooo = []
    else:
        ooo = [{"date": part.strip(), "subject": "confirmed"} for part in args.ooo.split(",") if part.strip()]
    ooo_set = {date.fromisoformat(r["date"]) for r in ooo}
    weeks = report.working_weeks(year, month)
    rows = []
    total_hours = 0
    for week in weeks:
        billable = [d for d in week if d not in ooo_set]
        hours = len(billable) * hour
        if hours <= 0:
            continue
        amount = hours * rate
        rows.append((week_label(week, description), _money(rate), hours, _money(amount)))
        total_hours += hours

    total = _money(total_hours * rate)
    output_dir = Path(inv.get("outputDir") or str(Path.home() / "Downloads")).expanduser()
    template = Path(inv.get("template") or str(DIR / "invoice-template.docx")).expanduser()
    if not template.is_absolute():
        template = DIR / template
    issue = date.fromisoformat(args.issue_date) if args.issue_date else datetime.now(tz).date()
    if args.number:
        parts = args.number.split("-")
        inv_year, seq = int(parts[0]), int(parts[1])
    else:
        inv_year, seq = fill_docx.next_number(output_dir, issue.year)
    stem = fill_docx.file_stem(inv_year, seq)
    invoice_no = f"{inv_year}-{seq:03d}"
    docx_path = output_dir / f"{stem}.docx"
    pdf_path = output_dir / f"{stem}.pdf"
    ooo_note = fill_docx.notes_ooo(ooo)

    print(f"Month {args.month}  rate {_money(rate)}")
    print(f"Calendar source: {source}")
    print(f"Invoice #{invoice_no}")
    print(f"Issue date: {issue.isoformat()}")
    print(f"OOO days: {len(ooo)}")
    if ooo:
        for row in ooo:
            print(f"- {row['date']}  {row['subject']}")
    else:
        print("- (none)")
    print()
    for desc, rate_s, hours, amount in rows:
        print(f"{desc}")
        print(f"  {rate_s}  {hours}h  {amount}")
    print(f"\nTotal  {total_hours}h  {total}")
    if args.dry_run:
        print("DRY_RUN  no files written — confirm month, number, issue date, OOO, total")
        return

    write_excel_copy(args.month, rows)
    fill_docx.fill_docx(
        template,
        docx_path,
        invoice_no,
        issue,
        rows,
        total,
        ooo_note,
    )
    print(f"DOCX {docx_path}", flush=True)
    fill_docx.export_pdf(
        pdf_path,
        {
            "invoice_no": invoice_no,
            "issue_date": issue.isoformat(),
            "lines": [list(row) for row in rows],
            "total": total,
            "ooo_note": ooo_note,
            "bank": inv.get("bank") or {},
        },
    )
    print(f"PDF {pdf_path}", flush=True)
    subprocess.Popen(["open", str(pdf_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
