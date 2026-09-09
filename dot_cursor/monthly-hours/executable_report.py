#!/usr/bin/env python3
"""Classify month work and print the four timesheet lines plus a work summary."""
from __future__ import annotations

import argparse
import calendar
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR))
import graph_auth


def weekday_count(year: int, month: int) -> int:
    return sum(1 for day in range(1, calendar.monthrange(year, month)[1] + 1)
               if calendar.weekday(year, month, day) < 5)


def run_json(script: str, args: list[str]) -> dict:
    cmd = [sys.executable, str(DIR / script), *args]
    raw = subprocess.check_output(cmd, text=True)
    return json.loads(raw)


def effort(ticket: dict | None, commit_count: int, is_bug: bool) -> float:
    if ticket and ticket.get("points"):
        weight = float(ticket["points"])
    elif is_bug:
        weight = 2.0
    else:
        weight = 3.0
    extra = max(0, commit_count - 1)
    return weight + 0.5 * extra


def classify_unticketed(subject: str, cfg: dict) -> str:
    if re.search(cfg.get("ktloSummaryRegex") or "$^", subject, re.I):
        return "KTLO"
    return "CapEx"


def classify_ticket(ticket: dict, cfg: dict) -> str:
    if ticket.get("iriusrisk"):
        return "IriusRisk"
    if ticket.get("type") in (cfg.get("ktloIssueTypes") or ["Bug"]):
        return "KTLO"
    if re.search(cfg.get("ktloSummaryRegex") or "$^", ticket.get("summary") or "", re.I):
        return "KTLO"
    # Product / feature stories and technical improvements → CapEx
    return "CapEx"


def irius_hours(ticket: dict, cfg: dict) -> float:
    hours = cfg["iriusrisk"]["hours"]
    if ticket.get("hasCommits"):
        return float(hours["implemented"])
    status = (ticket.get("status") or "").lower()
    if "progress" in status or status in ("qa in progress", "qa to do", "validate"):
        return float(hours["inProgress"])
    if not re.search(cfg["iriusrisk"].get("commentOnlySummaryRegex") or "", ticket.get("summary") or "", re.I):
        return 0.0
    return float(hours["commentOnly"])


def nearest_int_split(total: float, capex_w: float, ktlo_w: float) -> tuple[int, int]:
    leftover = max(0.0, total)
    target = int(round(leftover))
    if capex_w + ktlo_w <= 0:
        return target, 0
    capex = leftover * (capex_w / (capex_w + ktlo_w))
    capex_i = int(round(capex))
    ktlo_i = target - capex_i
    if ktlo_i < 0:
        capex_i = target
        ktlo_i = 0
    return capex_i, ktlo_i


def working_weeks(year: int, month: int) -> list[list[date]]:
    """Mon–Fri groups in the month. A leading weekend-only week is omitted."""
    groups: list[list[date]] = []
    for day in range(1, calendar.monthrange(year, month)[1] + 1):
        d = date(year, month, day)
        if d.weekday() >= 5:
            continue
        if not groups or d.isocalendar()[1] != groups[-1][0].isocalendar()[1]:
            groups.append([])
        groups[-1].append(d)
    return groups


def _in_week(iso: str, week: list[date]) -> bool:
    if not iso or len(iso) < 10:
        return False
    try:
        d = date.fromisoformat(iso[:10])
    except ValueError:
        return False
    return week[0] <= d <= week[-1]


def distribute(total: int, weights: list[float]) -> list[int]:
    if total <= 0 or not weights:
        return [0] * len(weights)
    s = sum(weights)
    if s <= 0:
        weights = [1.0] * len(weights)
        s = float(len(weights))
    raw = [total * w / s for w in weights]
    floors = [int(x) for x in raw]
    leftover = total - sum(floors)
    order = sorted(range(len(raw)), key=lambda i: (raw[i] - floors[i], i), reverse=True)
    for i in order[:leftover]:
        floors[i] += 1
    return floors


