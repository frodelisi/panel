#!/bin/zsh
# Gör Mac minin till server för dashboarden. Den startar när Macen startar och körs dygnet runt.
# Kör igen om du vill byta lösenord. Ta bort med: launchctl bootout gui/$UID/se.panel.dashboard
cd "$(dirname "$0")"
DATA="$HOME/Library/Application Support/Panel/dashboard"
mkdir -p "$DATA"

echo "Välj ett lösenord för dashboarden (syns inte när du skriver):"
read -s PW
echo
if [ -z "$PW" ]; then echo "Inget lösenord, avbryter."; exit 1; fi
print -r -- "$PW" > "$DATA/losenord"
chmod 600 "$DATA/losenord"

PY=/usr/bin/python3
AGENT="$HOME/Library/LaunchAgents/se.panel.dashboard.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>se.panel.dashboard</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$PWD/server.py</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/panel-dashboard.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$UID/se.panel.dashboard 2>/dev/null
launchctl bootstrap gui/$UID "$AGENT"

NAME="$(scutil --get LocalHostName 2>/dev/null)"
sleep 1
echo ""
echo "Klart! Dashboarden körs nu på den här datorn."
echo "  Här:                     http://localhost:8765"
echo "  Från MacBook och mobil:  http://$NAME.local:8765   (samma wifi)"
echo ""
echo "Skriv in den adressen i Panels inställningar på MacBooken (Dashboard), så öppnar korten rätt sida."
echo "Låt inte Macen somna: Systeminställningar → Energi → Förhindra automatisk vila."
open "http://localhost:8765"
