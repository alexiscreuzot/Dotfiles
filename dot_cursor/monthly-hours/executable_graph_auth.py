#!/usr/bin/env python3
"""Browser login + token refresh for Microsoft Graph. Tokens stay in this folder."""
from __future__ import annotations

import base64
import hashlib
import http.server
import json
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

DIR = Path(__file__).resolve().parent
CONFIG_PATH = DIR / "config.json"
TOKEN_PATH = DIR / "graph-token.json"


def load_config() -> dict:
    return json.loads(CONFIG_PATH.read_text())


def _graph_cfg() -> dict:
    return load_config()["graph"]


def _token_url() -> str:
    return f"https://login.microsoftonline.com/{_graph_cfg()['tenant']}/oauth2/v2.0/token"


def _device_url() -> str:
    return f"https://login.microsoftonline.com/{_graph_cfg()['tenant']}/oauth2/v2.0/devicecode"


def _post(url: str, data: dict) -> dict:
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            parsed = json.loads(detail)
        except ValueError:
            parsed = {"error": "http_error", "error_description": detail[:500]}
        parsed["_http"] = e.code
        return parsed


def save_tokens(payload: dict) -> dict:
    expires_in = int(payload.get("expires_in") or 3600)
    stored = {
        "access_token": payload["access_token"],
        "refresh_token": payload.get("refresh_token"),
        "expires_at": (datetime.now(timezone.utc) + timedelta(seconds=expires_in - 60)).isoformat(),
        "scope": payload.get("scope"),
        "token_type": payload.get("token_type", "Bearer"),
    }
    if TOKEN_PATH.exists():
        old = json.loads(TOKEN_PATH.read_text())
        if not stored.get("refresh_token"):
            stored["refresh_token"] = old.get("refresh_token")
    TOKEN_PATH.write_text(json.dumps(stored, indent=2) + "\n")
    TOKEN_PATH.chmod(0o600)
    return stored


def load_tokens() -> dict | None:
    if not TOKEN_PATH.exists():
        return None
    return json.loads(TOKEN_PATH.read_text())


def refresh(tokens: dict) -> dict:
    cfg = _graph_cfg()
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        raise SystemExit("No refresh token. Run: python3 graph-auth.py login")
    payload = _post(
        _token_url(),
        {
            "client_id": cfg["clientId"],
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "scope": " ".join(cfg["scopes"]),
        },
    )
    if "access_token" not in payload:
        raise SystemExit(
            "Token refresh failed: "
            + payload.get("error_description", payload.get("error", json.dumps(payload)[:300]))
        )
    return save_tokens(payload)


def access_token() -> str:
    tokens = load_tokens()
    if not tokens:
        raise SystemExit("Not logged in. Run: python3 graph-auth.py login")
    expires_at = datetime.fromisoformat(tokens["expires_at"])
    if expires_at <= datetime.now(timezone.utc):
        tokens = refresh(tokens)
    return tokens["access_token"]


def _pkce() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _authorize_url() -> str:
    return f"https://login.microsoftonline.com/{_graph_cfg()['tenant']}/oauth2/v2.0/authorize"


def login_browser() -> None:
    """Sign in in the browser; the redirect comes back to localhost. No device code."""
    cfg = _graph_cfg()
    verifier, challenge = _pkce()
    port = _free_port()
    redirect = f"http://localhost:{port}/"
    state = secrets.token_urlsafe(16)
    result: dict = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            return

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            if qs.get("code"):
                result["code"] = qs["code"][0]
                result["state"] = (qs.get("state") or [""])[0]
                body = b"<html><body><p>Signed in. You can close this tab.</p></body></html>"
                self.send_response(200)
            else:
                result["error"] = (qs.get("error_description") or qs.get("error") or ["missing code"])[0]
                body = f"<html><body><p>Login failed: {result['error']}</p></body></html>".encode()
                self.send_response(400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    params = {
        "client_id": cfg["clientId"],
        "response_type": "code",
        "redirect_uri": redirect,
        "response_mode": "query",
        "scope": " ".join(cfg["scopes"]),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "login_hint": cfg.get("loginHint") or "",
        "prompt": "select_account",
    }
    url = _authorize_url() + "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v})
    print("GRAPH_LOGIN", flush=True)
    print("Opening your browser to sign in as", cfg.get("loginHint") or "your work account", flush=True)
    print("If it does not open:", url, flush=True)
    try:
        subprocess.Popen(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    thread.join(timeout=300)
    server.server_close()
    if not result.get("code"):
        raise SystemExit("Login failed: " + (result.get("error") or "timed out waiting for the browser"))
    if result.get("state") and result["state"] != state:
        raise SystemExit("Login failed: state mismatch")
    payload = _post(
        _token_url(),
        {
            "client_id": cfg["clientId"],
            "grant_type": "authorization_code",
            "code": result["code"],
            "redirect_uri": redirect,
            "code_verifier": verifier,
            "scope": " ".join(cfg["scopes"]),
        },
    )
    if "access_token" not in payload:
        raise SystemExit(
            "Token exchange failed: "
            + payload.get("error_description", payload.get("error", json.dumps(payload)[:300]))
        )
    save_tokens(payload)
    print("LOGIN_OK", flush=True)
    print("token_file:", TOKEN_PATH, flush=True)


def login_device() -> None:
    cfg = _graph_cfg()
    start = _post(
        _device_url(),
        {
            "client_id": cfg["clientId"],
            "scope": " ".join(cfg["scopes"]),
        },
    )
    if "device_code" not in start:
        raise SystemExit(
            "Device-code start failed: "
            + start.get("error_description", start.get("error", json.dumps(start)[:300]))
        )
    uri = start.get("verification_uri_complete") or start.get("verification_uri") or "https://login.microsoft.com/device"
    print("GRAPH_LOGIN", flush=True)
    print("A browser tab will open. Sign in as", cfg.get("loginHint") or "your work account", flush=True)
    print("Microsoft will not email or text a code.", flush=True)
    print("If the page asks for a code, type:", start["user_code"], flush=True)
    print("url:", uri, flush=True)
    try:
        subprocess.Popen(["open", uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    interval = int(start.get("interval") or 5)
    device_code = start["device_code"]
    deadline = time.time() + int(start.get("expires_in") or 900)
    while time.time() < deadline:
        time.sleep(interval)
        payload = _post(
            _token_url(),
            {
                "client_id": cfg["clientId"],
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": device_code,
            },
        )
        if "access_token" in payload:
            save_tokens(payload)
            print("LOGIN_OK", flush=True)
            print("token_file:", TOKEN_PATH, flush=True)
            return
        err = payload.get("error")
        if err in ("authorization_pending", "slow_down"):
            if err == "slow_down":
                interval += 2
            continue
        raise SystemExit(
            "Login failed: "
            + payload.get("error_description", err or json.dumps(payload)[:300])
        )
    raise SystemExit("Login timed out. Run graph-auth.py login again.")


def login(mode: str = "browser") -> None:
    if mode == "device":
        login_device()
    else:
        login_browser()


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "token"
    if cmd == "login":
        mode = "browser" if "--browser" in sys.argv else "device"
        login(mode)
    elif cmd == "token":
        print(access_token())
    elif cmd == "status":
        tokens = load_tokens()
        if not tokens:
            print("logged_out")
            sys.exit(1)
        print("expires_at:", tokens.get("expires_at"))
        print("has_refresh:", bool(tokens.get("refresh_token")))
    else:
        sys.exit(f"Usage: {sys.argv[0]} login|token|status")


if __name__ == "__main__":
    main()