def weekly_grid(
    year: int,
    month: int,
    capex_i: int,
    scrum_i: int,
    irius_i: int,
    ktlo_i: int,
    scrum: dict,
    commits: list[dict],
    tickets: dict,
    items: dict,
    cfg: dict,
) -> list[list[int]]:
    weeks = working_weeks(year, month)
    n = len(weeks)
    hour = int(cfg.get("hourPerWeekday") or 8)
    budgets = [len(w) * hour for w in weeks]

    scrum_w = []
    for week in weeks:
        h = 0.0
        for ev in scrum.get("events") or []:
            if _in_week(ev.get("start") or "", week):
                h += float(ev.get("hours") or 0)
        scrum_w.append(h if h else (len(week) if scrum.get("source") == "placeholder" else 0.0))
    if scrum_i and sum(scrum_w) <= 0:
        scrum_w = [float(len(w)) for w in weeks]
    scrum_row = distribute(scrum_i, scrum_w)

    irius_w = []
    irius_keys = {k for k, _, _ in items.get("IriusRisk") or []}
    for week in weeks:
        h = 0.0
        for t in tickets.values():
            if t["key"] not in irius_keys:
                continue
            if _in_week(t.get("updated") or "", week) or _in_week(t.get("resolved") or "", week):
                h += 1
            if t.get("hasCommits"):
                for c in commits:
                    if t["key"] in c.get("keys", []) and _in_week(c.get("date") or "", week):
                        h += 2
        irius_w.append(h)
    irius_row = distribute(irius_i, irius_w)

    capex_w, ktlo_w = [], []
    for week in weeks:
        cw = kw = 0.0
        for c in commits:
            if not _in_week(c.get("date") or "", week):
                continue
            keys = c.get("keys") or []
            if keys:
                t = tickets.get(keys[0])
                bucket = classify_ticket(t, cfg) if t else "KTLO"
            else:
                bucket = classify_unticketed(c.get("subject") or "", cfg)
            if bucket == "CapEx":
                cw += 1
            elif bucket == "KTLO":
                kw += 1
        capex_w.append(cw)
        ktlo_w.append(kw)
    # Fill each week to budget after scrum+irius, then scale rows to monthly totals.
    rem = [max(0, budgets[i] - scrum_row[i] - irius_row[i]) for i in range(n)]
    capex_row, ktlo_row = [], []
    for i in range(n):
        c, k = nearest_int_split(rem[i], capex_w[i], ktlo_w[i])
        capex_row.append(c)
        ktlo_row.append(k)
    # Nudge CapEx/KTLO so monthly row totals match.
    def nudge(row: list[int], target: int, partner: list[int]) -> None:
        diff = target - sum(row)
        i = 0
        while diff != 0 and i < n * 4:
            idx = (n - 1 - (i % n)) if diff < 0 else (i % n)
            if diff > 0 and partner[idx] > 0:
                row[idx] += 1
                partner[idx] -= 1
                diff -= 1
            elif diff < 0 and row[idx] > 0:
                row[idx] -= 1
                partner[idx] += 1
                diff += 1
            i += 1

    nudge(capex_row, capex_i, ktlo_row)
    nudge(ktlo_row, ktlo_i, capex_row)
    return [capex_row, scrum_row, irius_row, ktlo_row]


