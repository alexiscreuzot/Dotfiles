---
name: qa-forum-android
description: >
  QA a Forum Android build on the emulator. Use when the user asks to test or
  QA an Android ticket, run/install an Android build on the emulator, or
  invokes the qa-android command. Lists the user's Jira tickets in QA with PRs
  in sorenson-eng/forum-android, downloads the matching Firebase App
  Distribution build, then installs and launches it via adb.
---

# QA Forum Android ticket

1. Fetch the user's Jira tickets in `QA To Do` / `QA In Progress` (needs Forum-iOS or Android `.env`: `JIRA_EMAIL`, `JIRA_TOKEN`, `JIRA_DOMAIN`).
2. Keep only tickets with PRs in `sorenson-eng/forum-android` (`gh search prs`).
3. Ask which ticket to test.
4. Exchange the firebase CLI's stored OAuth token for an access token; if stale, tell the user to run `firebase login` and stop.
5. Resolve the Firebase app id from package `com.waverlylabs.audience.translate` in project `586530322371`.
6. Pick the newest App Distribution release whose notes mention the ticket key; fall back to asking the user to pick from recent releases.
7. Download the APK, boot the emulator (AVD `forum`) if no device is attached, `adb install -r`, launch, report version + ticket URL.

## Examples

- User: `qa android` → list Android QA tickets, ask which one, install its build on the emulator.
- User: `test ENT-2931 on the android emulator` → skip the ticket picker, go straight to the release lookup + install for ENT-2931.
- User: `run the latest android QA build` → skip Jira, pick the most recent App Distribution release, install + launch.
