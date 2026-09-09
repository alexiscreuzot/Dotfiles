#!/usr/bin/env python3
"""Scrum hours for a month from Microsoft Graph, or from an Outlook .ics export."""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR))
import graph_auth


def month_bounds(year: int, month: int, tz: ZoneInfo) -> tuple[datetime, datetime]:
    start = datetime(year, month, 1, tzinfo=tz)
    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=tz)
    else:
        end = datetime(year, month + 1, 1, tzinfo=tz)
    return start, end


def _parse_dt(value: str, tz: ZoneInfo) -> datetime:
    if value.endswith("Z"):
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(tz)
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=tz)
    return dt.astimezone(tz)


def _title_ok(subject: str, pattern: re.Pattern) -> bool:
    return bool(pattern.search(subject or ""))


def _response_ok(event: dict) -> bool:
    if event.get("isCancelled"):
        return False
    status = ((event.get("responseStatus") or {}).get("response") or "").lower()
    if status in ("declined", "none"):
        # "none" is often the organizer; keep those.
        if status == "declined":
            return False
    return True


def fetch_graph_events(start: datetime, end: datetime, tz: ZoneInfo) -> list[dict]:
    token = graph_auth.access_token()
    params = {
        "startDateTime": start.isoformat(),
        "endDateTime": end.isoformat(),
        "$select": "subject,start,end,isCancelled,isAllDay,responseStatus,showAs,organizer",
        "$top": "100",
    }
    url = "https://graph.microsoft.com/v1.0/me/calendarView?" + urllib.parse.urlencode(params)
    events: list[dict] = []
    while url:
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "Prefer": f'outlook.timezone="{tz.key}"',
            },
        )
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            raise SystemExit(f"Graph calendarView failed ({e.code}): {e.read().decode()[:400]}")
        events.extend(data.get("value") or [])
        url = data.get("@odata.nextLink")
    return events


def parse_ics(path: Path, start: datetime, end: datetime, tz: ZoneInfo) -> list[dict]:
    text = path.read_text(errors="replace")
    blocks = re.split(r"\nBEGIN:VEVENT\n", text)
    events: list[dict] = []
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
        if not dtstart or not dtend:
            continue
        if len(dtstart) == 8:
            continue  # all-day
        ev_start = _parse_ics_dt(dtstart, tz)
        ev_end = _parse_ics_dt(dtend, tz)
        duration = ev_end - ev_start
        subject = _unescape_ics(fields.get("SUMMARY", ""))
        rrule = fields.get("RRULE")
        starts = [ev_start]
        if rrule and not fields.get("RECURRENCE-ID"):
            starts = list(_expand_weekly(ev_start, rrule, start, end))
        for inst in starts:
            inst_end = inst + duration
            if inst_end <= start or inst >= end:
                continue
            events.append(
                {
                    "subject": subject,
                    "start": {"dateTime": inst.isoformat()},
                    "end": {"dateTime": inst_end.isoformat()},
                    "isCancelled": False,
                    "isAllDay": False,
                    "responseStatus": {"response": "accepted"},
                }
            )
    return events


_BYDAY = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


def _expand_weekly(dtstart: datetime, rrule: str, window_start: datetime, window_end: datetime):
    parts = dict(p.split("=", 1) for p in rrule.split(";") if "=" in p)
    if parts.get("FREQ") != "WEEKLY":
        yield dtstart
        return
    interval = int(parts.get("INTERVAL") or 1)
    until = None
    if parts.get("UNTIL"):
        until = _parse_ics_dt(parts["UNTIL"], dtstart.tzinfo)
    days = {_BYDAY[d] for d in (parts.get("BYDAY") or "").split(",") if d in _BYDAY}
    if not days:
        days = {dtstart.weekday()}
    cursor = dtstart.date()
    last = window_end.date()
    if until:
        last = min(last, until.date())
    # Walk back to the week of DTSTART, then forward through the window.
    while cursor <= last:
        if cursor >= window_start.date() and cursor.weekday() in days:
            weeks = (cursor - dtstart.date()).days // 7
            if weeks >= 0 and weeks % interval == 0:
                inst = datetime.combine(cursor, dtstart.timetz())
                if inst >= dtstart and (until is None or inst <= until):
                    yield inst
        cursor += timedelta(days=1)


def _unescape_ics(value: str) -> str:
    return value.replace("\\n", " ").replace("\\,", ",").replace("\\;", ";")


def _parse_ics_dt(value: str, tz: ZoneInfo) -> datetime:
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).astimezone(tz)
    return datetime.strptime(value[:15], "%Y%m%dT%H%M%S").replace(tzinfo=tz)


def summarize(events: list[dict], start: datetime, end: datetime, tz: ZoneInfo, pattern: re.Pattern) -> dict:
    rows = []
    hours = 0.0
    for ev in events:
        if ev.get("isAllDay"):
            continue
        if not _response_ok(ev):
            continue
        subject = ev.get("subject") or ""
        if not _title_ok(subject, pattern):
            continue
        ev_start = _parse_dt((ev.get("start") or {}).get("dateTime") or "", tz)
        ev_end = _parse_dt((ev.get("end") or {}).get("dateTime") or "", tz)
        if ev_end <= start or ev_start >= end:
            continue
        clipped_start = max(ev_start, start)
        clipped_end = min(ev_end, end)
        dur = (clipped_end - clipped_start).total_seconds() / 3600
        if dur <= 0:
            continue
        hours += dur
        rows.append(
            {
                "start": clipped_start.isoformat(timespec="minutes"),
                "end": clipped_end.isoformat(timespec="minutes"),
                "hours": round(dur, 4),
                "subject": subject,
            }
        )
    rows.sort(key=lambda r: r["start"])
    return {"hours": round(hours, 4), "events": rows}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("month", help="YYYY-MM")
    parser.add_argument("--ics", help="Outlook .ics export if Graph is blocked")
    parser.add_argument("--ics-url", help="Published Outlook ICS URL")
    parser.add_argument("--all", action="store_true", help="Do not filter by Scrum title regex")
    args = parser.parse_args()
    year, month = map(int, args.month.split("-"))
    cfg = graph_auth.load_config()
    tz = ZoneInfo(cfg.get("timezone") or "America/Mexico_City")
    start, end = month_bounds(year, month, tz)
    pattern = re.compile(cfg["scrumTitleRegex"], re.I)
    ics_url = args.ics_url or cfg.get("icsUrl")
    if args.all:
        pattern = re.compile(".", re.I)
    if ics_url and not args.ics:
        req = urllib.request.Request(ics_url, headers={"User-Agent": "monthly-hours"})
        with urllib.request.urlopen(req) as resp:
            Path("/tmp/monthly-hours.ics").write_bytes(resp.read())
        events = parse_ics(Path("/tmp/monthly-hours.ics"), start, end, tz)
        source = "ics-url"
    elif args.ics:
        events = parse_ics(Path(args.ics), start, end, tz)
        source = "ics"
    else:
        events = fetch_graph_events(start, end, tz)
        source = "graph"
    out = summarize(events, start, end, tz, pattern)
    out["source"] = source
    out["month"] = args.month
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
