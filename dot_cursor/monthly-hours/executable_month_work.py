#!/usr/bin/env python3
"""August-style month work: git commits this month + matching Jira tickets."""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR))
import graph_auth

TICKET_RE = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")


def month_range(year: int, month: int) -> tuple[str, str, str]:
    start = date(year, month, 1)
    if month == 12:
        end = date(year + 1, 1, 1)
    else:
        end = date(year, month + 1, 1)
    return start.isoformat(), end.isoformat(), (end.isoformat())


def load_env(path: str) -> dict[str, str]:
    env: dict[str, str] = {}
    p = Path(path)
    if not p.exists():
        return env
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def git_commits(repo: dict, since: str, until: str) -> list[dict]:
    authors = repo.get("authors") or []
    cmd = [
        "git",
        "-C",
        repo["path"],
        "log",
        f"--since={since}",
        f"--until={until}",
        "--no-merges",
        "--pretty=format:%H|%ad|%an|%ae|%s",
        "--date=short",
    ]
    raw = subprocess.check_output(cmd, text=True)
    rows = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        sha, day, name, email, subject = (line.split("|", 4) + [""] * 5)[:5]
        blob = f"{name} {email}"
        if authors and not any(a.lower() in blob.lower() for a in authors):
            continue
        keys = TICKET_RE.findall(subject)
        rows.append(
            {
                "sha": sha[:10],
                "date": day,
                "author": name,
                "subject": subject,
                "keys": keys,
                "repo": repo["path"],
            }
        )
    return rows


def jira_search(env: dict, jql: str, fields: str) -> list[dict]:
    domain = env.get("JIRA_DOMAIN")
    email = env.get("JIRA_EMAIL")
    token = env.get("JIRA_TOKEN")
    if not (domain and email and token):
        raise SystemExit(f"Missing Jira credentials in {graph_auth.load_config()['jiraEnvPath']}")
    url = f"https://{domain}/rest/api/3/search/jql?" + urllib.parse.urlencode(
        {"jql": jql, "fields": fields, "maxResults": "100"}
    )
    basic = base64.b64encode(f"{email}:{token}".encode()).decode()
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "Authorization": f"Basic {basic}"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Jira search failed ({e.code}): {e.read().decode()[:400]}")
    if not data.get("issues") and data.get("errorMessages"):
        raise SystemExit("Jira search failed: " + "; ".join(data["errorMessages"]))
    return data.get("issues") or []


def ticket_fields(issue: dict) -> dict:
    f = issue["fields"]
    cat = f.get("customfield_14799") or f.get("customfield_13217")
    category = None
    if isinstance(cat, dict):
        category = cat.get("value")
        child = (cat.get("child") or {}).get("value")
        if child:
            category = f"{category}/{child}"
    return {
        "key": issue["key"],
        "summary": f.get("summary") or "",
        "type": (f.get("issuetype") or {}).get("name") or "",
        "status": (f.get("status") or {}).get("name") or "",
        "points": f.get("customfield_10090"),
        "category": category,
        "resolved": (f.get("resolutiondate") or "")[:10] or None,
        "updated": (f.get("updated") or "")[:10] or None,
    }


def key_in_ranges(key: str, ranges: list) -> bool:
    try:
        proj, num_s = key.split("-", 1)
        num = int(num_s)
    except ValueError:
        return False
    for start, end in ranges:
        sp, sn = start.split("-", 1)
        ep, en = end.split("-", 1)
        if proj == sp == ep and int(sn) <= num <= int(en):
            return True
    return False


def irius_match(ticket: dict, cfg: dict, has_commits: bool) -> bool:
    ir = cfg["iriusrisk"]
    key = ticket["key"]
    summary = ticket["summary"]
    extra = set(ir.get("extraKeys") or [])
    if not key.startswith("ENT-"):
        return False
    if key_in_ranges(key, ir.get("keyRanges") or []):
        return True
    if key in extra:
        return has_commits
    if re.search(ir["summaryRegex"], summary, re.I):
        if has_commits:
            return True
        return bool(re.search(ir.get("commentOnlySummaryRegex") or ir["summaryRegex"], summary, re.I))
    return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("month", help="YYYY-MM")
    args = parser.parse_args()
    year, month = map(int, args.month.split("-"))
    since, until, _ = month_range(year, month)
    cfg = graph_auth.load_config()
    commits: list[dict] = []
    for repo in cfg["repos"]:
        commits.extend(git_commits(repo, since, until))
    keys = sorted({k for c in commits for k in c["keys"]})
    env = load_env(cfg["jiraEnvPath"])
    env.update({k: os.environ[k] for k in ("JIRA_EMAIL", "JIRA_TOKEN", "JIRA_DOMAIN") if k in os.environ})
    fields = "summary,status,issuetype,resolutiondate,updated,customfield_14799,customfield_13217,customfield_10090"
    tickets: dict[str, dict] = {}
    if keys:
        jql = f"key in ({', '.join(keys)})"
        for issue in jira_search(env, jql, fields):
            t = ticket_fields(issue)
            tickets[t["key"]] = t
    irius_keys = []
    for start_k, end_k in (cfg.get("iriusrisk") or {}).get("keyRanges") or []:
        proj, a = start_k.split("-", 1)
        _, b = end_k.split("-", 1)
        irius_keys.extend(f"{proj}-{n}" for n in range(int(a), int(b) + 1))
    irius_keys.extend((cfg.get("iriusrisk") or {}).get("extraKeys") or [])
    irius_jql = (
        f'(summary ~ "Forum Mobile (Apple iOS)" OR summary ~ "IriusRisk" '
        f'OR key in ({", ".join(irius_keys)})) '
        f'AND updated >= "{since}" AND updated < "{until}"'
    )
    for issue in jira_search(env, irius_jql, fields):
        t = ticket_fields(issue)
        tickets.setdefault(t["key"], t)
    commit_keys = {k for c in commits for k in c["keys"]}
    out_tickets = []
    for t in tickets.values():
        has_commits = t["key"] in commit_keys
        t["hasCommits"] = has_commits
        t["commitCount"] = sum(1 for c in commits if t["key"] in c["keys"])
        t["iriusrisk"] = irius_match(t, cfg, has_commits)
        out_tickets.append(t)
    out_tickets.sort(key=lambda t: t["key"])
    json.dump(
        {
            "month": args.month,
            "since": since,
            "until": until,
            "commits": commits,
            "tickets": out_tickets,
        },
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
