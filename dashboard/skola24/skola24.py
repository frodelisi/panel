#!/usr/bin/env python3
"""Läser ditt schema i Skola24 med en webbläsare som Mac minin har loggat in i.

  python3 skola24.py login   – öppnar ett fönster: logga in och gå till ditt schema, stäng sedan fönstret
  python3 skola24.py fetch   – läser schemat (den här och nästa vecka) utan att visa något fönster

Schemat sparas i dashboardens skola.json (fältet "schema") och läggs in i din Google-kalender
(samma Google-inloggning som panelen på den här datorn), så att det syns överallt.
Inloggningen sparas i en egen webbläsarprofil på den här datorn, aldrig någon annanstans.
"""
import copy
import datetime as dt
import json
import os
import hashlib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

HOME = Path.home() / "Library" / "Application Support" / "Panel"
PROFILE = HOME / "skola24" / "profil"
STATE = HOME / "skola24" / "state.json"           # adressen till ditt schema
DATA = HOME / "dashboard"
SKOLA = DATA / "skola.json"
START_URL = "https://www.skola24.se/"


def notify(text):
    subprocess.run(["osascript", "-e", f'display notification "{text}" with title "Skolschema"'], check=False)


def load_state():
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_skola(schema=None, status=None):
    DATA.mkdir(parents=True, exist_ok=True)
    try:
        skola = json.loads(SKOLA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        skola = {"deadlines": [], "schema": []}
    if schema is not None:
        skola["schema"] = schema
    if status is not None:
        skola["schemaStatus"] = status
    tmp = SKOLA.with_suffix(".tmp")
    tmp.write_text(json.dumps(skola, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, SKOLA)


def login():
    PROFILE.mkdir(parents=True, exist_ok=True)
    seen = {}
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(str(PROFILE), headless=False, viewport={"width": 1280, "height": 860})
        page = ctx.pages[0] if ctx.pages else ctx.new_page()

        def on_request(req):
            if "render/timetable" in req.url and req.method == "POST":
                try:
                    seen["url"] = req.frame.page.url      # fliken där schemat visades (kan vara en ny flik)
                except Exception:
                    pass

        ctx.on("request", on_request)
        page.goto(load_state().get("url") or START_URL)
        print("Logga in (kryssa i \"Håll mig inloggad\" om det finns) och öppna ditt schema.")
        print("Stäng sedan webbläsarfönstret.")
        try:
            while ctx.pages:
                ctx.pages[0].wait_for_timeout(500)
        except Exception:
            pass
        try:
            ctx.close()
        except Exception:
            pass
    if seen.get("url"):
        STATE.write_text(json.dumps({"url": seen["url"]}), encoding="utf-8")
        print("Klart! Schemat hittades. Mac minin läser det nu själv.")
        return True
    print("Hittade inget schema. Kör igen och se till att ditt schema syns innan du stänger fönstret.")
    return False


# Kurskoder från Skola24 (t.ex. MATE2B00X) → vanliga ämnesnamn.
SUBJECTS = {
    "ENGE": "Engelska", "MATE": "Matematik", "SVEN": "Svenska", "SVAS": "Svenska som andraspråk",
    "SAMH": "Samhällskunskap", "HIST": "Historia", "GEOG": "Geografi", "RELI": "Religion",
    "FILO": "Filosofi", "PSYK": "Psykologi", "IDRO": "Idrott", "NAKU": "Naturkunskap",
    "BIOL": "Biologi", "KEMI": "Kemi", "FYSI": "Fysik", "FOET": "Företagsekonomi",
    "ENTR": "Entreprenörskap", "MARK": "Marknadsföring", "PRIV": "Privatjuridik", "LEDA": "Ledarskap",
    "PROG": "Programmering", "WEBB": "Webbutveckling", "BILD": "Bild", "MUSI": "Musik",
    "INFO": "Informationsteknik", "DIGI": "Digitalt skapande", "KOMM": "Kommunikation",
}
LANGUAGES = {"SPA": "Spanska", "TYS": "Tyska", "FRA": "Franska", "ITA": "Italienska", "KIN": "Kinesiska", "JAP": "Japanska"}


def pretty(code):
    c = (code or "").strip()
    up = c.upper()
    if up.startswith("MODO"):                     # moderna språk: MODO2000XSPA
        for k, v in LANGUAGES.items():
            if up.endswith(k):
                return v
        return "Moderna språk"
    return SUBJECTS.get(up[:4], c) if len(up) >= 5 and up[:4].isalpha() and up[4].isdigit() else c


def lessons_from(data, week):
    """Skola24 skickar lektioner som lessonInfo: texts, timeStart, timeEnd, dayOfWeekNumber."""
    info = (data.get("data") or {}).get("lessonInfo") or []
    out = []
    for l in info:
        texts = [t for t in (l.get("texts") or []) if t and t.strip()]
        if not texts or not l.get("timeStart"):
            continue
        out.append({
            "vecka": week,
            "dag": l.get("dayOfWeekNumber"),            # 1 = måndag
            "start": l["timeStart"][:5],
            "slut": (l.get("timeEnd") or "")[:5],
            "amne": pretty(texts[0]),
            "kurs": texts[0],
            "larare": texts[1] if len(texts) > 2 else "",
            "sal": texts[-1] if len(texts) > 1 else "",
            "text": texts,
        })
    return sorted(out, key=lambda x: (x["vecka"], x["dag"] or 0, x["start"]))


# ---------- Google-kalendern ----------

def google_token():
    """Kontot och en färsk åtkomstnyckel, från panelens inställningar på den här datorn."""
    try:
        config = json.loads((HOME / "config.json").read_text(encoding="utf-8"))
        secrets = json.loads((HOME / "secrets.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    accounts = [a for a in (secrets.get("google.accounts") or "").split(",") if a]
    account = (config.get("skolaKalenderKonto") or config.get("tasksAccount") or (accounts[0] if accounts else "")).lower()
    refresh = secrets.get(f"google.refresh.{account}")
    if not (account and refresh and config.get("googleClientID") and secrets.get("google.secret")):
        return None, None
    body = urllib.parse.urlencode({"refresh_token": refresh, "client_id": config["googleClientID"],
                                   "client_secret": secrets["google.secret"], "grant_type": "refresh_token"}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=body), timeout=20) as r:
        return account, json.loads(r.read())["access_token"]


def gcal(token, method, path, body=None, query=None):
    url = "https://www.googleapis.com/calendar/v3/calendars/primary/events" + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def lesson_date(lesson):
    today = dt.date.today()
    year = today.isocalendar()[0]
    if lesson["vecka"] < today.isocalendar()[1] - 26:      # över ett årsskifte
        year += 1
    return dt.date.fromisocalendar(year, lesson["vecka"], int(lesson["dag"]))


def sync_google(schema):
    """Lägger in lektionerna i Google-kalendern. Varje lektion får ett fast id, så att den uppdateras i
    stället för att dubbleras; lektioner som inte längre finns i schemat tas bort."""
    try:
        account, token = google_token()
    except (urllib.error.URLError, KeyError, ValueError) as e:
        return f"Google: {e}"
    if not token:
        return "Logga in med Google i Panel på Mac minin för att få schemat i kalendern."
    wanted = {}
    for l in schema:
        if not l.get("dag"):
            continue
        day = lesson_date(l)
        key = f"{day}|{l['start']}|{l['amne']}"
        event_id = "s24" + hashlib.sha1(key.encode()).hexdigest()    # 0-9a-f är tillåtet i Googles id
        title = l["amne"] + (f" · {l['sal']}" if l.get("sal") and l["sal"] != l["amne"] else "")
        wanted[event_id] = {
            "id": event_id, "summary": title, "description": " · ".join(l.get("text") or []),
            "location": l.get("sal") or "", "colorId": "7",
            "start": {"dateTime": f"{day}T{l['start']}:00", "timeZone": "Europe/Stockholm"},
            "end": {"dateTime": f"{day}T{l['slut'] or l['start']}:00", "timeZone": "Europe/Stockholm"},
            "reminders": {"useDefault": False},
            "extendedProperties": {"private": {"panelSkola24": "1"}},
            "transparency": "transparent",
        }
    if not wanted:
        return None
    days = sorted(lesson_date(l) for l in schema if l.get("dag"))
    existing = gcal(token, "GET", "", query={
        "privateExtendedProperty": "panelSkola24=1", "singleEvents": "true", "maxResults": "500",
        "timeMin": f"{days[0]}T00:00:00Z", "timeMax": f"{days[-1] + dt.timedelta(days=1)}T00:00:00Z"})
    have = {e["id"] for e in existing.get("items", [])}
    for event_id, event in wanted.items():
        try:
            if event_id in have:
                gcal(token, "PUT", f"/{event_id}", event)
            else:
                gcal(token, "POST", "", event)
        except urllib.error.HTTPError as e:
            if e.code == 409:          # fanns sedan tidigare (t.ex. borttagen): uppdatera i stället
                gcal(token, "PUT", f"/{event_id}", {**event, "status": "confirmed"})
            else:
                raise
    for event_id in have - set(wanted):
        gcal(token, "DELETE", f"/{event_id}")
    return None


def fetch():
    url = load_state().get("url")
    if not url:
        save_skola(status={"ok": False, "fel": "Inte inloggad. Kör logga-in-skola24.command på Mac minin."})
        return False
    captured = {}
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(str(PROFILE), headless=True)
        page = ctx.new_page()

        def on_response(res):
            if "render/timetable" in res.url and res.request.method == "POST" and "body" not in captured:
                try:
                    captured["body"] = res.json()
                    captured["request"] = res.request
                except Exception:
                    pass

        page.on("response", on_response)
        try:
            page.goto(url, wait_until="networkidle", timeout=60000)
            page.wait_for_timeout(3000)
        except Exception:
            pass

        if "body" not in captured:
            DATA.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(DATA / "skola24-fel.png"))
            login_page = any(w in page.url for w in ("login", "microsoftonline", "sso", "auth"))
            fel = "Inloggningen har gått ut. Kör logga-in-skola24.command på Mac minin." if login_page \
                else "Kunde inte läsa schemat (se skola24-fel.png i dashboardens mapp)."
            save_skola(status={"ok": False, "fel": fel, "tid": dt.datetime.now().isoformat(timespec="minutes")})
            if login_page:
                notify("Logga in i Skola24 igen på Mac minin")
            ctx.close()
            return False

        (DATA / "skola24-raw.json").write_text(json.dumps(captured["body"], ensure_ascii=False)[:500_000], encoding="utf-8")
        this_week = dt.date.today().isocalendar()[1]
        schema = lessons_from(captured["body"], this_week)

        # Nästa vecka: samma fråga som sidan själv ställde, med veckan ändrad.
        try:
            req = captured["request"]
            body = json.loads(req.post_data or "{}")
            if "week" in body:
                nxt = copy.deepcopy(body)
                nxt["week"] = (dt.date.today() + dt.timedelta(days=7)).isocalendar()[1]
                headers = {k: v for k, v in req.headers.items() if k.lower() not in ("content-length", "cookie", "host")}
                res = ctx.request.post(req.url, data=json.dumps(nxt), headers=headers)
                if res.ok:
                    schema += lessons_from(res.json(), nxt["week"])
        except Exception:
            pass

        ctx.close()
    try:
        kalender = sync_google(schema)
    except Exception as e:                      # kalendern får aldrig stoppa själva schemat
        kalender = f"Google-kalendern: {e}"
    status = {"ok": True, "tid": dt.datetime.now().isoformat(timespec="minutes"), "lektioner": len(schema)}
    if kalender:
        status["kalender"] = kalender
    save_skola(schema=schema, status=status)
    print(f"Läste {len(schema)} lektioner." + (f" {kalender}" if kalender else " Lagt in i Google-kalendern."))
    return True


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    ok = login() if mode == "login" else fetch()
    sys.exit(0 if ok else 1)
