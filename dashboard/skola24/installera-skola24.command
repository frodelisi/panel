#!/bin/zsh
# Gör så att Mac minin läser ditt schema i Skola24 själv (06, 09, 12, 15 och 18 varje dag, och vid start).
# Första gången: ett webbläsarfönster öppnas där du loggar in och öppnar ditt schema.
cd "$(dirname "$0")"
set -e
DIR="$HOME/Library/Application Support/Panel/skola24"
mkdir -p "$DIR"

echo "1/4 Installerar en egen webbläsare för schemat (tar några minuter första gången)…"
if [ ! -x "$DIR/venv/bin/python" ]; then /usr/bin/python3 -m venv "$DIR/venv"; fi
"$DIR/venv/bin/python" -m pip install -q --upgrade pip playwright
"$DIR/venv/bin/python" -m playwright install chromium

echo "2/4 Logga in i Skola24 i fönstret som öppnas."
"$DIR/venv/bin/python" skola24.py login

echo "3/4 Läser schemat varje dag…"
AGENT="$HOME/Library/LaunchAgents/se.panel.skola24.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>se.panel.skola24</string>
  <key>ProgramArguments</key><array><string>$DIR/venv/bin/python</string><string>$PWD/skola24.py</string><string>fetch</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key><array>
    <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>5</integer></dict>
    <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>5</integer></dict>
    <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>5</integer></dict>
    <dict><key>Hour</key><integer>15</integer><key>Minute</key><integer>5</integer></dict>
    <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>5</integer></dict>
  </array>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/panel-skola24.log</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/panel-skola24.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$UID/se.panel.skola24 2>/dev/null || true
launchctl bootstrap gui/$UID "$AGENT"

echo "4/4 Läser schemat nu…"
"$DIR/venv/bin/python" skola24.py fetch || true
echo ""
echo "Klart! Schemat syns i dashboarden (Skola), i panelens Nästa-kort och i din Google-kalender."
echo "Går inloggningen ut får du en notis. Kör då logga-in-skola24.command."
