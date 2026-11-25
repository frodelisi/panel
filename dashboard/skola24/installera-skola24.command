#!/bin/zsh
# Gör så att Mac minin läser ditt schema i Skola24 själv.
# Ett Skola24-fönster öppnas och får stå kvar (minimera det): Skola24 kommer bara ihåg inloggningen
# medan fönstret är öppet. Logga in där och öppna ditt schema; sedan sköter Mac minin resten.
cd "$(dirname "$0")"
set -e
DIR="$HOME/Library/Application Support/Panel/skola24"
mkdir -p "$DIR"

echo "1/4 Installerar en egen webbläsare för schemat (tar några minuter första gången)…"
if [ ! -x "$DIR/venv/bin/python" ]; then /usr/bin/python3 -m venv "$DIR/venv"; fi
"$DIR/venv/bin/python" -m pip install -q --upgrade pip playwright
"$DIR/venv/bin/python" -m playwright install chromium

echo "2/3 Startar Skola24-fönstret (startar själv igen om det stängs eller Macen startas om)…"
AGENT="$HOME/Library/LaunchAgents/se.panel.skola24.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>se.panel.skola24</string>
  <key>ProgramArguments</key><array><string>$DIR/venv/bin/python</string><string>$PWD/skola24.py</string><string>daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/panel-skola24.log</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/panel-skola24.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$UID/se.panel.skola24 2>/dev/null || true
launchctl bootstrap gui/$UID "$AGENT"

echo "3/3 Klart!"
echo ""
echo "I Skola24-fönstret: logga in (via Skolplattformen) och öppna ditt schema så att lektionerna syns."
echo "Minimera sedan fönstret – stäng det inte. Schemat läses var 15:e minut och syns i dashboarden,"
echo "i panelen och i Google-kalendern. Går inloggningen ut får du en notis: logga in i samma fönster."