def write_excel_copy(month: str, grid: list[list[int]]) -> Path:
    html_path = DIR / f"{month}-hours.html"
    csv_path = DIR / f"{month}-hours.csv"
    rows_html = []
    rows_csv = []
    for row in grid:
        rows_html.append("<tr>" + "".join(f"<td>{n}</td>" for n in row) + "</tr>")
        rows_csv.append(",".join(str(n) for n in row))
    html_path.write_text(
        "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>\n"
        "<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">\n"
        + "\n".join(rows_html)
        + "\n</table>\n<p>Select the table, copy, click the first Excel cell, paste.</p>\n"
        "</body></html>\n"
    )
    csv_path.write_text("\n".join(rows_csv) + "\n")
    subprocess.Popen(["open", str(html_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"EXCEL_COPY {html_path}", flush=True)
    return html_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("month", help="YYYY-MM")
    parser.add_argument("--ics")
    parser.add_argument("--ics-url")
    parser.add_argument("--scrum-placeholder", type=float, default=None,
                        help="Use this Scrum total if Graph/ICS is unavailable")
    args = parser.parse_args()
    year, month = map(int, args.month.split("-"))
    cfg = graph_auth.load_config()
    budget = weekday_count(year, month) * int(cfg.get("hourPerWeekday") or 8)

    scrum = None
    scrum_error = None
    if args.scrum_placeholder is not None and not args.ics and not args.ics_url:
        scrum = {"hours": args.scrum_placeholder, "events": [], "source": "placeholder"}
    else:
        scrum_args = [args.month]
        if args.ics:
            scrum_args += ["--ics", args.ics]
        if args.ics_url:
            scrum_args += ["--ics-url", args.ics_url]
        elif cfg.get("icsUrl"):
            scrum_args += ["--ics-url", cfg["icsUrl"]]
        try:
            scrum = run_json("scrum-hours.py", scrum_args)
        except subprocess.CalledProcessError as e:
            scrum_error = e.output if isinstance(e.output, str) else (e.stderr or str(e))
            if args.scrum_placeholder is None:
                raise SystemExit(
                    "Scrum calendar unavailable. Log in with "
                    f"{DIR / 'graph_auth.py'} login, or pass --ics / --scrum-placeholder.\n"
                    + (scrum_error or "")
                )
            scrum = {"hours": args.scrum_placeholder, "events": [], "source": "placeholder"}

    work = run_json("month-work.py", [args.month])
    commits = work["commits"]
    tickets = {t["key"]: t for t in work["tickets"]}
    commit_keys = {k for c in commits for k in c["keys"]}

    # Only August commits + IriusRisk assessment activity this month.
    items = {"CapEx": [], "KTLO": [], "IriusRisk": []}
    irius_h = 0.0
    capex_w = 0.0
    ktlo_w = 0.0

    for t in tickets.values():
        bucket = classify_ticket(t, cfg)
        if bucket == "IriusRisk":
            h = irius_hours(t, cfg)
            if h <= 0:
                continue
            irius_h += h
            items["IriusRisk"].append((t["key"], t["summary"], h))
            continue
        if not t.get("hasCommits"):
            continue
        w = effort(t, t.get("commitCount") or 1, t.get("type") == "Bug")
        if bucket == "CapEx":
            capex_w += w
        else:
            ktlo_w += w
        items[bucket].append((t["key"], t["summary"], w))

    for c in commits:
        if c["keys"]:
            continue
        bucket = classify_unticketed(c["subject"], cfg)
        w = 2.0
        if bucket == "KTLO":
            ktlo_w += w
        else:
            capex_w += w
        items[bucket].append((c["sha"], c["subject"], w))

    scrum_h = float(scrum.get("hours") or 0)
    scrum_i = int(round(scrum_h))
    irius_i = int(round(irius_h))
    leftover = budget - scrum_i - irius_i
    if leftover < 0:
        # Meetings + IriusRisk exceeded the month; still report actuals and note the overrun.
        capex_i, ktlo_i = 0, 0
    else:
        capex_i, ktlo_i = nearest_int_split(leftover, capex_w, ktlo_w)

    lines = [
        ("CapEx UK Forum", capex_i),
        ("Scrum meetings", scrum_i),
        ("IriusRisk", irius_i),
        ("KTLO", ktlo_i),
    ]
    grid = weekly_grid(
        year, month, capex_i, scrum_i, irius_i, ktlo_i,
        scrum, commits, tickets, items, cfg,
    )
    write_excel_copy(args.month, grid)

    print(f"Month {args.month}  (budget {budget}h = {weekday_count(year, month)} weekdays × 8)")
    print(f"Scrum source: {scrum.get('source')}")
    print()
    for name, hours in lines:
        print(f"{name:<20}{hours}")
    print(f"{'Total':<20}{sum(h for _, h in lines)}")
    if leftover < 0:
        print(f"\nNote: Scrum + IriusRisk ({scrum_i}+{irius_i}) exceed the {budget}h budget.")

    print("\n## What was done\n")
    print("CapEx UK Forum")
    if items["CapEx"]:
        for key, summary, _ in items["CapEx"]:
            print(f"- {key} — {summary}")
    else:
        print("- (none)")
    print("\nKTLO")
    if items["KTLO"]:
        for key, summary, _ in items["KTLO"]:
            print(f"- {key} — {summary}")
    else:
        print("- (none)")
    print("\nIriusRisk")
    if items["IriusRisk"]:
        for key, summary, h in items["IriusRisk"]:
            print(f"- {key} — {summary} ({h:g}h)")
    else:
        print("- (none)")
    print("\nScrum meetings")
    events = scrum.get("events") or []
    if events:
        for ev in events:
            print(f"- {ev['start'][:16]}  {ev['hours']:g}h  {ev['subject']}")
    elif scrum.get("source") == "placeholder":
        print(f"- placeholder {scrum_i}h (calendar not connected)")
    else:
        print("- (none matched the Scrum title regex)")


if __name__ == "__main__":
    main()
