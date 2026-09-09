# Scrum hours from Outlook

A published ICS URL is unauthenticated — anyone with the link can fetch it. Prefer a local drag-to-Desktop `.ics` if that worries you.

If you do use a published feed, set it to **Can view all details** (not availability / free-busy). Availability-only feeds have titles `Busy` / `Tentative`, so Scrum cannot be detected.

The URL is stored locally in `config.json` `icsUrl` (not in any repo).

```bash
python3 ~/.cursor/monthly-hours/report.py 2026-08
python3 ~/.cursor/monthly-hours/scrum-hours.py 2026-08 --all
```

## New Outlook for Mac (what you have)

1. Open **Calendar**.
2. Show August (month or week view).
3. Select the Scrum / standup / planning / retro meetings (`Cmd`-click to multi-select).
4. Drag the selection onto the Desktop. Outlook writes a private `.ics` file.
5. Run the command above with that path.

You can drag a whole day or week if that is faster; the script keeps only titles matching `scrum|standup|daily|sprint planning|retro|retrospective|refinement|grooming|sprint review`.

## If drag does not create a file

Turn off New Outlook (Outlook menu → **Legacy Outlook** / uncheck New Outlook), then **File → Export**, or drag events from Calendar to the Desktop the same way.

## After IT approves Graph

`python3 ~/.cursor/monthly-hours/graph-auth.py login` and drop `--ics`.
