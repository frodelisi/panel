#!/bin/zsh
# Bygger Panel och installerar den i ~/Applications. Startar automatiskt när du loggar in.
# Kör igen när du fått en ny version, så byggs den om.
cd "$(dirname "$0")"
set -e
TYST=0; [ "$1" = "--tyst" ] && TYST=1   # används när panelen uppdaterar sig själv

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Macen behöver Apples utvecklarverktyg (gratis, ungefär 10 minuter)."
  echo "En ruta öppnas nu: tryck Installera. Kör sedan installera.command igen."
  xcode-select --install
  exit 0
fi

echo "1/4 Bygger Panel…"
if ! swift build -c release 2> build-fel.txt; then
  echo ""
  echo "Bygget misslyckades. Skicka filen build-fel.txt (ligger i den här mappen) till Claude."
  exit 1
fi
rm -f build-fel.txt

echo "2/4 Gör appen…"
APP="$HOME/Applications/Panel.app"
pkill -x Panel 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Panel "$APP/Contents/MacOS/Panel"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>se.panel.app</string>
  <key>CFBundleName</key><string>Panel</string>
  <key>CFBundleExecutable</key><string>Panel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Panel läser dina senaste mail från Mail-appen.</string>
  <key>NSCalendarsUsageDescription</key><string>Panel visar dina deadlines från Kalender.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Panel visar dina deadlines från Kalender.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "3/4 Startar automatiskt vid inloggning…"
AGENT="$HOME/Library/LaunchAgents/se.panel.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>se.panel.app</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

# Var mappen ligger (för automatiska uppdateringar) och vilken version som är installerad.
SUPPORT="$HOME/Library/Application Support/Panel"
mkdir -p "$SUPPORT"
pwd > "$SUPPORT/repo-path"
if git rev-parse HEAD >/dev/null 2>&1; then
  echo "$(date '+%e %b %H:%M' | sed 's/^ //') · $(git log -1 --format=%s)" > "$SUPPORT/version"
else
  date '+%e %b %H:%M' | sed 's/^ //' > "$SUPPORT/version"
fi

# Första installationen: ljus bakgrund och en Docka som syns (sparar hur det var, så att avinstallera.command kan ångra).
if [ $TYST = 0 ] && [ ! -d "$SUPPORT/backup" ]; then
  echo "   Ljus bakgrund och Docka…"
  mkdir -p "$SUPPORT/backup"
  defaults export com.apple.dock "$SUPPORT/backup/dock.plist"
  osascript -e 'tell application "System Events" to get picture of current desktop' > "$SUPPORT/backup/bakgrund.txt" 2>/dev/null || true
  cp bakgrund.jpg "$SUPPORT/bakgrund.jpg"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$SUPPORT/bakgrund.jpg\"" || true
  defaults write com.apple.dock autohide -bool false
  defaults write com.apple.dock tilesize -int 54
  defaults write com.apple.dock magnification -bool true
  defaults write com.apple.dock largesize -int 70
  defaults write com.apple.dock show-recents -bool false
  killall Dock || true
  defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
fi

# Körs dashboarden på den här datorn (Mac minin)? Starta om den så att nya versionen gäller.
if [ -f "$HOME/Library/LaunchAgents/se.panel.dashboard.plist" ]; then
  launchctl kickstart -k gui/$UID/se.panel.dashboard 2>/dev/null || true
fi

echo "4/4 Startar Panel…"
open "$APP"
echo ""
echo "Klart! För musen upp till kameran (eller mitten av skärmens överkant) så fälls panelen ner."
echo "Inställningar: kugghjulet i panelen, eller dubbelklicka på Panel i ~/Applications."
