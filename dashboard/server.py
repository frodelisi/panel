#!/usr/bin/env python3
"""Dashboarden: en liten webbserver som körs på Mac minin dygnet runt.

Visar dashboarden på http://<datorn>:8765 och sparar det du fyller i (budget, sparmål,
prenumerationer, mål …) som JSON-filer i ~/Library/Application Support/Panel/dashboard/.
Skyddas med ett lösenord (installera-dashboard.command frågar efter det).
Bara Pythons standardbibliotek används, så inget behöver installeras.
"""
import base64
import hmac
import json
import os
import re
import shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "web"
DEFAULTS = ROOT / "data"
DATA = Path.home() / "Library" / "Application Support" / "Panel" / "dashboard"
PASSWORD_FILE = DATA / "losenord"
PORT = int(os.environ.get("PORT", "8765"))
MAX_BODY = 1_000_000
NAME = re.compile(r"^[a-z]{1,20}$")


def data_names():
    return sorted(p.stem for p in DEFAULTS.glob("*.json"))


def load(name):
    """Dina sparade uppgifter; första gången en kopia av standardfilen."""
    path = DATA / f"{name}.json"
    if not path.exists():
        DATA.mkdir(parents=True, exist_ok=True)
        shutil.copy(DEFAULTS / f"{name}.json", path)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(name, value):
    DATA.mkdir(parents=True, exist_ok=True)
    tmp = DATA / f".{name}.json.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DATA / f"{name}.json")


class Handler(BaseHTTPRequestHandler):
    server_version = "Dashboard"

    def authorized(self):
        try:
            password = PASSWORD_FILE.read_text(encoding="utf-8").strip()
        except OSError:
            password = ""
        if not password:
            self.reply(500, "text/plain", "Inget lösenord satt. Kör installera-dashboard.command.".encode())
            return False
        header = self.headers.get("Authorization", "")
        if header.startswith("Basic "):
            try:
                _, _, given = base64.b64decode(header[6:]).decode("utf-8").partition(":")
                if hmac.compare_digest(given.encode(), password.encode()):
                    return True
            except ValueError:
                pass
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Dashboard", charset="UTF-8"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def reply(self, code, kind, body):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.authorized():
            return
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.reply(200, "text/html; charset=utf-8", (WEB / "index.html").read_bytes())
        elif path == "/api/all":
            body = json.dumps({n: load(n) for n in data_names()}, ensure_ascii=False).encode()
            self.reply(200, "application/json; charset=utf-8", body)
        else:
            self.reply(404, "text/plain", b"Finns inte")

    def do_POST(self):
        if not self.authorized():
            return
        m = re.fullmatch(r"/api/save/([a-z]+)", self.path)
        length = int(self.headers.get("Content-Length") or 0)
        if not m or not NAME.match(m.group(1)) or m.group(1) not in data_names():
            return self.reply(404, "text/plain", b"Finns inte")
        if length > MAX_BODY:
            return self.reply(413, "text/plain", b"For stort")
        try:
            value = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self.reply(400, "text/plain", b"Fel format")
        save(m.group(1), value)
        self.reply(200, "application/json", b'{"ok":true}')

    def log_message(self, fmt, *args):
        pass  # håll loggen tyst


if __name__ == "__main__":
    print(f"Dashboarden körs på http://localhost:{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
